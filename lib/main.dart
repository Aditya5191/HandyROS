import 'package:flutter/material.dart';
import 'screens/app_shell.dart';
import 'app/theme.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(HandyROSApp(settings: settings));
}

class HandyROSApp extends StatelessWidget {
  final AppSettings settings;

  const HandyROSApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "HandyROS",
          theme: HandyTheme.lightTheme,
          darkTheme: HandyTheme.darkTheme,
          themeMode: settings.themeMode,
          builder: (context, child) {
            // AppBrightness.current is read directly (not via
            // Theme.of(context)) by CustomPainters — every canvas
            // viewer — which have no BuildContext to look Theme up
            // with, only a Canvas. Kept in sync here, once per build,
            // resolving ThemeMode.system against the platform's actual
            // current brightness.
            AppBrightness.current = switch (settings.themeMode) {
              ThemeMode.light => Brightness.light,
              ThemeMode.dark => Brightness.dark,
              ThemeMode.system => MediaQuery.platformBrightnessOf(context),
            };
            return child!;
          },
          home: AppShell(settings: settings),
        );
      },
    );
  }
}
