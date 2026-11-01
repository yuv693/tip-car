import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveRideMapScreen extends StatefulWidget {
  final String rideId;
  final String bookingId;
  final bool isDriver;

  const LiveRideMapScreen({
    super.key,
    required this.rideId,
    required this.bookingId,
    required this.isDriver,
  });

  @override
  State<LiveRideMapScreen> createState() => _LiveRideMapScreenState();
}

class _LiveRideMapScreenState extends State<LiveRideMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _locationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _pickupSubscription;
  LatLng? _driverPosition;
  LatLng? _pickupPosition;
  List<LatLng> _route = [];
  bool _sharing = false;
  bool _busy = false;
  bool _routeBusy = false;
  String _message = '';
  String _eta = 'Waiting for both locations…';
  DateTime? _lastRouteRequest;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _watchRideLocation();
    _watchPickupLocation();
  }

  LatLng? _point(Map<String, dynamic> row) {
    final lat = row['latitude'];
    final lng = row['longitude'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  void _watchRideLocation() {
    _locationSubscription = _db
        .from('ride_locations')
        .stream(primaryKey: ['ride_id'])
        .eq('ride_id', widget.rideId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final point = _point(rows.first);
      if (point == null) return;
      setState(() => _driverPosition = point);
      _refreshRoute();
    }, onError: (Object error) {
      if (mounted) setState(() => _message = 'Could not receive driver location: $error');
    });
  }

  void _watchPickupLocation() {
    _pickupSubscription = _db
        .from('booking_pickups')
        .stream(primaryKey: ['booking_id'])
        .eq('booking_id', widget.bookingId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final point = _point(rows.first);
      if (point == null) return;
      setState(() => _pickupPosition = point);
      _refreshRoute();
    }, onError: (Object error) {
      if (mounted) setState(() => _message = 'Could not receive pickup location: $error');
    });
  }

  Future<Position> _getCurrentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Please allow location permission in Tip Car settings.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please turn on GPS/location services.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _sharePickup() async {
    setState(() { _busy = true; _message = ''; });
    try {
      final position = await _getCurrentPosition();
      await _db.from('booking_pickups').upsert({
        'booking_id': widget.bookingId,
        'ride_id': widget.rideId,
        'passenger_id': _db.auth.currentUser!.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'booking_id');
      if (mounted) {
        setState(() {
          _pickupPosition = LatLng(position.latitude, position.longitude);
          _message = 'Pickup location shared with your driver.';
        });
      }
      _refreshRoute();
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not share pickup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSharing() async {
    setState(() { _busy = true; _message = ''; });
    try {
      final current = await _getCurrentPosition();
      await _sendPosition(current);
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Tip Car live ride',
            notificationText: 'Your live location is shared with your confirmed passenger.',
            notificationChannelName: 'Tip Car location sharing',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).listen((position) {
        _sendPosition(position).catchError((Object error) {
          if (mounted) setState(() => _message = 'Could not upload location: $error');
        });
      }, onError: (Object error) {
        if (mounted) setState(() => _message = 'Location updates stopped: $error');
      });
      if (mounted) {
        setState(() {
          _sharing = true;
          _message = 'Live location is on. You can minimize Tip Car; the Android notification stays visible.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPosition(Position position) async {
    await _db.rpc('update_my_ride_location', params: {
      'p_ride_id': widget.rideId,
      'p_latitude': position.latitude,
      'p_longitude': position.longitude,
    });
    if (!mounted) return;
    setState(() => _driverPosition = LatLng(position.latitude, position.longitude));
    _refreshRoute();
  }

  Future<void> _refreshRoute() async {
    final from = _driverPosition;
    final to = _pickupPosition;
    if (from == null || to == null || _routeBusy) { return; }
    final now = DateTime.now();
    if (_lastRouteRequest != null &&
        now.difference(_lastRouteRequest!) < const Duration(seconds: 8)) { return; }
    _lastRouteRequest = now;
    _routeBusy = true;
    try {
      final url = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
      );
      final response = await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('Route service unavailable');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) throw Exception('No driving route found');
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final points = coordinates.map((pair) {
        final values = pair as List<dynamic>;
        return LatLng((values[1] as num).toDouble(), (values[0] as num).toDouble());
      }).toList();
      final minutes = ((route['duration'] as num).toDouble() / 60).ceil();
      final km = (route['distance'] as num).toDouble() / 1000;
      if (mounted) {
        setState(() {
          _route = points;
          _eta = 'About $minutes min · ${km.toStringAsFixed(1)} km to pickup';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        _route = [];
        _eta = 'Route/ETA temporarily unavailable';
        });
      }
    } finally {
      _routeBusy = false;
    }
  }

  Future<void> _stopSharing() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (mounted) {
      setState(() {
      _sharing = false;
      _message = 'Location sharing stopped.';
      });
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _locationSubscription?.cancel();
    _pickupSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driverPosition;
    final pickup = _pickupPosition;
    final center = driver ?? pickup ?? const LatLng(21.6417, 69.6293);
    return Scaffold(
      appBar: AppBar(title: const Text('Live ride tracking')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: 14),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tipcar.app',
                ),
                if (_route.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(points: _route, strokeWidth: 5, color: const Color(0xff246bfe)),
                  ]),
                MarkerLayer(markers: [
                  if (driver != null)
                    Marker(
                      point: driver,
                      width: 54,
                      height: 54,
                      child: const Icon(Icons.directions_car_filled, size: 42, color: Color(0xff246bfe)),
                    ),
                  if (pickup != null)
                    Marker(
                      point: pickup,
                      width: 54,
                      height: 54,
                      child: const Icon(Icons.location_pin, size: 48, color: Colors.red),
                    ),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_eta, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text(driver == null ? 'Waiting for driver GPS…' : 'Blue car = driver live location'),
                Text(pickup == null ? 'Pickup point not shared yet.' : 'Red pin = passenger pickup point'),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message),
                  ),
                const SizedBox(height: 10),
                if (widget.isDriver)
                  FilledButton.icon(
                    onPressed: _busy ? null : (_sharing ? _stopSharing : _startSharing),
                    icon: Icon(_sharing ? Icons.location_off : Icons.my_location),
                    label: Text(_busy ? 'Please wait…' : (_sharing ? 'Stop live sharing' : 'Start live sharing')),
                  )
                else
                  FilledButton.icon(
                    onPressed: _busy ? null : _sharePickup,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(_busy ? 'Please wait…' : 'Share my pickup location'),
                  ),
                const Text(
                  'ETA is a road-route estimate and does not include live traffic. Location sharing requires GPS and permission; Android may pause it after force-stop or battery restrictions.',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
