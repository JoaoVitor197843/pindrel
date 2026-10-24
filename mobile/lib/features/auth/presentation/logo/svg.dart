import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'actor.dart';

/// A tiny reader of the SVG subset the logo art uses (`svg g path rect ellipse circle`, absolute and
/// relative `MLHVCQZ`, `rotate/translate/scale`), so the art stays the SVG strings of the prototype.
/// Elements with an `id` or `class` become their own [Actor], so a scene can animate them.
class Svg {
  Svg(this.root, this.ids, this.classes);

  final Actor root;
  final Map<String, Actor> ids;
  final Map<String, List<Actor>> classes;

  Actor operator [](String id) => ids[id]!;
}

/// `#rgb`, `#rrggbb`, `rgba(r,g,b,a)` or `currentColor`; null for `none`.
Color? parseColor(String value, [Color current = const Color(0xFFFFFFFF)]) {
  final v = value.trim();
  if (v == 'none') return null;
  if (v == 'currentColor') return current;
  if (v.startsWith('#')) {
    var h = v.substring(1);
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    return Color(0xFF000000 | int.parse(h, radix: 16));
  }
  final m = RegExp(r'rgba?\(([^)]*)\)').firstMatch(v);
  if (m != null) {
    final p = m
        .group(1)!
        .split(',')
        .map((e) => double.parse(e.trim()))
        .toList();
    return Color.fromRGBO(
      p[0].round(),
      p[1].round(),
      p[2].round(),
      p.length > 3 ? p[3] : 1,
    );
  }
  throw FormatException('unsupported color', value);
}

/// Shorthand for the scenes: `col('#f2c94c')`.
Color col(String hex) => parseColor(hex)!;

class _Node {
  _Node(this.tag, this.attrs);
  final String tag;
  final Map<String, String> attrs;
  final List<_Node> children = [];
}

final _tagRe = RegExp(r'<(/?)([a-zA-Z]+)((?:\s+[a-zA-Z-]+="[^"]*")*)\s*(/?)>');
final _attrRe = RegExp(r'([a-zA-Z-]+)="([^"]*)"');

_Node _parse(String markup) {
  final root = _Node('#root', {});
  final stack = [root];
  for (final m in _tagRe.allMatches(markup)) {
    if (m.group(1) == '/') {
      stack.removeLast();
      continue;
    }
    final attrs = {
      for (final a in _attrRe.allMatches(m.group(3)!)) a.group(1)!: a.group(2)!,
    };
    final node = _Node(m.group(2)!, attrs);
    stack.last.children.add(node);
    if (m.group(4) != '/') stack.add(node);
  }
  return root.children.single;
}

/// 2D affine matrix `[a b c d e f]`.
typedef _Aff = List<double>;
const _Aff _identity = [1, 0, 0, 1, 0, 0];

_Aff _mul(_Aff m, _Aff n) => [
  m[0] * n[0] + m[2] * n[1],
  m[1] * n[0] + m[3] * n[1],
  m[0] * n[2] + m[2] * n[3],
  m[1] * n[2] + m[3] * n[3],
  m[0] * n[4] + m[2] * n[5] + m[4],
  m[1] * n[4] + m[3] * n[5] + m[5],
];

final _numRe = RegExp(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

List<double> _nums(String s) =>
    _numRe.allMatches(s).map((m) => double.parse(m.group(0)!)).toList();

_Aff _transform(String? attr) {
  var m = _identity;
  if (attr == null) return m;
  for (final t in RegExp(r'(\w+)\(([^)]*)\)').allMatches(attr)) {
    final a = _nums(t.group(2)!);
    switch (t.group(1)) {
      case 'translate':
        m = _mul(m, [1, 0, 0, 1, a[0], a.length > 1 ? a[1] : 0]);
      case 'scale':
        m = _mul(m, [a[0], 0, 0, a.length > 1 ? a[1] : a[0], 0, 0]);
      case 'rotate':
        final r = a[0] * math.pi / 180;
        final c = math.cos(r);
        final s = math.sin(r);
        final cx = a.length > 2 ? a[1] : 0.0;
        final cy = a.length > 2 ? a[2] : 0.0;
        m = _mul(m, [1, 0, 0, 1, cx, cy]);
        m = _mul(m, [c, s, -s, c, 0, 0]);
        m = _mul(m, [1, 0, 0, 1, -cx, -cy]);
      default:
        throw FormatException('unsupported transform', t.group(0));
    }
  }
  return m;
}

Path _applyAff(Path p, _Aff m) {
  if (identical(m, _identity)) return p;
  final f = Float64List(16)
    ..[0] = m[0]
    ..[1] = m[1]
    ..[4] = m[2]
    ..[5] = m[3]
    ..[10] = 1
    ..[12] = m[4]
    ..[13] = m[5]
    ..[15] = 1;
  return p.transform(f);
}

/// Path data (`d`) to a [Path].
Path parsePathData(String d) {
  final path = Path();
  final tokens = RegExp(
    r'([A-Za-z])|(-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)',
  ).allMatches(d).toList();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  double next() => double.parse(tokens[i++].group(2)!);
  while (i < tokens.length) {
    if (tokens[i].group(1) != null) cmd = tokens[i++].group(1)!;
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0;
    final oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = next() + ox;
        y = next() + oy;
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = next() + ox;
        y = next() + oy;
        path.lineTo(x, y);
      case 'H':
        x = next() + ox;
        path.lineTo(x, y);
      case 'V':
        y = next() + oy;
        path.lineTo(x, y);
      case 'C':
        final x1 = next() + ox, y1 = next() + oy;
        final x2 = next() + ox, y2 = next() + oy;
        x = next() + ox;
        y = next() + oy;
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Q':
        final x1 = next() + ox, y1 = next() + oy;
        x = next() + ox;
        y = next() + oy;
        path.quadraticBezierTo(x1, y1, x, y);
      case 'Z':
        path.close();
        x = sx;
        y = sy;
      default:
        throw FormatException('unsupported path command', cmd);
    }
  }
  return path;
}

