import 'package:flutter/material.dart';

import 'core/app_settings.dart';
import 'features/home/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(BefrestApp(settings: settings));
}

class BefrestApp extends StatelessWidget {
  final AppSettings settings;

  const BefrestApp({
    super.key,
    required this.settings,
  });

  ThemeData _theme(Brightness brightness) {
    const seed = Color(0xFF5B5FEF);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F7FB)
          : const Color(0xFF0F1014),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بفرست',
      locale: const Locale('fa'),
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(settings: settings),
      ),
    );
  }
}
