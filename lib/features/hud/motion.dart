import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Motion design tokens shared by the whole app.
///
/// Durations follow one ladder (micro-interactions 150–200 ms, transitions
/// 300–500 ms); anything a finger can touch moves on a spring so it can be
/// interrupted and keeps its velocity. Everything collapses to instant when
/// the platform asks for reduced motion.
abstract final class Motion {
  static const micro = Duration(milliseconds: 160);
  static const short = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 320);
  static const long = Duration(milliseconds: 480);

  /// Delay before detail content fades / rises in after its container.
  static const detailDelay = Duration(milliseconds: 90);
  static const pressScale = .97;

  /// Card flip, card stack pull-out: slightly under-damped, settles < 650 ms.
  static const flipSpring =
      SpringDescription(mass: 1, stiffness: 120, damping: 17);

  /// Dock indicator, stamp: snappier.
  static const snapSpring =
      SpringDescription(mass: 1, stiffness: 380, damping: 26);

  /// Globe fling deceleration (FrictionSimulation drag coefficient).
  static const globeFriction = .06;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// A [Curve] that follows a spring from 0 to 1, normalised to the animation
/// length and snapped to exactly 1 at the end — for duration-based APIs that
/// should still land like a spring.
class SpringCurve extends Curve {
  const SpringCurve([this.spring = Motion.snapSpring, this.seconds = .65]);

  final SpringDescription spring;
  final double seconds;

  @override
  double transformInternal(double t) =>
      t >= 1 ? 1 : SpringSimulation(spring, 0, 1, 0).x(t * seconds);
}

/// Haptic feedback ladder. Devices without a vibrator ignore these; every
/// call site also shows a visual equivalent (press scale, stamp, shake).
abstract final class Haptics {
  static void tick() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
  static void error() => HapticFeedback.heavyImpact();
}

/// Scales its child to [Motion.pressScale] while pressed and ticks on tap.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final scaled = AnimatedScale(
      scale: _down ? Motion.pressScale : 1,
      duration: Motion.of(context, Motion.micro),
      curve: Curves.easeOut,
      child: widget.child,
    );
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: widget.onTap == null
          ? scaled
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tick();
                widget.onTap!();
              },
              child: scaled),
    );
  }
}

/// Shakes its child horizontally when [trigger] changes (error feedback).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.medium);

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !Motion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final dx = 10 * (1 - t) * _wave(t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: widget.child,
      );

  static double _wave(double t) {
    const cycles = 3;
    final x = (t * cycles * 2) % 2;
    return x < 1
        ? (x < .5 ? x * 2 : 2 - x * 2)
        : -(x < 1.5 ? (x - 1) * 2 : 2 - (x - 1) * 2);
  }
}
