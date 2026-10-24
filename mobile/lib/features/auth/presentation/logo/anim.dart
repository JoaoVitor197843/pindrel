import 'dart:math' as math;
import 'dart:ui' show Canvas, Color;

import 'package:flutter/animation.dart';

/// A transform in the order the prototype's CSS used: `translate(tx,ty) rotate(rot) translateX(lx)
/// scale(sx,sy) skewX(skew)`. Angles in degrees.
class Tf {
  const Tf({
    this.tx = 0,
    this.ty = 0,
    this.rot = 0,
    this.lx = 0,
    this.sx = 1,
    this.sy = 1,
    this.skew = 0,
  });

  final double tx, ty, rot, lx, sx, sy, skew;

  static Tf lerp(Tf a, Tf b, double t) => Tf(
    tx: a.tx + (b.tx - a.tx) * t,
    ty: a.ty + (b.ty - a.ty) * t,
    rot: a.rot + (b.rot - a.rot) * t,
    lx: a.lx + (b.lx - a.lx) * t,
    sx: a.sx + (b.sx - a.sx) * t,
    sy: a.sy + (b.sy - a.sy) * t,
    skew: a.skew + (b.skew - a.skew) * t,
  );

  void apply(Canvas canvas) {
    if (tx != 0 || ty != 0) canvas.translate(tx, ty);
    if (rot != 0) canvas.rotate(rot * math.pi / 180);
    if (lx != 0) canvas.translate(lx, 0);
    if (sx != 1 || sy != 1) canvas.scale(sx, sy);
    if (skew != 0) canvas.skew(math.tan(skew * math.pi / 180), 0);
  }
}

/// One keyframe. A channel left `null` is not animated by it: `tf` (transform), `op` (opacity), `color`
/// (fill / background) and `v` (a free number, used by the progress ring).
class Fr {
  const Fr(
    this.o, {
    this.tf,
    this.op,
    this.color,
    this.v,
    this.ease = Curves.linear,
  });

  /// Offset in 0..1 of the animation.
  final double o;
  final Tf? tf;
  final double? op;
  final Color? color;
  final double? v;

  /// Easing of the segment that starts at this keyframe.
  final Curve ease;
}

/// Shorthand for a keyframe with a transform. `s` sets both scale axes unless `sx`/`sy` are given.
Fr fr(
  double o, {
  double tx = 0,
  double ty = 0,
  double r = 0,
  double lx = 0,
  double s = 1,
  double? sx,
  double? sy,
  double k = 0,
  double? op,
  Color? c,
  double? v,
  Curve e = Curves.linear,
  bool tf = true,
}) => Fr(
  o,
  tf: tf
      ? Tf(tx: tx, ty: ty, rot: r, lx: lx, sx: sx ?? s, sy: sy ?? s, skew: k)
      : null,
  op: op,
  color: c,
  v: v,
  ease: e,
);

/// A keyframe without a transform: opacity and/or color only.
Fr frOp(double o, double op, {Curve e = Curves.linear}) =>
    fr(o, op: op, e: e, tf: false);

enum Fill { none, both, forwards }

/// What an animation says about each channel at one instant.
class Pose {
  Tf? tf;
  double? op;
  Color? color;
  double? v;
}

/// Web Animations semantics, evaluated by time instead of by a clock: `delay`, `iterations`, `alternate`,
/// a timing-function over the whole iteration (`ease`) and one per segment (`Fr.ease`). Times in ms.
class Anim {
  Anim(
    this.frames, {
    required this.dur,
    this.delay = 0,
    this.iters = 1,
    this.alt = false,
    this.ease = Curves.linear,
    this.fill = Fill.none,
    this.created = 0,
  }) : _tf = _indexes(frames, (f) => f.tf != null),
       _op = _indexes(frames, (f) => f.op != null),
       _color = _indexes(frames, (f) => f.color != null),
       _v = _indexes(frames, (f) => f.v != null);

  final List<Fr> frames;
  final double dur, delay;
  final int iters;
  final bool alt;
  final Curve ease;
  final Fill fill;

  /// When it was "created" in the prototype (a timeout): a later animation wins over an earlier one.
  final double created;

  final List<int> _tf, _op, _color, _v;

  double get end => delay + dur * iters;

  static List<int> _indexes(List<Fr> frames, bool Function(Fr) has) => [
    for (var i = 0; i < frames.length; i++)
      if (has(frames[i])) i,
  ];

  /// Null when the animation has no effect at `t`.
  Pose? sample(double t) {
    var local = t - delay;
    if (local < 0) {
      if (fill != Fill.both) return null;
      local = 0;
    }
    final total = dur * iters;
    if (local >= total) {
      if (fill == Fill.none) return null;
      local = total;
    }
    final x = dur <= 0 ? 1.0 : local / dur;
    var it = x.floor();
    var prog = x - it;
    if (x >= iters) {
      it = iters - 1;
      prog = 1;
    }
    if (alt && it.isOdd) prog = 1 - prog;
    final p = ease.transform(prog.clamp(0.0, 1.0));
    final pose = Pose();
    if (_tf.isNotEmpty) {
      pose.tf = _channel<Tf>(_tf, p, (f) => f.tf!, Tf.lerp);
    }
    if (_op.isNotEmpty) {
      pose.op = _channel<double>(_op, p, (f) => f.op!, _lerpD);
    }
    if (_color.isNotEmpty) {
      pose.color = _channel<Color>(
        _color,
        p,
        (f) => f.color!,
        (a, b, t) => Color.lerp(a, b, t)!,
      );
    }
    if (_v.isNotEmpty) {
      pose.v = _channel<double>(_v, p, (f) => f.v!, _lerpD);
    }
    return pose;
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;

  T _channel<T>(
    List<int> idx,
    double p,
    T Function(Fr) get,
    T Function(T, T, double) lerp,
  ) {
    final first = frames[idx.first];
    if (p <= first.o || idx.length == 1) return get(first);
    for (var i = 0; i < idx.length - 1; i++) {
      final a = frames[idx[i]];
      final b = frames[idx[i + 1]];
      if (p <= b.o) {
        final span = b.o - a.o;
        final f = span <= 0 ? 1.0 : (p - a.o) / span;
        return lerp(get(a), get(b), a.ease.transform(f.clamp(0.0, 1.0)));
      }
    }
    return get(frames[idx.last]);
  }
}
