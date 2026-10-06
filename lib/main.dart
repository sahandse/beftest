
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

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B5FEF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بفرست',
      locale: const Locale('fa'),
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(settings: settings),
      ),
    );
  }
}
