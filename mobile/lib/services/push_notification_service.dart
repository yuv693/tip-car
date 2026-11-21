import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Firebase native options are loaded from google-services.json on Android.\nclass TipCarPushService {
 static bool ready=false;
 static Future<void> initialize() async {try{if(Firebase.apps.isEmpty)await Firebase.initializeApp();final m=FirebaseMessaging.instance;await m.requestPermission(alert:true,badge:true,sound:true);final t=await m.getToken();if(t!=null)await _save(t);m.onTokenRefresh.listen(_save);ready=true;}catch(_){ready=false;}}
 static Future<void> _save(String token)async{final c=Supabase.instance.client;final u=c.auth.currentUser;if(u==null)return;await c.from('driver_push_tokens').upsert({'user_id':u.id,'token':token,'platform':'android','updated_at':DateTime.now().toUtc().toIso8601String()},onConflict:'user_id,token');}
}
