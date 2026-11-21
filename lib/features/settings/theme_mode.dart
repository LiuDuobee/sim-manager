import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../hud/hud_theme.dart';

/// Light / dark / follow-system choice, persisted in SharedPreferences.
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController([super.value = ThemeMode.system]);

  static const prefsKey = 'simvault.themeMode';

  static ThemeMode parse(String? name) => ThemeMode.values
      .firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = parse(prefs.getString(prefsKey));
  }

  Future<void> select(ThemeMode mode) async {
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode.name);
  }
}

class ThemeModeScope extends InheritedNotifier<ThemeModeController> {
  const ThemeModeScope(
      {super.key,
      required ThemeModeController controller,
      required super.child})
      : super(notifier: controller);

  static ThemeModeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeModeScope>()!.notifier!;
}

const themeModeOptions = [
  (ThemeMode.light, Icons.light_mode_outlined, '浅色'),
  (ThemeMode.dark, Icons.dark_mode_outlined, '深色'),
  (ThemeMode.system, Icons.brightness_auto_outlined, '跟随系统'),
];

/// Three-way segmented glass switch: 浅色 / 深色 / 跟随系统.
class ThemeModeSwitch extends StatelessWidget {
  const ThemeModeSwitch({super.key, this.showLabels = false});

  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final controller = ThemeModeScope.of(context);
    final h = context.hud;
    return Container(
      key: const Key('theme-switch'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: h.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: h.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (mode, icon, label) in themeModeOptions)
          Tooltip(
            message: label,
            child: InkWell(
              key: Key('theme-${mode.name}'),
              borderRadius: BorderRadius.circular(11),
              onTap: () => controller.select(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: BoxConstraints(
                    minWidth: showLabels ? 96 : Hud.minTap,
                    minHeight: showLabels ? Hud.minTap : 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: controller.value == mode
                      ? h.sky.withValues(alpha: h.isDark ? .2 : .14)
                      : null,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: controller.value == mode
                          ? h.sky.withValues(alpha: .45)
                          : Colors.transparent),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 18,
                          color: controller.value == mode ? h.sky : h.muted),
                      if (showLabels) ...[
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    controller.value == mode ? h.sky : h.fg)),
                      ],
                    ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Phone: a bottom sheet holding the same switch with labels.
Future<void> showThemeModeSheet(BuildContext context) => showGlassBottomSheet(
      context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            HudLabel('主题 · Appearance', color: sheetContext.hud.muted),
            const SizedBox(height: 12),
            const ThemeModeSwitch(showLabels: true),
          ]),
        ),
      ),
    );
