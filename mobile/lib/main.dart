import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const anon = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isNotEmpty && anon.isNotEmpty) {
    await Supabase.initialize(url: url, anonKey: anon);
  }
  runApp(const TipCarApp(configured: url != '' && anon != ''));
}

class TipCarApp extends StatelessWidget {
  final bool configured;
  const TipCarApp({super.key, required this.configured});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tip Car & Bus',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff075de8)), useMaterial3: true),
    home: HomeScreen(configured: configured),
  );
}
