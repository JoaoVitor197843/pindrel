import 'package:flutter/material.dart';

/// Bolinha de status com um anel que pulsa. Com a opção de acessibilidade
/// "reduzir movimento" ligada (ou com [pulsing] falso), fica parada.
///
/// O anel cresce além do [diameter] sem ocupar espaço: quem usa deixa uma folga
/// até o texto ao lado.
class PulsingDot extends StatefulWidget {
  const PulsingDot({
    super.key,
    required this.color,
    required this.diameter,
    this.pulsing = true,
  });

  final Color color;

  /// Diâmetro da bolinha, em geral o de uma letra do texto ao lado.
  final double diameter;

  final bool pulsing;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _reduceMotion = false;

  bool get _animate => widget.pulsing && !_reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.diameter,
        child: CustomPaint(
          painter: _DotPainter(
            animation: _controller,
            color: widget.color,
            animate: _animate,
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.animation,
    required this.color,
    required this.animate,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    if (animate) {
      final t = animation.value;
      canvas.drawCircle(
        center,
        radius * (1 + 0.9 * t),
        Paint()..color = color.withValues(alpha: 0.5 * (1 - t)),
      );
    }
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color || old.animate != animate;
}
