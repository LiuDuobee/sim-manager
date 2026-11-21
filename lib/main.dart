import 'package:flutter/material.dart';

import 'features/hud/hud_theme.dart';
import 'pages/home_page.dart';

export 'models/sim_card.dart';

void main() => runApp(const SimVaultApp());

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
          fontFamilyFallback: const [
            'Microsoft YaHei',
            'PingFang SC',
            'Noto Sans CJK SC',
            'Noto Sans SC',
          ],
        ),
        home: home ?? const HomePage(),
      );
}
