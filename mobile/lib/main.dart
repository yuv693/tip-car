import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';

const tipCarNavy = Color(0xff102a56);
const tipCarOrange = Color(0xfff28c28);
const tipCarGreen = Color(0xff138a50);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const anon = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isNotEmpty && anon.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: anon);
  }
  runApp(const TipCarApp(configured: url != '' && anon != ''));
}

class TipCarApp extends StatelessWidget {
  final bool configured;
  const TipCarApp({super.key, required this.configured});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tip Car',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: tipCarNavy,
            primary: tipCarNavy,
            secondary: tipCarOrange,
            surface: const Color(0xfff7f8fb),
          ),
          scaffoldBackgroundColor: const Color(0xfff7f8fb),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: tipCarNavy,
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xffe8edf4)),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xffffead7),
            labelTextStyle: WidgetStateProperty.resolveWith((states) =>
                TextStyle(
                  color: states.contains(WidgetState.selected)
                      ? tipCarNavy
                      : const Color(0xff68758a),
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                )),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xffdce3ed)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xffdce3ed)),
            ),
          ),
        ),
        home: HomeScreen(configured: configured),
      );
}
