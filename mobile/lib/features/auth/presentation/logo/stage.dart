import 'package:flutter/widgets.dart';

import 'scenes.dart';

/// Width of the stage in the prototype; the scene is built for this box and then shrunk onto the logo.
const logoStageWidth = 388.0;

/// How long (ms) the scene stays up: until its last particle is gone.
double logoStageDuration(LogoScene scene) => scene.runtime;

/// Plays a [LogoScene] right over the logo (no card), one `CustomPaint` for everything (no widget per particle), then calls
/// `onDone`. Its controller is the only thing alive; it is disposed with the widget.
class LogoStage extends StatefulWidget {
  const LogoStage({
    super.key,
    required this.scene,
    required this.onDone,
    required this.center,
    required this.scale,
  });

  final LogoScene scene;

  /// Where the real logo's center is on the screen, and its size over the prototype's 88 px.
  final Offset center;
  final double scale;
  final VoidCallback onDone;

  @override
  State<LogoStage> createState() => _LogoStageState();
}

class _LogoStageState extends State<LogoStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: logoStageDuration(widget.scene).round()),
    )..addStatusListener(_status);
    _controller.forward();
  }

  void _status(AnimationStatus s) {
    if (s == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: LogoStagePainter(
          widget.scene,
          _controller,
          center: widget.center,
          scale: widget.scale,
        ),
      ),
    );
  }
}

/// Draws the scene at `controller.value`: under-actors, the logo replica, then what goes above it. With a
/// `center` the stage is shrunk by `scale` and centered there, so its logo lands on the real one.
class LogoStagePainter extends CustomPainter {
  LogoStagePainter(this.scene, this.controller, {this.center, this.scale = 1})
    : super(repaint: controller);

  final LogoScene scene;
  final Animation<double> controller;
  final Offset? center;
  final double scale;

  /// Time of the scene in ms for an animation value in 0..1.
  double get time => controller.value * logoStageDuration(scene);

  @override
  void paint(Canvas canvas, Size size) => paintAt(canvas, time);

  /// One frame at `t` ms (also what the tests render).
  void paintAt(Canvas canvas, double t) {
    canvas.save();
    final c = center;
    if (c != null) {
      canvas
        ..translate(c.dx, c.dy)
        ..scale(scale)
        ..translate(-scene.stageWidth / 2, -LogoScene.stageHeight / 2);
    }
    for (final a in scene.under) {
      a.paint(canvas, t);
    }
    scene.logo.paint(canvas, t);
    for (final a in scene.over) {
      a.paint(canvas, t);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoStagePainter old) =>
      old.scene != scene || old.center != center || old.scale != scale;
}
