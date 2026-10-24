import 'dart:ui' hide TextStyle;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import 'anim.dart';

final Paint _paint = Paint();

/// Something an [Actor] draws, in its own coordinates.
abstract class Drawable {
  /// `tint` replaces the fill; `v` is the free number of the running animation (see [PathShape.dashed]).
  void draw(Canvas canvas, double t, double alpha, {Color? tint, double? v});
}

class PathShape implements Drawable {
  PathShape(
    this.path, {
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.opacity = 1,
    this.dashed = false,
  });

  final Path path;
  final Color? fill, stroke;
  final double strokeWidth, opacity;
  final StrokeCap cap;
  final StrokeJoin join;

  /// A stroke drawn only up to length `v` (the prototype's `stroke-dasharray` + `stroke-dashoffset`).
  final bool dashed;

  @override
  void draw(Canvas canvas, double t, double alpha, {Color? tint, double? v}) {
    final a = alpha * opacity;
    if (a <= 0) return;
    final f = tint ?? fill;
    if (f != null) {
      _paint
        ..style = PaintingStyle.fill
        ..color = f.withValues(alpha: f.a * a);
      canvas.drawPath(path, _paint);
    }
    final s = stroke;
    if (s != null) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = cap
        ..strokeJoin = join
        ..color = s.withValues(alpha: s.a * a);
      var p = path;
      if (dashed) {
        final shown = v ?? 0;
        if (shown <= 0) return;
        p = Path();
        var left = shown;
        for (final m in path.computeMetrics()) {
          p.addPath(m.extractPath(0, left.clamp(0, m.length)), Offset.zero);
          left -= m.length;
          if (left <= 0) break;
        }
      }
      canvas.drawPath(p, _paint);
    }
  }
}

/// A line of text with its top-left corner at `at`. Laid out once, again only when the tint changes.
class TextShape implements Drawable {
  TextShape(this.text, this.style, {this.at = Offset.zero, this.opacity = 1}) {
    _layout(style.color!);
  }

  final String text;
  final TextStyle style;
  final Offset at;
  final double opacity;
  late TextPainter _tp;
  late Color _laidOutWith;

  double get width => _tp.width;
  double get height => _tp.height;

  void _layout(Color color) {
    _laidOutWith = color;
    _tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void draw(Canvas canvas, double t, double alpha, {Color? tint, double? v}) {
    final a = alpha * opacity;
    if (a <= 0) return;
    final c = tint ?? style.color!;
    if (c != _laidOutWith) _layout(c);
    if (a < 1) {
      canvas.saveLayer(
        Rect.fromLTWH(at.dx, at.dy, _tp.width, _tp.height).inflate(2),
        Paint()..color = Color.fromRGBO(0, 0, 0, a),
      );
      _tp.paint(canvas, at);
      canvas.restore();
    } else {
      _tp.paint(canvas, at);
    }
  }
}

/// A node of the scene: a box placed at (`x`,`y`) in its parent, with its own animations.
///
/// Drawing order: background, then `items` (shapes and child actors) in order. The animation transform
/// pivots on `origin` (default: the center of the box). `scale` maps the content (an SVG's viewBox units)
/// to the box and `shift` moves it (the viewBox's origin).
class Actor implements Drawable {
  Actor({
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    Offset? origin,
    List<Drawable>? items,
    this.bg,
    this.radius = 0,
    this.clip = false,
    this.scale = 1,
    this.shift = Offset.zero,
    this.opacity = 1,
  }) : origin = origin ?? Offset(w / 2, h / 2),
       items = items ?? [];

  double x, y;
  final double w, h;
  final Offset origin;
  final List<Drawable> items;

  /// Background of the box (rounded by `radius`); the color channel of an animation drives it.
  Color? bg;
  final double radius;
  final bool clip;
  final double scale;
  final Offset shift;

  /// Opacity when no animation says otherwise (the prototype's elements start at 0).
  final double opacity;
  final List<Anim> anims = [];

  /// When the last animation ends (0 without animations).
  double get end => anims.fold(0.0, (m, a) => a.end > m ? a.end : m);

  Pose _pose(double t) {
    final out = Pose();
    for (final a in anims) {
      final s = a.sample(t);
      if (s == null) continue;
      out.tf = s.tf ?? out.tf;
      out.op = s.op ?? out.op;
      out.color = s.color ?? out.color;
      out.v = s.v ?? out.v;
    }
    return out;
  }

  /// Keeps `anims` in the order the prototype created them (a later one wins over an earlier one).
  void sortAnims() {
    final order = {for (var i = 0; i < anims.length; i++) anims[i]: i};
    anims.sort((a, b) {
      final c = a.created.compareTo(b.created);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
  }

  /// Draws the actor as it is at `t` ms.
  void paint(Canvas canvas, double t, [double alpha = 1]) =>
      draw(canvas, t, alpha);

  @override
  void draw(Canvas canvas, double t, double alpha, {Color? tint, double? v}) {
    final p = anims.isEmpty ? null : _pose(t);
    final a = alpha * (p?.op ?? opacity);
    if (a <= 0) return;
    canvas.save();
    canvas.translate(x + origin.dx, y + origin.dy);
    p?.tf?.apply(canvas);
    canvas.translate(-origin.dx, -origin.dy);
    final box = Rect.fromLTWH(0, 0, w, h);
    if (clip) {
      canvas.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
    }
    final color = p?.color;
    final back = color != null && bg != null ? color : bg;
    if (back != null) {
      _paint
        ..style = PaintingStyle.fill
        ..color = back.withValues(alpha: back.a * a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(radius)),
        _paint,
      );
    }
    if (scale != 1) canvas.scale(scale);
    if (shift != Offset.zero) canvas.translate(shift.dx, shift.dy);
    final tint = bg == null ? color : null;
    for (final item in items) {
      item.draw(canvas, t, a, tint: tint, v: p?.v);
    }
    canvas.restore();
  }
}
