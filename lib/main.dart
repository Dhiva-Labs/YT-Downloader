import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'splash_page.dart';

final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
SharedPreferences? _prefs;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _prefs = await SharedPreferences.getInstance();
  final saved = _prefs?.getString('themeMode');
  themeMode.value = ThemeMode.values.firstWhere(
    (m) => m.name == saved,
    orElse: () => ThemeMode.system,
  );
  runApp(const YtDownloaderApp());
}

void cycleThemeMode() {
  const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  final next = order[(order.indexOf(themeMode.value) + 1) % order.length];
  themeMode.value = next;
  _prefs?.setString('themeMode', next.name);
}

class YtDownloaderApp extends StatelessWidget {
  const YtDownloaderApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE53935),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: scheme.surfaceContainerLow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'YT-Downloader by DhivaLabs',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: const SplashPage(),
      ),
    );
  }
}
