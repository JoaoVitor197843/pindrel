import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Ghost loading bar: the border color, with the opacity going back
/// and forth (1.5 s, like the web skeleton). With "reduce motion" it stands
/// still.
class SkeletonBar extends StatefulWidget {
  const SkeletonBar({super.key, required this.height, this.width});

  final double height;

  /// Without a width, it takes whatever there is.
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
      // 1.0 -> 0.45 and back
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
