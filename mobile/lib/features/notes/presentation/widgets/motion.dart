import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The web's entrances (rise, fade, slide, pop, icon-pop), with the same durations. Everything is driven by one
/// controller and a curve, never by timers, so a screen that closes in the middle of one leaves nothing behind. When
/// the system asks for reduced motion the child simply shows up.
enum EntranceKind { rise, fade, slideFromLeft, slideFromRight, pop, icon }

const _durations = {
  EntranceKind.rise: Duration(milliseconds: 300),
  EntranceKind.fade: Duration(milliseconds: 450),
  EntranceKind.slideFromLeft: Duration(milliseconds: 240),
  EntranceKind.slideFromRight: Duration(milliseconds: 240),
  EntranceKind.pop: Duration(milliseconds: 160),
  EntranceKind.icon: Duration(milliseconds: 380),
};

class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.kind = EntranceKind.rise, this.delay = Duration.zero, this.enabled = true});
  final Widget child;
  final EntranceKind kind;

  /// Waited before the entrance starts (a list staggers its rows).
  final Duration delay;

  /// False draws the child at once (a row drawn again after scrolling back to it does not replay its entrance).
  final bool enabled;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _durations[widget.kind]! + widget.delay);
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _durations[widget.kind]!.inMilliseconds + widget.delay.inMilliseconds;
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(widget.delay.inMilliseconds / total, 1, curve: widget.kind == EntranceKind.icon ? Curves.linear : Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final t = curve.value;
        switch (widget.kind) {
          case EntranceKind.rise:
            return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child));
          case EntranceKind.fade:
            return Opacity(opacity: t, child: child);
          case EntranceKind.slideFromLeft:
            return Opacity(opacity: t, child: Transform.translate(offset: Offset(-14 * (1 - t), 0), child: child));
          case EntranceKind.slideFromRight:
            return Opacity(opacity: t, child: Transform.translate(offset: Offset(14 * (1 - t), 0), child: child));
          case EntranceKind.pop:
            return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, -4 * (1 - t)), child: Transform.scale(scale: 0.97 + 0.03 * t, child: child)));
          case EntranceKind.icon:
            // 0% scale .6 rotate -8deg -> 60% scale 1.12 rotate 3deg -> 100% 1
            final up = Curves.easeOut.transform((t / 0.6).clamp(0, 1));
            final down = Curves.easeOut.transform(((t - 0.6) / 0.4).clamp(0, 1));
            final scale = t < 0.6 ? 0.6 + (1.12 - 0.6) * up : 1.12 + (1 - 1.12) * down;
            final turn = (t < 0.6 ? -8 + (3 + 8) * up : 3 * (1 - down)) * math.pi / 180;
            return Opacity(opacity: (t / 0.6).clamp(0, 1), child: Transform.rotate(angle: turn, child: Transform.scale(scale: scale, child: child)));
        }
      },
    );
  }
}
