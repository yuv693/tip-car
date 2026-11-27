import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/taxi_route_service.dart';
import '../services/push_notification_service.dart';
import 'alternative_ride_screen.dart';

class InstantTaxiScreen extends StatefulWidget {
  final bool configured;
  final String? initialDestination;
  final String? initialVehicleType;
  const InstantTaxiScreen({
    super.key,
    required this.configured,
    this.initialDestination,
    this.initialVehicleType,
  });

  @override
  State<InstantTaxiScreen> createState() => _InstantTaxiScreenState();
}

class _InstantTaxiScreenState extends State<InstantTaxiScreen> {
  final _pickup = TextEditingController(text: 'My current location');
  final _destination = TextEditingController();
  final _vehicleName = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final _mapController = MapController();

  SupabaseClient get db => Supabase.instance.client;
  String? get userId => db.auth.currentUser?.id;

  String _role = 'passenger';
  String _vehicleType = 'bike';
  String _message = '';
  bool _online = false;
  bool _sharing = false;
  bool _busy = false;
  Map<String, dynamic>? _myRequest;
  Map<String, dynamic>? _activeRequest;
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _offers = [];
  StreamSubscription<List<Map<String, dynamic>>>? _offersStream;
  String? _offersRequestId;
  LatLng? _myPosition;
  LatLng? _driverPosition;
  LatLng? _destinationPosition;
  List<LatLng> _routePoints = [];
  double? _routeDistanceKm;
  double? _routeDurationMinutes;
  double? _estimatedFare;
  double? _driverPickupDistanceKm;
  double? _driverPickupEtaMinutes;
  DateTime? _lastEtaCalculation;
  bool _etaLoading = false;
  DateTime? _lastInboxRefresh;
  StreamSubscription<Position>? _gps;
  Timer? _heartbeat;
  StreamSubscription<List<Map<String, dynamic>>>? _requestStream;
  StreamSubscription<List<Map<String, dynamic>>>? _locationStream;
  String? _locationRequestId;

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination?.trim().isNotEmpty == true) {
      _destination.text = widget.initialDestination!.trim();
    }
    if (widget.initialVehicleType == 'bike' || widget.initialVehicleType == 'car') {
      _vehicleType = widget.initialVehicleType!;
    }
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!widget.configured || userId == null) return;
    try {
      final row = await db.from('profiles').select('role')
          .eq('id', userId!).single();
      if (!mounted) return;
      setState(() => _role = row['role']?.toString() ?? 'passenger');
      if (_role == 'driver') {
        await TipCarPushService.initialize();
        await _loadPresence();
        _watchDriverRequests();
      } else {
        _watchPassengerRequests();
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Profile load failed: $e');
    }
  }

  Future<void> _loadPresence() async {
    try {
      final row = await db.from('driver_presence').select()
          .eq('driver_id', userId!).maybeSingle();
      if (row == null || !mounted) return;
      setState(() {
        _vehicleType = row['vehicle_type']?.toString() ?? 'bike';
        _vehicleName.text = row['vehicle_name']?.toString() ?? '';
        _vehicleNumber.text = row['vehicle_number']?.toString() ?? '';
        final fresh = DateTime.tryParse(row['updated_at']?.toString() ?? '');
        _online = row['online'] == true &&
            fresh != null &&
            DateTime.now().toUtc().difference(fresh.toUtc()) <
                const Duration(seconds: 90);
      });
      if (_online) {
        await _startGps();
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not load driver availability: $e');
    }
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on GPS to continue.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Allow Tip Car location permission in Android settings.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _requestTaxi() async {
    if (userId == null) return;
    if (_destination.text.trim().isEmpty) {
      setState(() => _message = 'Enter your destination first.');
      return;
    }
    setState(() { _busy = true; _message = ''; });
    try {
      final p = await _currentPosition();
      final quote = await TaxiRouteService.estimate(
        pickupLat: p.latitude, pickupLon: p.longitude,
        destination: _destination.text.trim(), vehicleType: _vehicleType,
      );
      final row = await db.from('ride_requests').insert({
        'passenger_id': userId,
        'vehicle_type': _vehicleType,
        'pickup_label': _pickup.text.trim().isEmpty ? 'Current location' : _pickup.text.trim(),
        'destination_label': _destination.text.trim(),
        'pickup_latitude': p.latitude,
        'pickup_longitude': p.longitude,
        'destination_latitude': quote.destination.latitude,
        'destination_longitude': quote.destination.longitude,
        'route_distance_km': quote.distanceKm,
        'route_duration_minutes': quote.durationMinutes,
        'estimated_fare': quote.estimatedFare,
      }).select().single();
      if (!mounted) return;
      setState(() {
        _myPosition = LatLng(p.latitude, p.longitude);
        _destinationPosition = quote.destination;
        _routePoints = quote.points;
        _routeDistanceKm = quote.distanceKm;
        _routeDurationMinutes = quote.durationMinutes;
        _estimatedFare = quote.estimatedFare;
        _myRequest = Map<String, dynamic>.from(row);
        _message = 'Route calculated. Ride request sent to nearby drivers.';
      });
      _watchRequestLocation(row['id'].toString());
      try {
        await db.functions.invoke('notify-nearby-drivers', body: {'request_id': row['id']});
      } catch (_) {
        if (mounted) setState(() => _message = 'Ride request sent. Push notification setup is still pending.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not request a ride: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watchPassengerRequests() {
    _requestStream?.cancel();
    _requestStream = db.from('ride_requests').stream(primaryKey: ['id'])
        .eq('passenger_id', userId!).listen((rows) {
      if (!mounted) return;
      rows.sort((a, b) => (b['created_at'] ?? '').toString()
          .compareTo((a['created_at'] ?? '').toString()));
      final active = rows.where((r) => !['completed','cancelled','expired']
          .contains(r['status'])).toList();
      setState(() => _myRequest = active.isEmpty ? null : active.first);
      final id = _myRequest?['id']?.toString();
      if (id != null) {
        _watchRequestLocation(id);
        _watchRideOffers(id);
      } else {
        _offersStream?.cancel();
        _offersRequestId = null;
        if (mounted) setState(() => _offers = []);
      }
    }, onError: (Object e) {
      if (mounted) setState(() => _message = 'Ride updates unavailable: $e');
    });
  }

  void _watchRideOffers(String requestId) {
    if (_offersRequestId == requestId && _offersStream != null) return;
    _offersStream?.cancel();
    _offersRequestId = requestId;
    _offersStream = db.from('ride_request_offers').stream(primaryKey: ['id'])
        .eq('request_id', requestId).listen((rows) {
      if (!mounted) return;
      final offers = rows.map((r) => Map<String, dynamic>.from(r)).toList()
        ..sort((a, b) => ((a['fare'] as num?)?.toDouble() ?? double.infinity)
            .compareTo((b['fare'] as num?)?.toDouble() ?? double.infinity));
      setState(() => _offers = offers);
    }, onError: (Object e) {
      if (mounted) setState(() => _message = 'Driver offers unavailable: $e');
    });
  }

  Future<void> _chooseOffer(Map<String, dynamic> offer) async {
    if (_myRequest == null || _busy) return;
    setState(() { _busy = true; _message = ''; });
    try {
      await db.rpc('select_ride_request_offer', params: {'p_offer_id': offer['id']});
      if (!mounted) return;
      setState(() => _message = 'Driver selected! Fare ₹${(offer['fare'] as num).toStringAsFixed(0)} confirmed.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not select this offer: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendFareOffer(Map<String, dynamic> request) async {
    final controller = TextEditingController(
      text: ((request['estimated_fare'] as num?)?.toDouble() ?? 100).toStringAsFixed(0),
    );
    final fare = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send your ride fare'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Your total fare'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final value = double.tryParse(controller.text.trim());
            if (value != null && value > 0) Navigator.pop(dialogContext, value);
          }, child: const Text('Send offer')),
        ],
      ),
    );
    controller.dispose();
    if (fare == null) return;
    setState(() { _busy = true; _message = ''; });
    try {
      await db.from('ride_request_offers').upsert({
        'request_id': request['id'],
        'driver_id': userId,
        'fare': fare,
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'request_id,driver_id');
      if (mounted) setState(() => _message = 'Fare offer ₹${fare.toStringAsFixed(0)} sent. Passenger can compare offers.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not send fare offer: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watchRequestLocation(String requestId) {
    if (_locationStream != null && _locationRequestId == requestId) return;
    _locationStream?.cancel();
    _locationRequestId = requestId;
    _locationStream = db.from('ride_request_locations')
        .stream(primaryKey: ['request_id'])
        .eq('request_id', requestId).listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final row = rows.first;
      final point = LatLng(
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
      );
      setState(() => _driverPosition = point);
      _refreshDriverPickupEta(point);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(point, 15);
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _message = 'Live driver location unavailable: $e');
    });
  }

  Future<void> _refreshDriverPickupEta(LatLng driverPoint) async {
    final request = _myRequest;
    if (request == null ||
        !['accepted', 'arrived'].contains(request['status']?.toString())) {
      return;
    }
    final lat = request['pickup_latitude'];
    final lon = request['pickup_longitude'];
    if (lat is! num || lon is! num) return;
    final now = DateTime.now();
    if (_lastEtaCalculation != null &&
        now.difference(_lastEtaCalculation!) < const Duration(seconds: 30)) {
      return;
    }
    _lastEtaCalculation = now;
    if (mounted) setState(() => _etaLoading = true);
    try {
      final leg = await TaxiRouteService.estimateLeg(
        from: driverPoint,
        to: LatLng(lat.toDouble(), lon.toDouble()),
      );
      if (!mounted) return;
      setState(() {
        _driverPickupDistanceKm = leg.distanceKm;
        _driverPickupEtaMinutes = leg.durationMinutes;
      });
    } catch (_) {
      // Keep the last successful ETA visible if the public routing service is busy.
    } finally {
      if (mounted) setState(() => _etaLoading = false);
    }
  }

  bool _isRequestForThisDriver(Map<String, dynamic> request) {
    if (request['vehicle_type']?.toString() != _vehicleType) return false;
    final pickupLat = request['pickup_latitude'];
    final pickupLon = request['pickup_longitude'];
    final driverPosition = _myPosition;
    if (pickupLat is! num || pickupLon is! num || driverPosition == null) {
      return false;
    }
    final pickup = LatLng(pickupLat.toDouble(), pickupLon.toDouble());
    final distanceKm = const Distance().as(
      LengthUnit.Kilometer, driverPosition, pickup,
    );
    return distanceKm <= 8;
  }

  Future<void> _refreshDriverRequests({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastInboxRefresh != null &&
        now.difference(_lastInboxRefresh!) < const Duration(seconds: 15)) {
      return;
    }
    _lastInboxRefresh = now;
    try {
      final rows = await db.from('ride_requests').select()
          .eq('status', 'searching').order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _incoming = List<Map<String, dynamic>>.from(rows)
          .where((r) => r['driver_id'] == null && _isRequestForThisDriver(r))
          .toList());
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not refresh nearby requests: $e');
    }
  }

  void _watchDriverRequests() {
    _requestStream?.cancel();
    _requestStream = db.from('ride_requests').stream(primaryKey: ['id'])
        .order('created_at', ascending: false).listen((rows) {
      if (!mounted) return;
      final visible = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      setState(() {
        _incoming = visible.where((r) => r['status'] == 'searching' &&
            r['driver_id'] == null && _isRequestForThisDriver(r)).toList();
        final active = visible.where((r) => r['driver_id'] == userId &&
            ['accepted','arrived','in_progress'].contains(r['status'])).toList();
        _activeRequest = active.isEmpty ? null : active.first;
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _message = 'Incoming ride updates unavailable: $e');
    });
  }

  Future<void> _setOnline(bool value) async {
    if (value) {
      if (_vehicleName.text.trim().isEmpty ||
          _vehicleNumber.text.trim().isEmpty) {
        setState(() => _message = 'Enter vehicle name and registration number first.');
        return;
      }
      setState(() { _busy = true; _message = ''; });
      try {
        final p = await _currentPosition();
        await db.from('driver_presence').upsert({
          'driver_id': userId,
          'vehicle_type': _vehicleType,
          'vehicle_name': _vehicleName.text.trim(),
          'vehicle_number': _vehicleNumber.text.trim().toUpperCase(),
          'online': true,
          'latitude': p.latitude,
          'longitude': p.longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'driver_id');
        if (!mounted) return;
        setState(() { _online = true; _myPosition = LatLng(p.latitude, p.longitude); });
        await _startGps();
        if (mounted) setState(() => _message = 'You are online. Nearby matching $_vehicleType requests will appear here.');
      } catch (e) {
        if (mounted) setState(() => _message = 'Could not go online: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      try {
        if (_activeRequest != null) {
          setState(() => _message = 'Complete or cancel your active ride before going offline.');
          return;
        }
        await _gps?.cancel();
        _gps = null;
        _heartbeat?.cancel();
        _heartbeat = null;
        await db.from('driver_presence').update({
          'online': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('driver_id', userId!);
        if (mounted) setState(() { _online = false; _sharing = false; _message = 'You are offline.'; });
      } catch (e) {
        if (mounted) setState(() => _message = 'Could not go offline: $e');
      }
    }
  }

  Future<void> _startGps() async {
    await _gps?.cancel();
    _gps = Geolocator.getPositionStream(locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Tip Car driver online',
        notificationText: 'Tip Car is sharing your location while you are online.',
        notificationChannelName: 'Tip Car driver availability',
        enableWakeLock: true,
        setOngoing: true,
      ),
    )).listen((p) {
      _updateDriverPosition(p).catchError((Object e) {
        if (mounted) setState(() => _message = 'GPS update failed: $e');
      });
    }, onError: (Object e) {
      if (mounted) {
        setState(() { _sharing = false; _message = 'GPS stopped: $e'; });
      }
    });
    if (mounted) setState(() => _sharing = true);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_online || !_sharing || userId == null) return;
      try {
        await db.from('driver_presence').update({
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('driver_id', userId!);
      } catch (e) {
        if (mounted) setState(() => _message = 'Driver availability heartbeat failed: $e');
      }
    });
  }

  Future<void> _updateDriverPosition(Position p) async {
    final point = LatLng(p.latitude, p.longitude);
    await db.from('driver_presence').update({
      'latitude': p.latitude,
      'longitude': p.longitude,
      'online': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('driver_id', userId!);
    final active = _activeRequest;
    if (active != null) {
      await db.from('ride_request_locations').upsert({
        'request_id': active['id'],
        'driver_id': userId,
        'latitude': p.latitude,
        'longitude': p.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'request_id');
    }
    if (!mounted) return;
    setState(() => _myPosition = point);
    if (_incoming.isEmpty) await _refreshDriverRequests();
  }

  Future<void> _advanceRide() async {
    final active = _activeRequest;
    if (active == null) return;
    final current = active['status']?.toString();
    final next = current == 'accepted' ? 'arrived'
        : current == 'arrived' ? 'in_progress'
        : current == 'in_progress' ? 'completed' : null;
    if (next == null) return;
    try {
      final result = await db.from('ride_requests').update({
        'status': next,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', active['id']).eq('driver_id', userId!)
          .select().maybeSingle();
      if (!mounted) return;
      setState(() => _message = result == null
          ? 'Ride status could not be updated.'
          : 'Ride status: $next');
      if (next == 'completed') {
        await db.from('ride_request_locations')
            .delete().eq('request_id', active['id']);
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Ride update failed: $e');
    }
  }

  Future<void> _cancelAssignedRide() async {
    final active = _activeRequest;
    if (active == null) return;
    final status = active['status']?.toString();
    if (status != 'accepted' && status != 'arrived') {
      setState(() => _message = 'A ride already in progress cannot be cancelled here. Contact the passenger and support.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this accepted ride?'),
        content: const Text('The passenger will see that the driver cancelled. No ride commission is charged for a cancelled ride.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep ride')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel ride')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await db.from('ride_requests').update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', active['id']).eq('driver_id', userId!);
      if (mounted) setState(() => _message = 'Ride cancelled. You can now go offline or receive another request.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not cancel assigned ride: $e');
    }
  }

  Future<void> _cancelRequest() async {
    final request = _myRequest;
    if (request == null) return;
    try {
      await db.from('ride_requests').update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request['id']).eq('passenger_id', userId!);
      if (mounted) setState(() => _message = 'Ride request cancelled.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not cancel request: $e');
    }
  }

  @override
  void dispose() {
    _gps?.cancel();
    _heartbeat?.cancel();
    _requestStream?.cancel();
    _locationStream?.cancel();
    _offersStream?.cancel();
    _pickup.dispose();
    _destination.dispose();
    _vehicleName.dispose();
    _vehicleNumber.dispose();
    super.dispose();
  }

  Widget _statusCard(Map<String, dynamic> request) {
    final status = request['status']?.toString() ?? 'searching';
    final label = switch (status) {
      'searching' => 'Finding a nearby driver…',
      'accepted' => 'Driver accepted your ride',
      'arrived' => 'Driver has arrived at pickup',
      'in_progress' => 'Your ride is in progress',
      'completed' => 'Ride completed',
      'cancelled' => 'Ride cancelled',
      _ => status,
    };
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text('${request['pickup_label']} → ${request['destination_label']}'),
        Text(request['vehicle_type'] == 'bike' ? '🏍️ Bike Taxi' : '🚗 Car Taxi'),
        if (request['route_distance_km'] != null) Text('Route: ${request['route_distance_km']} km · ETA ${request['route_duration_minutes']} min'),
        if (request['estimated_fare'] != null) Text('Estimated fare: ₹${request['estimated_fare']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (status == 'searching' || status == 'accepted')
          TextButton.icon(onPressed: _cancelRequest,
            icon: const Icon(Icons.close), label: const Text('Cancel request')),
        if (_driverPosition != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xffeaf2ff),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.near_me_rounded, color: Color(0xff174d91), size: 26),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Driver live location', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text(_driverPickupDistanceKm == null
                    ? 'Updating road distance to pickup…'
                    : '${_driverPickupDistanceKm!.toStringAsFixed(1)} km from pickup'),
                  Text(_driverPickupEtaMinutes == null
                    ? 'Calculating arrival time…'
                    : 'Estimated arrival: ${_driverPickupEtaMinutes!.ceil()} min (road estimate)',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff174d91))),
                  if (_etaLoading) const Text('Refreshing road-route ETA…',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              )),
            ]),
          ),
        ],
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.configured) {
      return const Scaffold(body: Center(child: Text('Tip Car setup is incomplete.')));
    }
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Please sign in to use Instant Taxi.')));
    }
    final isDriver = _role == 'driver';
    final pickup = _myRequest == null ? _myPosition : LatLng(
      (_myRequest!['pickup_latitude'] as num).toDouble(),
      (_myRequest!['pickup_longitude'] as num).toDouble(),
    );
    final center = _driverPosition ?? _myPosition ?? pickup ??
        const LatLng(21.6417, 69.6293);
    return Scaffold(
      appBar: AppBar(title: Text(isDriver ? 'Driver · Instant Taxi' : 'Instant Bike / Car Taxi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isDriver) ...[
            const Text('Book a nearby ride', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bike', label: Text('Bike'), icon: Icon(Icons.two_wheeler)),
                ButtonSegment(value: 'car', label: Text('Car'), icon: Icon(Icons.directions_car)),
              ],
              selected: {_vehicleType},
              onSelectionChanged: _myRequest == null
                  ? (v) => setState(() => _vehicleType = v.first)
                  : null,
            ),
            const SizedBox(height: 10),
            TextField(controller: _pickup, decoration: const InputDecoration(
              labelText: 'Pickup', prefixIcon: Icon(Icons.my_location))),
            TextField(controller: _destination, decoration: const InputDecoration(
              labelText: 'Destination', prefixIcon: Icon(Icons.flag_outlined))),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _myRequest != null ? null : _requestTaxi,
              icon: _busy ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.local_taxi),
              label: Text(_busy ? 'Calculating route & requesting…' : 'Calculate route & find driver'),
            ),
            if (_routeDistanceKm != null) Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Route: ${_routeDistanceKm!.toStringAsFixed(1)} km · ETA ${_routeDurationMinutes!.toStringAsFixed(0)} min'),
                Text('Estimated fare: ₹${_estimatedFare!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Text('Indicative estimate only; final fare rules are not yet locked.', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ]),
            )),
            if (_myRequest != null) _statusCard(_myRequest!),
            if (_myRequest != null && _myRequest!['status'] == 'searching') ...[
              const SizedBox(height: 8),
              const Text('Driver fare offers · cheapest first', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (_offers.isEmpty) const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Waiting for nearby drivers to send their fares…'),
              ),
              ..._offers.where((o) => o['status'] == 'pending').map((offer) {
                final amount = (offer['fare'] as num?)?.toDouble() ?? 0;
                final isCheapest = _offers.where((o) => o['status'] == 'pending')
                    .every((o) => ((o['fare'] as num?)?.toDouble() ?? double.infinity) >= amount);
                return Card(
                  child: ListTile(
                    leading: Icon(isCheapest ? Icons.price_check : Icons.local_taxi,
                      color: isCheapest ? Colors.green : null, size: 30),
                    title: Text('₹${amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    subtitle: Text(isCheapest ? 'Lowest fare offer' : 'Driver fare offer'),
                    trailing: FilledButton(
                      onPressed: _busy ? null : () => _chooseOffer(offer),
                      child: const Text('Choose'),
                    ),
                  ),
                );
              }),
            ],
            if (_myRequest != null && _myRequest!['status'] == 'searching')
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AlternativeRideScreen(
                    pickup: _pickup.text.trim(),
                    destination: _destination.text.trim().isNotEmpty
                        ? _destination.text.trim()
                        : (_myRequest!['destination_label'] ?? '').toString(),
                    instantRequestId: _myRequest!['id']?.toString(),
                  ),
                )),
                icon: const Icon(Icons.alt_route),
                label: const Text('Find an alternative scheduled ride'),
              ),
            if (_myRequest != null && (_driverPosition != null || _routePoints.isNotEmpty))
              SizedBox(height: 280, child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: center, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.tipcar.app',
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        '© OpenStreetMap contributors',
                        onTap: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                  if (_routePoints.length > 1) PolylineLayer(polylines: [
                    Polyline(points: _routePoints, strokeWidth: 4, color: Colors.blue),
                  ]),
                  MarkerLayer(markers: [
                    if (pickup != null) Marker(point: pickup, width: 42, height: 42,
                      child: const Icon(Icons.location_on, color: Colors.green, size: 38)),
                    if (_destinationPosition != null) Marker(point: _destinationPosition!, width: 42, height: 42,
                      child: const Icon(Icons.flag, color: Colors.red, size: 34)),
                    if (_driverPosition != null) Marker(point: _driverPosition!, width: 42, height: 42,
                      child: Icon(_myRequest?['vehicle_type'] == 'bike' ? Icons.two_wheeler : Icons.directions_car, color: Colors.blue, size: 38)),
                  ]),
                ],
              )),
          ] else ...[
            const Text('Go online to receive nearby requests',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xffeef5ff),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.public, color: Color(0xff174a7e)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gujarat driver network: register once. When you go online, Tip Car automatically updates your live location. Only nearby passengers see your availability; no monthly manual update is needed.',
                        style: TextStyle(fontSize: 13, color: Color(0xff17324d)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bike', label: Text('Bike'), icon: Icon(Icons.two_wheeler)),
                ButtonSegment(value: 'car', label: Text('Car'), icon: Icon(Icons.directions_car)),
              ],
              selected: {_vehicleType},
              onSelectionChanged: _online || _activeRequest != null
                  ? null : (v) => setState(() => _vehicleType = v.first),
            ),
            TextField(controller: _vehicleName,
              decoration: const InputDecoration(labelText: 'Vehicle name / model')),
            TextField(controller: _vehicleNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Vehicle registration number')),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_online ? 'You are online' : 'You are offline'),
              subtitle: Text(_sharing ? 'GPS is sharing your live location; matching requests are enabled.' : 'Only matching Bike or Car requests within 8 km are shown.'),
              value: _online,
              onChanged: _busy ? null : _setOnline,
            ),
            if (_activeRequest != null) ...[
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Current ride', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  Text('${_activeRequest!['pickup_label']} → ${_activeRequest!['destination_label']}'),
                  Text('Status: ${_activeRequest!['status']}'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _advanceRide, child: Text(
                    _activeRequest!['status'] == 'accepted' ? 'I have arrived'
                    : _activeRequest!['status'] == 'arrived' ? 'Start ride'
                    : 'Complete ride')),
                  if (_activeRequest!['status'] == 'accepted' || _activeRequest!['status'] == 'arrived')
                    TextButton.icon(
                      onPressed: _busy ? null : _cancelAssignedRide,
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: const Text('Cancel accepted ride', style: TextStyle(color: Colors.red)),
                    ),
                ],
              ))),
            ],
            const SizedBox(height: 12),
            const Text('Nearby ride requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            if (!_online) const Text('Go online to see requests.'),
            if (_online && _incoming.isEmpty) const Text('Waiting for nearby passengers…'),
            ..._incoming.map((r) {
              final fare = (r['estimated_fare'] as num?)?.toDouble();
              final routeKm = (r['route_distance_km'] as num?)?.toDouble();
              final eta = (r['route_duration_minutes'] as num?)?.toDouble();
              final pickupLat = (r['pickup_latitude'] as num?)?.toDouble();
              final pickupLon = (r['pickup_longitude'] as num?)?.toDouble();
              final pickupDistance = _myPosition != null &&
                      pickupLat != null && pickupLon != null
                  ? const Distance().as(
                      LengthUnit.Kilometer,
                      _myPosition!,
                      LatLng(pickupLat, pickupLon),
                    )
                  : null;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          r['vehicle_type'] == 'bike'
                              ? Icons.two_wheeler : Icons.directions_car,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          r['vehicle_type'] == 'bike' ? 'Bike ride request' : 'Car ride request',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )),
                        if (fare != null) Text(
                          '₹${fare.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                      ]),
                      const Divider(),
                      const Text('PICKUP', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: Colors.blueGrey,
                      )),
                      Text((r['pickup_label'] ?? 'Customer location').toString()),
                      if (pickupDistance != null) Text(
                        'Your distance to pickup: ${pickupDistance.toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 8),
                      const Text('DESTINATION', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: Colors.blueGrey,
                      )),
                      Text((r['destination_label'] ?? 'Not provided').toString()),
                      if (routeKm != null || eta != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${routeKm == null ? '' : 'Trip: ${routeKm.toStringAsFixed(1)} km'}'
                            '${routeKm != null && eta != null ? ' · ' : ''}'
                            '${eta == null ? '' : 'ETA: ${eta.toStringAsFixed(0)} min'}',
                            style: const TextStyle(color: Colors.blueGrey),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _sendFareOffer(r),
                          icon: const Icon(Icons.currency_rupee),
                          label: const Text('Send your fare offer'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (_message.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(_message, style: const TextStyle(color: Colors.blue))),
          const SizedBox(height: 12),
          const Text('GPS and mobile data must remain on. Live driver tracking starts after a driver accepts.',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
        ],
      ),
    );
  }
}
