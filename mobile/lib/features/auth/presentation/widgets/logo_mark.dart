import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../logo/scenes.dart';
import '../logo/season.dart';
import '../logo/stage.dart';
import '../logo/trigger.dart';

/// The brand's "P". Five quick taps play the scene of the day on a stage over the app (nothing leaves the
/// device); with "reduce motion" on it only blinks. It never navigates or calls the server.
class LogoMark extends StatefulWidget {
  const LogoMark({super.key, this.theme, this.now, this.region});

  /// Forces a theme (tests); otherwise `LOGO_THEME` or the device's local date decide.
  final LogoTheme? theme;

  /// ISO country code whose own dates apply (see `regionalRules`); none by default.
  final String? region;

  /// "Today" for the date rule (tests).
  final DateTime? now;

  @override
  State<LogoMark> createState() => _LogoMarkState();
}

class _LogoMarkState extends State<LogoMark> with WidgetsBindingObserver {
  final _trigger = TapTrigger();
  OverlayEntry? _entry;
  Timer? _pressTimer;
  Timer? _blinkTimer;
  bool _pressed = false;
  bool _dim = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pressTimer?.cancel();
    _blinkTimer?.cancel();
    _stop(rebuild: false);
    _trigger.release();
    super.dispose();
  }

  // an app sent to the background does not keep a scene running
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _stop();
    _trigger.release();
  }

  void _stop({bool rebuild = true}) {
    final entry = _entry;
    _entry = null;
    if (rebuild && _playing && mounted) setState(() => _playing = false);
    if (entry == null) return;
    entry.remove();
    entry.dispose();
  }

  void _onTap() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    switch (_trigger.tap()) {
      case TapResult.ignored:
        return;
      case TapResult.press:
        if (reduce) return;
        setState(() => _pressed = true);
        _pressTimer?.cancel();
        _pressTimer = Timer(const Duration(milliseconds: 70), () {
          if (mounted) setState(() => _pressed = false);
        });
      case TapResult.fire:
        reduce ? _blink() : _play();
    }
  }

  void _blink() {
    setState(() => _dim = true);
    _trigger.hold(const Duration(milliseconds: 420));
    _blinkTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _dim = false);
    });
  }

  void _play() {
    final theme =
        widget.theme ??
        currentLogoTheme(widget.now ?? DateTime.now(), region: widget.region);
    final box = context.findRenderObject()! as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final scene = LogoScene(theme, stageWidth: logoStageWidth);
    _trigger.hold(
      Duration(milliseconds: logoStageDuration(scene).round() + 50),
    );
    // the replica drawn by the scene takes the real logo's place until it ends
    setState(() => _playing = true);
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: LogoStage(
          scene: scene,
          onDone: _stop,
          center: center,
          scale: box.size.width / 88,
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Logo do Plany',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: AnimatedScale(
          scale: _pressed ? .92 : 1,
          duration: const Duration(milliseconds: 70),
          child: AnimatedOpacity(
            opacity: _playing ? 0 : (_dim ? .5 : 1),
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('P', style: AppText.serif(20)),
            ),
          ),
        ),
      ),
    );
  }
}
