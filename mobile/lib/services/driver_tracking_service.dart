import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the driver's foreground location service alive when ride screens are
/// pushed/popped. The Android foreground-service notification remains visible
/// while the driver is online.
class TipCarDriverTrackingService {
  TipCarDriverTrackingService._();

  static final SupabaseClient _db = Supabase.instance.client;
  static StreamSubscription<Position>? _gps;
  static Timer? _heartbeat;
  static String? _driverId;
  static void Function(Position)? _onPosition;
  static void Function(Object)? _onError;
  static Future<void>? _starting;

  static Future<void> start(
    String driverId, {
    void Function(Position)? onPosition,
    void Function(Object)? onError,
  }) async {
    _onPosition = onPosition;
    _onError = onError;
    if (_driverId == driverId && _gps != null) return;
    final pendingStart = _starting;
    if (pendingStart != null) {
      await pendingStart;
      if (_driverId == driverId && _gps != null) return;
    }
    final operation = _startInternal(driverId);
    _starting = operation;
    try {
      await operation;
    } finally {
      if (identical(_starting, operation)) _starting = null;
    }
  }

  static Future<void> _startInternal(String driverId) async {
    await _gps?.cancel();
    _heartbeat?.cancel();
    _driverId = driverId;

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on GPS to share your live location.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Allow location permission in Android settings.');
    }

    _gps = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
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
      ),
    ).listen(
      (position) {
        _publishPosition(driverId, position);
        _onPosition?.call(position);
      },
      onError: (Object error) {
        _onError?.call(error);
      },
    );

    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_driverId != driverId) return;
      try {
        await _db.from('driver_presence').update({
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('driver_id', driverId);
      } catch (error) {
        _onError?.call(error);
      }
    });
  }

  static Future<void> _publishPosition(
    String driverId,
    Position position,
  ) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    try {
      await _db.from('driver_presence').update({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'online': true,
        'updated_at': timestamp,
      }).eq('driver_id', driverId);

      final active = await _db.from('ride_requests')
          .select('id')
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'arrived', 'in_progress'])
          .limit(1)
          .maybeSingle();
      if (active != null) {
        await _db.from('ride_request_locations').upsert({
          'request_id': active['id'],
          'driver_id': driverId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'updated_at': timestamp,
        }, onConflict: 'request_id');
      }
    } catch (error) {
      _onError?.call(error);
    }
  }

  /// Stop only when the driver explicitly switches offline.
  static Future<void> stop(String driverId) async {
    if (_driverId != driverId) return;
    await _gps?.cancel();
    _gps = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _driverId = null;
    _onPosition = null;
    _onError = null;
  }

  /// A screen can detach its UI callback without stopping background tracking.
  static void detach(String? driverId) {
    if (driverId == null || _driverId != driverId) return;
    _onPosition = null;
    _onError = null;
  }
}
