// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

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
  final bool isDriver;
  const LiveRideMapScreen({super.key, required this.rideId, required this.isDriver});
  @override
  State<LiveRideMapScreen> createState() => _LiveRideMapScreenState();
}

class _LiveRideMapScreenState extends State<LiveRideMapScreen> {
  final _map = MapController();
  StreamSubscription<Position>? _gps;
  StreamSubscription<List<Map<String, dynamic>>>? _updates;
  LatLng? _driver, _pickup, _destination;
  List<LatLng> _approach = [], _trip = [];
  double? _pickupKm, _pickupMin, _tripKm, _tripMin;
  DateTime? _lastRoute;
  String _origin = 'Pickup', _dest = 'Destination', _message = '';
  bool _sharing = false, _busy = false, _loading = true;
  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadRide();
    _watchLocation();
  }

  Future<LatLng?> _geocode(String place) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search',
          {'q': place + ', Gujarat, India', 'format': 'jsonv2', 'limit': '1'});
      final response = await http.get(uri, headers: {'User-Agent': 'TipCarRideApp/1.0'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final rows = jsonDecode(response.body) as List;
      if (rows.isEmpty) return null;
      final row = rows.first as Map<String, dynamic>;
      return LatLng(double.parse(row['lat'].toString()), double.parse(row['lon'].toString()));
    } catch (_) { return null; }
  }

  Future<void> _loadRide() async {
    try {
      final ride = await db.from('rides').select('origin,destination')
          .eq('id', widget.rideId).single();
      _origin = ride['origin']?.toString() ?? 'Pickup';
      _dest = ride['destination']?.toString() ?? 'Destination';
      final points = await Future.wait([_geocode(_origin), _geocode(_dest)]);
      if (!mounted) return;
      setState(() { _pickup = points[0]; _destination = points[1]; _loading = false; });
      await _refreshRoutes(force: true);
      final center = _driver ?? _pickup ?? _destination;
      if (center != null && mounted) _map.move(center, 10);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _message = 'Route load failed: ' + e.toString(); });
    }
  }

  void _watchLocation() {
    _updates = db.from('ride_locations').stream(primaryKey: ['ride_id'])
        .eq('ride_id', widget.rideId).listen((rows) async {
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      setState(() => _driver = LatLng((row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble()));
      await _refreshRoutes();
    }, onError: (Object e) {
      if (mounted) setState(() => _message = 'Location update error: ' + e.toString());
    });
  }

  Future<_Route?> _getRoute(LatLng from, LatLng to) async {
    try {
      final coords = from.longitude.toString() + ',' + from.latitude.toString() + ';' +
          to.longitude.toString() + ',' + to.latitude.toString();
      final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/' +
          coords + '?overview=full&geometries=geojson');
      final response = await http.get(uri, headers: {'User-Agent': 'TipCarRideApp/1.0'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;
      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final coordinates = route['geometry']['coordinates'] as List;
      final line = coordinates.map((p) => LatLng((p[1] as num).toDouble(),
          (p[0] as num).toDouble())).toList();
      return _Route(line, (route['distance'] as num).toDouble() / 1000,
          (route['duration'] as num).toDouble() / 60);
    } catch (_) { return null; }
  }

  Future<void> _refreshRoutes({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastRoute != null &&
        now.difference(_lastRoute!) < const Duration(seconds: 30)) return;
    if (_pickup == null || _destination == null) return;
    _lastRoute = now;
    final a = await _getRoute(_driver ?? _pickup!, _pickup!);
    final b = await _getRoute(_pickup!, _destination!);
    if (!mounted) return;
    setState(() {
      if (a != null) { _approach = a.line; _pickupKm = a.km; _pickupMin = a.min; }
      if (b != null) { _trip = b.line; _tripKm = b.km; _tripMin = b.min; }
    });
  }

  Future<void> _startSharing() async {
    setState(() { _busy = true; _message = ''; });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission required.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Turn on GPS.');
      await _send(await Geolocator.getCurrentPosition());
      await _gps?.cancel();
      _gps = Geolocator.getPositionStream(locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high, distanceFilter: 20,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tip Car live ride',
          notificationText: 'Live location is shared with confirmed ride passengers.',
          notificationChannelName: 'Tip Car location sharing',
          enableWakeLock: true, setOngoing: true,
        ),
      )).listen((p) => _send(p).catchError((Object e) {
        if (mounted) setState(() => _message = 'Location upload failed: ' + e.toString());
      }), onError: (Object e) {
        if (mounted) setState(() => _message = 'GPS stopped: ' + e.toString());
      });
      if (mounted) setState(() { _sharing = true; _message = 'Live location is sharing. Android notification remains visible.'; });
    } catch (e) {
      if (mounted) setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _send(Position p) async {
    await db.rpc('update_my_ride_location', params: {
      'p_ride_id': widget.rideId, 'p_latitude': p.latitude, 'p_longitude': p.longitude,
    });
    if (!mounted) return;
    setState(() => _driver = LatLng(p.latitude, p.longitude));
    await _refreshRoutes();
  }

  Future<void> _stop() async {
    await _gps?.cancel(); _gps = null;
    if (mounted) setState(() { _sharing = false; _message = 'Location sharing stopped.'; });
  }

  String _eta(double? value) {
    if (value == null) return 'Calculating…';
    final m = value.round();
    if (m < 1) return 'Under 1 min';
    return m >= 60 ? (m ~/ 60).toString() + ' hr ' + (m % 60).toString() + ' min'
        : m.toString() + ' min';
  }

  @override
  void dispose() { _gps?.cancel(); _updates?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_driver != null) Marker(point: _driver!, width: 50, height: 50,
        child: const Icon(Icons.directions_car_filled, size: 42, color: Color(0xff246bfe))),
      if (_pickup != null) Marker(point: _pickup!, width: 42, height: 42,
        child: const Icon(Icons.location_on, size: 40, color: Colors.green)),
      if (_destination != null) Marker(point: _destination!, width: 42, height: 42,
        child: const Icon(Icons.flag, size: 34, color: Colors.red)),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Live ride tracking')),
      body: Column(children: [
        Expanded(child: FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: _driver ?? _pickup ?? const LatLng(21.6417, 69.6293), initialZoom: 10),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tipcar.app'),
            if (_trip.isNotEmpty) PolylineLayer(polylines: [
              Polyline(points: _trip, strokeWidth: 4, color: Colors.blueGrey)]),
            if (_approach.isNotEmpty) PolylineLayer(polylines: [
              Polyline(points: _approach, strokeWidth: 5, color: const Color(0xff246bfe))]),
            MarkerLayer(markers: markers),
          ],
        )),
        Container(width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_origin + ' → ' + _dest,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _EtaTile(title: widget.isDriver ? 'Time to pickup' : 'Driver arriving in',
                value: _eta(_pickupMin), subtitle: _pickupKm == null ? 'Road distance' : _pickupKm!.toStringAsFixed(1) + ' km')),
              const SizedBox(width: 10),
              Expanded(child: _EtaTile(title: 'Trip duration',
                value: _eta(_tripMin), subtitle: _tripKm == null ? 'Road distance' : _tripKm!.toStringAsFixed(1) + ' km')),
            ]),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_driver == null) const Text('Waiting for driver location…'),
            if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_message, style: const TextStyle(fontSize: 12))),
            if (widget.isDriver) ...[
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: _busy ? null : (_sharing ? _stop : _startSharing),
                icon: Icon(_sharing ? Icons.location_off : Icons.my_location),
                label: Text(_busy ? 'Please wait…' : (_sharing ? 'Stop sharing' : 'Start live sharing'))),
            ],
            const Text('ETA uses road routing, not live traffic. GPS and mobile data must remain on.',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
          ]),
        ),
      ]),
    );
  }
}

class _Route {
  final List<LatLng> line; final double km, min;
  const _Route(this.line, this.km, this.min);
}
class _EtaTile extends StatelessWidget {
  final String title, value, subtitle;
  const _EtaTile({required this.title, required this.value, required this.subtitle});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xfff2f6ff), borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
    ]));
}