const _inherited = [
  'fill',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
];

class _Ctx {
  _Ctx(this.current, this.origins);
  final Color current;
  final Map<String, Offset> origins;
  final ids = <String, Actor>{};
  final classes = <String, List<Actor>>{};
}

/// Reads `markup` (one `<svg>`) into an [Actor] of `width` x `height` px (default: the viewBox size).
/// `origins` sets the pivot of an `id` (default: the center of its shapes, like CSS `fill-box`).
Svg parseSvg(
  String markup, {
  double? width,
  double? height,
  Color currentColor = const Color(0xFFFFFFFF),
  Map<String, Offset> origins = const {},
}) {
  final svg = _parse(markup);
  final vb = _nums(svg.attrs['viewBox']!);
  final w = width ?? vb[2];
  final h = height ?? vb[3];
  final ctx = _Ctx(currentColor, origins);
  final root = Actor(
    w: w,
    h: h,
    scale: math.min(w / vb[2], h / vb[3]),
    shift: Offset(-vb[0], -vb[1]),
  );
  _children(svg, _identity, _style(svg, const {}), root.items, ctx);
  return Svg(root, ctx.ids, ctx.classes);
}

Map<String, String> _style(_Node n, Map<String, String> parent) => {
  ...parent,
  for (final k in _inherited)
    if (n.attrs.containsKey(k)) k: n.attrs[k]!,
};

void _children(
  _Node n,
  _Aff tf,
  Map<String, String> style,
  List<Drawable> out,
  _Ctx ctx,
) {
  for (final c in n.children) {
    final t = _mul(tf, _transform(c.attrs['transform']));
    final s = _style(c, style);
    final id = c.attrs['id'];
    final cls = c.attrs['class'];
    final named = id != null || cls != null;
    final target = named ? <Drawable>[] : out;
    if (c.tag == 'g') {
      _children(c, t, s, target, ctx);
    } else {
      target.add(_shape(c, t, s, ctx));
    }
    if (named) {
      final b = _bounds(target);
      final actor = Actor(
        origin: ctx.origins[id] ?? (b?.center ?? Offset.zero),
        items: target,
      );
      if (id != null) ctx.ids[id] = actor;
      if (cls != null) (ctx.classes[cls] ??= []).add(actor);
      out.add(actor);
    }
  }
}

Rect? _bounds(List<Drawable> items) {
  Rect? r;
  for (final i in items) {
    final b = i is PathShape
        ? i.path.getBounds()
        : i is Actor
        ? _bounds(i.items)
        : null;
    if (b != null) r = r == null ? b : r.expandToInclude(b);
  }
  return r;
}

PathShape _shape(_Node n, _Aff tf, Map<String, String> s, _Ctx ctx) {
  final a = n.attrs;
  double num(String k, [double dflt = 0]) =>
      a.containsKey(k) ? double.parse(a[k]!) : dflt;
  final dashed = a.containsKey('stroke-dasharray');
  Path path;
  switch (n.tag) {
    case 'path':
      path = parsePathData(a['d']!);
    case 'rect':
      final x = num('x'), y = num('y'), w = num('width'), h = num('height');
      final rx = num('rx');
      if (dashed) {
        // starts at the top edge going clockwise, like SVG, so the "progress" grows the same way
        path = Path()
          ..moveTo(x + rx, y)
          ..lineTo(x + w - rx, y)
          ..arcToPoint(Offset(x + w, y + rx), radius: Radius.circular(rx))
          ..lineTo(x + w, y + h - rx)
          ..arcToPoint(Offset(x + w - rx, y + h), radius: Radius.circular(rx))
          ..lineTo(x + rx, y + h)
          ..arcToPoint(Offset(x, y + h - rx), radius: Radius.circular(rx))
          ..lineTo(x, y + rx)
          ..arcToPoint(Offset(x + rx, y), radius: Radius.circular(rx))
          ..close();
      } else {
        path = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, h),
              Radius.circular(rx),
            ),
          );
      }
    case 'ellipse':
      path = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(num('cx'), num('cy')),
            width: num('rx') * 2,
            height: num('ry') * 2,
          ),
        );
    case 'circle':
      path = Path()
        ..addOval(
          Rect.fromCircle(
            center: Offset(num('cx'), num('cy')),
            radius: num('r'),
          ),
        );
    default:
      throw FormatException('unsupported element', n.tag);
  }
  final fill = parseColor(s['fill'] ?? '#000000', ctx.current);
  final stroke = s['stroke'] == null
      ? null
      : parseColor(s['stroke']!, ctx.current);
  return PathShape(
    _applyAff(path, tf),
    fill: fill,
    stroke: stroke,
    strokeWidth: double.tryParse(s['stroke-width'] ?? '') ?? 1,
    cap: switch (s['stroke-linecap']) {
      'round' => StrokeCap.round,
      'square' => StrokeCap.square,
      _ => StrokeCap.butt,
    },
    join: switch (s['stroke-linejoin']) {
      'round' => StrokeJoin.round,
      'bevel' => StrokeJoin.bevel,
      _ => StrokeJoin.miter,
    },
    opacity: num('opacity', 1),
    dashed: dashed,
  );
}
