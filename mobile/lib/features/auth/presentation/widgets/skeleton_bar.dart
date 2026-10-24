import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Barra fantasma de carregamento: a cor da borda, com a opacidade indo e
/// voltando (1,5 s, como o esqueleto da web). Com "reduzir movimento" fica
/// parada.
class SkeletonBar extends StatefulWidget {
  const SkeletonBar({super.key, required this.height, this.width});

  final double height;

  /// Sem largura, ocupa a que houver.
  final double? width;

  @override
  State<SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      // 1.0 -> 0.45 e de volta
      opacity: Tween<double>(begin: 1, end: 0.45).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
