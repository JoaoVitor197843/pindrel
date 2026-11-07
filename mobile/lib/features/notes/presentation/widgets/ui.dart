import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'motion.dart';

/// Radius of every field and card (the web's `rounded-field`).
const fieldRadius = 10.0;

/// The look of a card or panel: a surface with a 1 px border; it takes the stronger border when [hover].
BoxDecoration cardBox({
  bool hover = false,
  Color? color,
  double radius = fieldRadius,
}) => BoxDecoration(
  color: color ?? AppColors.surface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: hover ? AppColors.fieldBorder : AppColors.border),
);

/// Mono, uppercase, wide-tracked label (section headings, counts, badges).
TextStyle monoLabel({
  double size = 11,
  double spacing = 1.9,
  Color color = AppColors.textMuted,
}) => AppText.mono(size, color: color, letterSpacing: spacing);

/// Runs [child] with a stronger border while the pointer is over it (desktop); on touch it never changes.
class HoverBox extends StatefulWidget {
  const HoverBox({super.key, required this.builder});
  final Widget Function(BuildContext context, bool hover) builder;
  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  var _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: widget.builder(context, _hover),
  );
}

/// A 40-high bordered button with an icon (the top bar's menu button, the toolbar buttons).
class OutlineIconButton extends StatelessWidget {
  const OutlineIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: FocusRing(
        child: InkWell(
          borderRadius: BorderRadius.circular(fieldRadius),
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(fieldRadius),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: Icon(icon, size: 20, color: color ?? AppColors.text),
          ),
        ),
      ),
    ),
  );
}

