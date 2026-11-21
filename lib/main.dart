import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/hud/hud_theme.dart';
import 'features/settings/theme_mode.dart';
import 'pages/home_page.dart';
import 'services/update/update_services.dart';

export 'models/sim_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind transparent status/navigation bars; pages pad themselves
  // with SafeArea / viewPadding.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final themeMode = ThemeModeController();
  await themeMode.load();
  runApp(SimVaultApp(
      themeMode: themeMode,
      updates: kIsWeb ? null : UpdateServices.platform()));
}

class SimVaultApp extends StatefulWidget {
  const SimVaultApp({super.key, this.home, this.themeMode, this.updates});

  final Widget? home;

  /// Loaded before runApp in production; tests let the app load it.
  final ThemeModeController? themeMode;

  /// Update check on launch; null (tests) skips it.
  final UpdateServices? updates;

  @override
  State<SimVaultApp> createState() => _SimVaultAppState();
}

class _SimVaultAppState extends State<SimVaultApp> {
  late final ThemeModeController _themeMode =
      widget.themeMode ?? (ThemeModeController()..load());

  @override
  void dispose() {
    if (widget.themeMode == null) _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThemeModeScope(
        controller: _themeMode,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: _themeMode,
          builder: (context, mode, _) => MaterialApp(
            title: 'SIMVault v3.3 · World Card Atlas',
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: buildHudTheme(HudPalette.light),
            darkTheme: buildHudTheme(HudPalette.dark),
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
                value: hudSystemUi(Theme.of(context).brightness),
                child: child!),
            home: widget.home ?? HomePage(updates: widget.updates),
          ),
        ),
      );
}
