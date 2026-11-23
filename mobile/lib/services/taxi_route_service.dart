import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteQuote {
  final List<LatLng> points;
  final double distanceKm, durationMinutes, estimatedFare;
  final LatLng destination;
  const RouteQuote({required this.points, required this.distanceKm, required this.durationMinutes, required this.estimatedFare, required this.destination});
}

/// Free-to-start OpenStreetMap community services; no paid API key required.
class TaxiRouteService {
  static final http.Client _client = http.Client();
  static final Map<String, LatLng> _geocodeCache = {};
  static final Map<String, RouteQuote> _routeCache = {};
  static DateTime? _lastGeocodeRequest;
  static Future<void> _geocodeQueue = Future<void>.value();

  static Future<void> _waitForGeocodeSlot() async {
    final previous = _geocodeQueue;
    final completer = Completer<void>();
    _geocodeQueue = completer.future;
    await previous;
    try {
      final last = _lastGeocodeRequest;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        const gap = Duration(milliseconds: 1100);
        if (elapsed < gap) await Future<void>.delayed(gap - elapsed);
      }
      _lastGeocodeRequest = DateTime.now();
    } finally {
      completer.complete();
    }
  }

  static Future<LatLng> _findDestination(String destination) async {
    final key = destination.trim().toLowerCase();
    final cached = _geocodeCache[key];
    if (cached != null) return cached;
    await _waitForGeocodeSlot();
    final response = await _client.get(
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': destination.trim(), 'format': 'jsonv2', 'limit': '1', 'countrycodes': 'in',
      }),
      headers: {'User-Agent': 'TipCar/1.0 (https://github.com/yuv693/tip-car)', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) throw Exception('Address search is busy. Please wait and try again.');
    if (response.statusCode != 200) throw Exception('Destination search unavailable.');
    final places = jsonDecode(response.body) as List;
    if (places.isEmpty) throw Exception('Destination not found. Add city/area, e.g. Rajkot, Gujarat.');
    final point = LatLng(double.parse(places.first['lat'].toString()), double.parse(places.first['lon'].toString()));
    _geocodeCache[key] = point;
    return point;
  }

  static Future<RouteQuote> estimate({required double pickupLat, required double pickupLon, required String destination, required String vehicleType}) async {
    final destinationPoint = await _findDestination(destination);
    final cacheKey = [pickupLat.toStringAsFixed(4), pickupLon.toStringAsFixed(4), destinationPoint.latitude.toStringAsFixed(5), destinationPoint.longitude.toStringAsFixed(5), vehicleType].join(':');
    final cached = _routeCache[cacheKey];
    if (cached != null) return cached;
    final path = '/route/v1/driving/' + pickupLon.toString() + ',' + pickupLat.toString() + ';' + destinationPoint.longitude.toString() + ',' + destinationPoint.latitude.toString();
    final response = await _client.get(
      Uri.https('router.project-osrm.org', path, {'overview': 'full', 'geometries': 'polyline', 'steps': 'false'}),
      headers: {'User-Agent': 'TipCar/1.0 (https://github.com/yuv693/tip-car)'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode == 429) throw Exception('Route service is busy. Please try again shortly.');
    if (response.statusCode != 200) throw Exception('Road route service unavailable.');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != 'Ok' || (body['routes'] as List).isEmpty) throw Exception('No road route found for this destination.');
    final route = (body['routes'] as List).first as Map<String, dynamic>;
    final km = (route['distance'] as num).toDouble() / 1000;
    final mins = (route['duration'] as num).toDouble() / 60;
    final fare = vehicleType == 'bike' ? 25 + km * 8 + mins * 1.2 : 45 + km * 14 + mins * 1.8;
    final quote = RouteQuote(points: _decode(route['geometry'].toString()), distanceKm: km, durationMinutes: mins, estimatedFare: fare, destination: destinationPoint);
    _routeCache[cacheKey] = quote;
    return quote;
  }

  static List<LatLng> _decode(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lon = 0;
    while (index < encoded.length) {
      var shift = 0, result = 0, byte = 0;
      do { byte = encoded.codeUnitAt(index++) - 63; result |= (byte & 31) << shift; shift += 5; } while (byte >= 32);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do { byte = encoded.codeUnitAt(index++) - 63; result |= (byte & 31) << shift; shift += 5; } while (byte >= 32);
      lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lon / 1e5));
    }
    return points;
  }
}