import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// FCM may start a background isolate when a notification arrives while the
// app is backgrounded. Android displays notification-payload messages itself;
// this handler initializes Firebase for background processing.
@pragma('vm:entry-point')
Future<void> tipCarFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

class TipCarPushService {
  static bool ready = false;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized && ready) return;
    try {
      FirebaseMessaging.onBackgroundMessage(
        tipCarFirebaseMessagingBackgroundHandler,
      );
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) await _save(token);
      messaging.onTokenRefresh.listen((newToken) async {
        try {
          await _save(newToken);
        } catch (_) {
          // A later token refresh or app launch can retry registration.
        }
      });
      _initialized = true;
      ready = true;
    } catch (_) {
      // Realtime ride inbox remains available if Firebase is not configured.
      ready = false;
    }
  }

  static Future<void> _save(String token) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    await client.from('driver_push_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,token');
  }
}
