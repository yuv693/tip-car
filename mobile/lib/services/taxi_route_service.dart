import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
class RouteQuote {
 final List<LatLng> points; final double distanceKm,durationMinutes,estimatedFare; final LatLng destination;
 const RouteQuote({required this.points,required this.distanceKm,required this.durationMinutes,required this.estimatedFare,required this.destination});
}
class TaxiRouteService {
 static Future<RouteQuote> estimate({required double pickupLat,required double pickupLon,required String destination,required String vehicleType}) async {
  final g=await http.get(Uri.https('nominatim.openstreetmap.org','/search',{'q':destination,'format':'jsonv2','limit':'1','countrycodes':'in'}),headers:{'User-Agent':'TipCar/1.0 route'});
  if(g.statusCode!=200) throw Exception('Destination search unavailable.');
  final places=jsonDecode(g.body) as List; if(places.isEmpty) throw Exception('Destination not found. Add city/area.');
  final lat=double.parse(places.first['lat'].toString()), lon=double.parse(places.first['lon'].toString());
  final r=await http.get(Uri.https('router.project-osrm.org','/route/v1/driving/$pickupLon,$pickupLat;$lon,$lat',{'overview':'full','geometries':'polyline','steps':'false'}));
  if(r.statusCode!=200) throw Exception('Road route service unavailable.');
  final body=jsonDecode(r.body) as Map<String,dynamic>; if(body['code']!='Ok'||(body['routes'] as List).isEmpty) throw Exception('No road route found.');
  final route=(body['routes'] as List).first as Map<String,dynamic>;
  final km=(route['distance'] as num).toDouble()/1000, mins=(route['duration'] as num).toDouble()/60;
  final fare=vehicleType=='bike'?25+km*8+mins*1.2:45+km*14+mins*1.8;
  return RouteQuote(points:_decode(route['geometry'].toString()),distanceKm:km,durationMinutes:mins,estimatedFare:fare,destination:LatLng(lat,lon));
 }
 static List<LatLng> _decode(String s){final out=<LatLng>[];var i=0,lat=0,lon=0;while(i<s.length){var sh=0,v=0,b=0;do{b=s.codeUnitAt(i++)-63;v|=(b&31)<<sh;sh+=5;}while(b>=32);lat+=(v&1)!=0?~(v>>1):(v>>1);sh=0;v=0;do{b=s.codeUnitAt(i++)-63;v|=(b&31)<<sh;sh+=5;}while(b>=32);lon+=(v&1)!=0?~(v>>1):(v>>1);out.add(LatLng(lat/1e5,lon/1e5));}return out;}
}
