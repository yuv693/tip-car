import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveRideMapScreen extends StatefulWidget {
  final String rideId;
  final bool isDriver;

  const LiveRideMapScreen({
    super.key,
    required this.rideId,
    required this.isDriver,
  });

  @override
  State<LiveRideMapScreen> createState() => _LiveRideMapScreenState();
}

class _LiveRideMapScreenState extends State<LiveRideMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _driverPosition;
  bool _sharing = false;
  bool _busy = false;
  String _message = '';

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _watchRideLocation();
  }

  void _watchRideLocation() {
    _db
        .from('ride_locations')
        .stream(primaryKey: ['ride_id'])
        .eq('ride_id', widget.rideId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      final point = LatLng(
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
      );
      setState(() => _driverPosition = point);
      _mapController.move(point, 15);
    }, onError: (Object error) {
      if (mounted) setState(() => _message = 'Could not receive location updates: $error');
    });
  }

  Future<void> _startSharing() async {
    setState(() { _busy = true; _message = ''; });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Allow location permission to share your ride position.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Please turn on GPS/location services.');
      }

      final current = await Geolocator.getCurrentPosition();
      await _sendPosition(current);
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen((position) {
        _sendPosition(position);
      }, onError: (Object error) {
        if (mounted) setState(() => _message = 'Location updates stopped: $error');
      });
      if (mounted) setState(() { _sharing = true; _message = 'Live location sharing is on.'; });
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
    final point = LatLng(position.latitude, position.longitude);
    setState(() => _driverPosition = point);
    _mapController.move(point, 15);
  }

  Future<void> _stopSharing() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (mounted) setState(() { _sharing = false; _message = 'Location sharing stopped.'; });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marker = _driverPosition;
    return Scaffold(
      appBar: AppBar(title: const Text('Live ride tracking')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: marker ?? const LatLng(21.6417, 69.6293),
                initialZoom: marker == null ? 11 : 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tipcar.app',
                ),
                if (marker != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: marker,
                      width: 52,
                      height: 52,
                      child: const Icon(
                        Icons.directions_car_filled,
                        size: 42,
                        color: Color(0xff246bfe),
                      ),
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
                Text(
                  marker == null
                      ? 'Waiting for driver location…'
                      : 'Driver location is updating on the map.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message),
                  ),
                if (widget.isDriver) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : (_sharing ? _stopSharing : _startSharing),
                    icon: Icon(_sharing ? Icons.location_off : Icons.my_location),
                    label: Text(_busy
                        ? 'Please wait…'
                        : (_sharing ? 'Stop sharing' : 'Start live sharing')),
                  ),
                  const Text(
                    'Location sharing works only while this screen stays open. Background tracking is not enabled.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
