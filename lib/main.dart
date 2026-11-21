import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/hud/hud_theme.dart';
import 'pages/home_page.dart';

export 'models/sim_card.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind transparent status/navigation bars; pages pad themselves
  // with SafeArea / viewPadding.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const SimVaultApp());
}

const simVaultSystemUi = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

class SimVaultApp extends StatelessWidget {
  const SimVaultApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SIMVault v3.2 · World Card Atlas',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: Hud.bg,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Hud.sky,
              brightness: Brightness.dark,
              surface: Hud.panel),
          appBarTheme: const AppBarTheme(
            systemOverlayStyle: simVaultSystemUi,
            backgroundColor: Hud.bg,
            surfaceTintColor: Colors.transparent,
          ),
          fontFamilyFallback: const [
            'Microsoft YaHei',
            'PingFang SC',
            'Noto Sans CJK SC',
            'Noto Sans SC',
          ],
        ),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: simVaultSystemUi, child: child!),
        home: home ?? const HomePage(),
      );
}