/// The cream call-to-action button (new page, first page...).
class CreamButton extends StatelessWidget {
  const CreamButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 44,
    this.expand = false,
    this.buttonKey,
  });
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final double height;
  final bool expand;
  final Key? buttonKey;
  @override
  Widget build(BuildContext context) => FocusRing(
    child: Material(
      color: AppColors.primaryButton,
      borderRadius: BorderRadius.circular(fieldRadius),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(fieldRadius),
        onTap: onPressed,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.onPrimaryButton),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.onPrimaryButton,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A bordered ghost button with text (Restaurar, Esvaziar lixeira, Trocar capa...).
class OutlineTextButton extends StatelessWidget {
  const OutlineTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 40,
    this.danger = false,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool danger, compact;
  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.offlineText : AppColors.text;
    return FocusRing(
      child: InkWell(
        borderRadius: BorderRadius.circular(fieldRadius),
        onTap: onPressed,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(fieldRadius),
            border: Border.all(
              color: danger
                  ? AppColors.offline.withValues(alpha: 0.5)
                  : AppColors.fieldBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small icon button without a border (pin, trash, close...), 36 px by default.
class GhostIconButton extends StatelessWidget {
  const GhostIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 16,
    this.color = AppColors.textMuted,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size, iconSize;
  final Color color;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: FocusRing(
        child: InkWell(
          borderRadius: BorderRadius.circular(fieldRadius),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      ),
    ),
  );
}

/// A pill with a coloured dot and mono text (a tag).
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.name,
    required this.color,
    this.onRemove,
    this.hash = false,
  });
  final String name;
  final Color color;
  final VoidCallback? onRemove;
  final bool hash;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(10, 4, onRemove == null ? 10 : 6, 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '${hash ? '#' : ''}$name',
          style: AppText.mono(12, color: color, letterSpacing: 0.3),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(99),
            child: Tooltip(
              message: 'Remover tag $name',
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: color),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// The little toast at the bottom of the screen (a short message that fades on its own). Its timer belongs to the
/// widget, so it ends with it if the screen goes away first.
abstract final class Toast {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String message) =>
      showOn(Overlay.maybeOf(context, rootOverlay: true), message);

  /// The same, on an overlay already in hand (a screen that is about to close takes the navigator's).
  static void showOn(OverlayState? overlay, String message) {
    if (overlay == null) return;
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (c) => _ToastView(
        message: message,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (_entry == entry) _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Drops a toast that is still showing.
  static void clear() {
    final e = _entry;
    _entry = null;
    if (e != null && e.mounted) e.remove();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;
  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2400), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Positioned(
    left: 16,
    right: 16,
    bottom: 24 + MediaQuery.viewInsetsOf(c).bottom,
    child: IgnorePointer(
      child: Center(
        child: Entrance(
          kind: EntranceKind.pop,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(fieldRadius),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.message,
                  style: const TextStyle(fontSize: 14, color: AppColors.text),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A dashed rounded border (the empty states and the spoiler); Flutter has none built in.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    this.color = AppColors.border,
    this.radius = fieldRadius,
    this.fill,
  });
  final Widget child;
  final Color color;
  final double radius;
  final Color? fill;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashedPainter(color, radius, fill), child: child);
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.radius, this.fill);
  final Color color;
  final double radius;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    if (fill != null) canvas.drawRRect(rrect, Paint()..color = fill!);
    final path = Path()..addRRect(rrect.deflate(0.5));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + 5).clamp(0, m.length)), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius || old.fill != fill;
}

/// Diagonal stripes (the web's spoiler background: surface and page colours in turn, 135 degrees).
class StripedBox extends StatelessWidget {
  const StripedBox({super.key, required this.child, this.radius = fieldRadius});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: CustomPaint(painter: _StripePainter(), child: child),
  );
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.background);
    final p = Paint()
      ..color = AppColors.surface
      ..strokeWidth = 11.3;
    // lines run from the top-right to the bottom-left; spacing 16 across the diagonal
    for (var x = -size.height; x < size.width + size.height; x += 16 * 1.4142) {
      canvas.drawLine(Offset(x + size.height, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => false;
}

/// Whether the last thing the person did was press a key (so a focus ring is wanted) rather than click or touch: the web's
/// `:focus-visible`. Registered once, on first use.
abstract final class KeyboardMode {
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && !_modifierOnly(e.logicalKey)) active.value = true;
    return false;
  }

  static void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) active.value = false;
  }

  /// Hooks the keyboard and the pointer (again when it is already hooked: a test binding forgets its handlers between
  /// tests, and taking a handler out before putting it in keeps it from being counted twice).
  static void ensure() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    HardwareKeyboard.instance.addHandler(_onKey);
    final router = GestureBinding.instance.pointerRouter;
    try {
      router.removeGlobalRoute(_onPointer);
    } on AssertionError {
      // not hooked yet: a debug build asserts that the route exists, a release build ignores it
    }
    router.addGlobalRoute(_onPointer);
  }

  static final _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  static bool _modifierOnly(LogicalKeyboardKey k) => _modifiers.contains(k);

  /// For tests: forget what happened before.
  static void reset(bool value) => active.value = value;
}

/// The ring around whatever has the keyboard focus (2 px, the accent colour, 2 px off its edge), only after a key press.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.radius = fieldRadius});
  final Widget child;
  final double radius;
  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  var _focused = false;

  @override
  void initState() {
    super.initState();
    KeyboardMode.ensure();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (f) => setState(() => _focused = f),
    child: ValueListenableBuilder<bool>(
      valueListenable: KeyboardMode.active,
      builder: (context, keyboard, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          child!,
          if (_focused && keyboard)
            Positioned(
              left: -4,
              top: -4,
              right: -4,
              bottom: -4,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('focus-ring'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius + 4),
                    border: Border.all(color: AppColors.accentBorder, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: widget.child,
    ),
  );
}

/// An [InkWell] that shows the keyboard focus ring (the web's `:focus-visible`).
class RingInkWell extends StatelessWidget {
  const RingInkWell({
    super.key,
    this.borderRadius,
    this.customBorder,
    this.onTap,
    this.child,
  });
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) => FocusRing(
    radius:
        borderRadius?.topLeft.x ??
        (customBorder is CircleBorder ? 999 : fieldRadius),
    child: InkWell(
      borderRadius: borderRadius,
      customBorder: customBorder,
      onTap: onTap,
      child: child,
    ),
  );
}
