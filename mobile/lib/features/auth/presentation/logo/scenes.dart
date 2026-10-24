import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../../../../core/theme/app_colors.dart';
import 'actor.dart';
import 'anim.dart';
import 'logo_art.dart' as art;
import 'season.dart';
import 'svg.dart';

/// Time the five taps' streaks take to converge on the logo (the first beat of the "normal" scene).
const _hit = 1000.0;

const _cOut = Cubic(.2, .8, .3, 1);
const _cToss1 = Cubic(.2, .8, .4, 1);
const _cToss2 = Cubic(.5, 0, .9, .6);
const _cConf1 = Cubic(.1, .7, .3, 1);
const _cConf2 = Cubic(.4, 0, .8, .6);

/// A whole scene, built once as data: the actors, each with its animations on a timeline in ms. Nothing here
/// draws; `LogoStage` evaluates it frame by frame. Everything mirrors the reference prototype
/// (docs/plany-easter-egg-prototype.html), a Web Animations `element.animate` per actor.
class LogoScene {
  LogoScene(this.theme, {required this.stageWidth, math.Random? random})
    : _rng = random ?? math.Random() {
    _buildLogo();
    switch (theme) {
      case LogoTheme.normal:
        length = _normal();
      case LogoTheme.halloween:
        length = _halloween();
      case LogoTheme.d24:
        length = _d24();
      case LogoTheme.d25:
        length = _d25();
      case LogoTheme.d31:
        length = _d31();
      case LogoTheme.d1:
        length = _d1();
      case LogoTheme.carnaval:
        length = _carnaval();
      case LogoTheme.pascoa:
        length = _pascoa();
      case LogoTheme.namorados:
        length = _namorados();
      case LogoTheme.junino:
        length = _junino();
      case LogoTheme.dev:
        length = _dev();
    }
    logo.items
      ..clear()
      ..addAll([..._flashes, _pl, swap, oring]);
    for (final a in [...under, ...over, logo, swap, oring, ..._flashes]) {
      a.sortAnims();
    }
    runtime = [
      length,
      ...under.map((a) => a.end),
      ...over.map((a) => a.end),
    ].reduce(math.max);
  }

  static const stageHeight = 280.0;

  final LogoTheme theme;
  final double stageWidth;
  final math.Random _rng;

  /// How long (ms) the scene lasts, as the prototype reports it (what the logo stays busy for).
  late final double length;

  /// When the last particle is gone (some outlive `length`, as in the prototype).
  late final double runtime;

  late final Actor logo, swap, oring;
  late final Actor _pl;
  final List<Actor> _flashes = [];

  /// Behind the logo, in z order, and above it (only the Junino sparks).
  final List<Actor> under = [], over = [];

  double get _cx => stageWidth / 2;
  double get _cy => stageHeight / 2;

  // ---- helpers ----------------------------------------------------------------------------------------------

  double _rnd(double a, double b) => a + _rng.nextDouble() * (b - a);
  T _pick<T>(List<T> l) => l[_rng.nextInt(l.length)];

  void _buildLogo() {
    logo = Actor(
      x: _cx - 44,
      y: _cy - 44,
      w: 88,
      h: 88,
      bg: AppColors.accent,
      radius: 20,
      clip: true,
    );
    _pl = _text('P', 54, AppColors.text);
    _center(_pl, 88, 88);
    swap = Actor(w: 88, h: 88, opacity: 0);
    oring = Actor(
      w: 88,
      h: 88,
      opacity: 0,
      items: [
        PathShape(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(2, 2, 84, 84),
              const Radius.circular(18),
            ),
          ),
          stroke: col('#e2862c'),
          strokeWidth: 4,
        ),
      ],
    );
  }

  /// A text actor; `serif`/`monospace` are the system families (no font packages).
  Actor _text(
    String s,
    double size,
    Color color, {
    bool mono = false,
    bool italic = false,
    double spacing = 0,
  }) {
    final t = TextShape(
      s,
      TextStyle(
        fontFamily: mono ? 'monospace' : 'serif',
        fontSize: size,
        height: 1,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: spacing,
      ),
    );
    return Actor(w: t.width, h: size, items: [t]);
  }

  void _center(Actor a, double w, double h) {
    a.x = (w - a.w) / 2;
    a.y = (h - a.h) / 2;
  }

  PathShape _rect(double w, double h, Color c, [double r = 0]) => PathShape(
    Path()..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
    ),
    fill: c,
  );

  PathShape _oval(double w, double h, Color c) =>
      PathShape(Path()..addOval(Rect.fromLTWH(0, 0, w, h)), fill: c);

  /// An absolute element of the stage, at its center unless `x`/`y` say otherwise, invisible until animated.
  Actor _mk(
    double w,
    double h,
    List<Drawable> items, {
    double? x,
    double? y,
    Offset? origin,
    bool top = false,
  }) {
    final a = Actor(
      x: x ?? _cx - w / 2,
      y: y ?? _cy - h / 2,
      w: w,
      h: h,
      origin: origin,
      items: items,
      opacity: 0,
    );
    (top ? over : under).add(a);
    return a;
  }

  /// An SVG art as an actor of the stage (`size`: its width and height in px).
  (Actor, Svg) _mkSvg(
    String markup,
    double w,
    double h, {
    Color color = const Color(0xFFFFFFFF),
    Map<String, Offset> origins = const {},
    double? x,
    double? y,
    Offset? origin,
    bool top = false,
  }) {
    final s = parseSvg(
      markup,
      width: w,
      height: h,
      currentColor: color,
      origins: origins,
    );
    final a = _mk(w, h, [s.root], x: x, y: y, origin: origin, top: top);
    return (a, s);
  }

  void _anim(
    Actor a,
    List<Fr> frames, {
    required double dur,
    double delay = 0,
    int iters = 1,
    bool alt = false,
    Curve ease = Curves.linear,
    Fill fill = Fill.none,
    double? created,
  }) => a.anims.add(
    Anim(
      frames,
      dur: dur,
      delay: delay,
      iters: iters,
      alt: alt,
      ease: ease,
      fill: fill,
      created: created ?? delay,
    ),
  );

  /// `fly`: animate and disappear; the first and last keyframes are held (`fill: both`).
  void _fly(
    Actor a,
    List<Fr> frames, {
    required double dur,
    double delay = 0,
    Curve ease = Curves.linear,
  }) => _anim(
    a,
    frames,
    dur: dur,
    delay: delay,
    ease: ease,
    fill: Fill.both,
    created: 0,
  );

  /// A flash over the logo (under the P) of its own color, so each one keeps its color.
  Actor _flash(String color) {
    final f = Actor(w: 88, h: 88, bg: col(color), opacity: 0);
    _flashes.add(f);
    return f;
  }

  void _flashFade(
    String color,
    List<Fr> frames,
    double dur, {
    double delay = 0,
  }) => _anim(_flash(color), frames, dur: dur, delay: delay);

  void _ring(String color, double at) {
    for (final dl in [0.0, 140.0]) {
      final r = _mk(88, 88, [
        PathShape(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(1, 1, 86, 86),
              const Radius.circular(19),
            ),
          ),
          stroke: col(color),
          strokeWidth: 2,
        ),
      ]);
      _fly(
        r,
        [fr(0, op: .7), fr(1, s: 2.5, op: 0)],
        dur: 800,
        delay: at + dl,
        ease: const Cubic(.2, .6, .3, 1),
      );
    }
  }

  void _bump(String color, double at) {
    _anim(
      logo,
      [fr(0), fr(.5, s: 1.1), fr(1)],
      dur: 240,
      delay: at,
      ease: Curves.easeOut,
    );
    _flashFade(color, [frOp(0, 0), frOp(.5, .5), frOp(1, 0)], 240, delay: at);
  }

  void _pop(String color) {
    _anim(
      logo,
      [fr(0), fr(.45, s: .92), fr(.5, s: .92), fr(.62, s: 1.2), fr(.8), fr(1)],
      dur: _hit + 500,
      ease: Curves.easeOut,
    );
    _flashFade(color, [
      frOp(0, 0),
      frOp(.66, 0),
      frOp(.74, .7),
      frOp(1, 0),
    ], _hit + 500);
  }

  /// Shows a figure in place of the P: fills the swap layer, which fades in and out over `d`.
  Svg _scene(
    String markup,
    String bg,
    double d, {
    double fadeAt = .86,
    double inAt = .06,
    double at = 0,
    Map<String, Offset> origins = const {},
  }) {
    final s = parseSvg(markup, origins: origins);
    swap.bg = col(bg);
    swap.items
      ..clear()
      ..add(s.root);
    _swapFade(d, fadeAt: fadeAt, inAt: inAt, at: at);
    return s;
  }

  void _swapFade(
    double d, {
    double fadeAt = .86,
    double at = 0,
    double inAt = .06,
  }) => _anim(
    swap,
    [frOp(0, 0), frOp(inAt, 1), frOp(fadeAt, 1), frOp(1, 0)],
    dur: d,
    delay: at,
    fill: Fill.both,
  );

  /// Grows from left to right (written lines).
  void _sx(Actor a, double dl, double du) => _anim(
    a,
    [fr(0, sx: 0), fr(1)],
    dur: du,
    delay: dl,
    ease: Curves.easeOut,
    fill: Fill.both,
  );

  Actor _star(Color c) => Actor(
    w: 14,
    h: 14,
    items: [
      PathShape(parsePathData(art.star).shift(const Offset(7, 7)), fill: c),
    ],
  );

  void _burst(int n, double dl, List<String> cols, double r0, double r1) {
    for (var i = 0; i < n; i++) {
      final a = math.pi * 2 * i / n + _rnd(-.2, .2);
      final d = _rnd(r0, r1);
      final dx = math.cos(a) * d;
      final dy = math.sin(a) * d;
      final s = _mk(14, 14, [_star(col(_pick(cols)))]);
      _fly(
        s,
        [
          fr(0, s: .3, op: 0),
          fr(.4, tx: dx, ty: dy, s: 1.3, r: 120, op: 1),
          fr(1, tx: dx * 1.2, ty: dy * 1.2 + 12, s: 0, r: 240, op: 0),
        ],
        dur: 900,
        delay: dl,
        ease: Curves.easeOut,
      );
    }
  }

  /// Alternating rotation (samba sway, ears).
  void _wob(Actor a, List<double> amps, double dl, double step) {
    final fs = <Fr>[fr(0)];
    for (var i = 0; i < amps.length; i++) {
      fs.add(fr((i + 1) / (amps.length + 1), r: amps[i]));
    }
    fs.add(fr(1));
    _anim(
      a,
      fs,
      dur: step * (amps.length + 1),
      delay: dl,
      ease: Curves.easeInOut,
    );
  }

  /// Arc throw with a fall (eggs, pumpkins, gifts).
  void _toss(
    Actor a,
    double dx,
    double peak,
    double end,
    double rot,
    double delay,
    double sc,
  ) => _fly(
    a,
    [
      fr(0, s: sc, op: 0, e: _cToss1),
      fr(.38, tx: dx * .55, ty: -peak, r: rot * .5, op: 1, e: _cToss2),
      fr(.9, tx: dx, ty: end, r: rot, op: 1),
      fr(1, tx: dx, ty: end, r: rot, op: 0),
    ],
    dur: 1300,
    delay: delay,
  );

  void _streaks(List<String> cols) {
    for (var i = 0; i < 22; i++) {
      final ang = 360 * i / 22 + _rnd(-6, 6);
      final len = _rnd(36, 80).roundToDouble();
      final dl = _rnd(0, 420).roundToDouble();
      final s = _mk(len, 3, [_rect(len, 3, col(cols[i % cols.length]), 2)]);
      _fly(
        s,
        [
          fr(0, r: ang, lx: 290, op: 0),
          fr(.25, r: ang, lx: 190, op: .9),
          fr(1, r: ang, lx: 62, sx: .25, op: 0),
        ],
        dur: _hit - dl,
        delay: dl,
        ease: const Cubic(.5, 0, .9, .6),
      );
    }
  }

  void _snowfall(int n, double d0, double d1) {
    for (var i = 0; i < n; i++) {
      final x = _rnd(-180, 180);
      final sw = _rnd(-26, 26);
      final sz = _rnd(11, 18).roundToDouble();
      final (f, _) = _mkSvg(
        art.snowflake,
        sz,
        sz,
        color: col(i % 3 == 0 ? '#cfe3ff' : '#f2efe8'),
      );
      _fly(
        f,
        [
          fr(0, tx: x, ty: -150, op: 0),
          fr(.1, tx: x + sw * .3, ty: -100, r: 40, op: .9),
          fr(.88, tx: x + sw, ty: 140, r: 260, op: .9),
          fr(1, tx: x + sw, ty: 155, r: 280, op: 0),
        ],
        dur: _rnd(1700, 2400).roundToDouble(),
        delay: _rnd(d0, d1).roundToDouble(),
      );
    }
  }

  static const _confCols = [
    '#e9558f',
    '#2f80ed',
    '#4d6b4d',
    '#f4f1ea',
    '#e2862c',
    '#f2c94c',
  ];

  void _conf(
    int n,
    double d0,
    double d1, {
    List<String> cols = _confCols,
    double at = 0,
  }) {
    for (var k = 0; k < n; k++) {
      final w = _rnd(5, 8).roundToDouble();
      final h = _rnd(8, 12).roundToDouble();
      final an = _rnd(-math.pi * .95, -math.pi * .05);
      final ds = _rnd(90, 170);
      final dx = math.cos(an) * ds;
      final dy = math.sin(an) * ds;
      final fall = _rnd(140, 200);
      final rot = _rnd(-540, 540);
      final el = _mk(w, h, [_rect(w, h, col(_pick(cols)), 1)]);
      _fly(
        el,
        [
          fr(0, op: 0, e: _cConf1),
          fr(.35, tx: dx, ty: dy, r: rot * .4, op: 1, e: _cConf2),
          fr(.9, tx: dx * 1.15, ty: dy + fall, r: rot, op: 1),
          fr(1, tx: dx * 1.15, ty: dy + fall, r: rot, op: 0),
        ],
        dur: 1500,
        delay: at + _rnd(d0, d1).roundToDouble(),
      );
    }
  }

  void _rain(int n, double d0, double d1) {
    for (var k = 0; k < n; k++) {
      final x = _rnd(-185, 185);
      final sw = _rnd(-30, 30);
      final rot = _rnd(-540, 540);
      final w = _rnd(5, 8).roundToDouble();
      final h = _rnd(8, 12).roundToDouble();
      final el = _mk(w, h, [_rect(w, h, col(_pick(_confCols)), 1)]);
      _fly(
        el,
        [
          fr(0, tx: x, ty: -150, op: 0),
          fr(.1, tx: x, ty: -130, r: rot * .1, op: 1),
          fr(.9, tx: x + sw, ty: 140, r: rot, op: .9),
          fr(1, tx: x + sw, ty: 155, r: rot, op: 0),
        ],
        dur: _rnd(1400, 1900).roundToDouble(),
        delay: _rnd(d0, d1).roundToDouble(),
      );
    }
  }

  /// Fireworks: [cx, cy, delay]; `n` particles per burst, radius between `dmin` and `dmax`, `bc` = the flash.
  void _fw(
    List<(double, double, double)> list,
    List<String> cols,
    int n,
    double dmin,
    double dmax,
    String bc,
  ) {
    for (final (cx, cy, d) in list) {
      final r = _mk(5, 5, [_oval(5, 5, col('#f2c94c'))]);
      _fly(
        r,
        [
          fr(0, op: 0),
          fr(.03, op: 1),
          fr(.95, tx: cx, ty: cy, op: 1),
          fr(1, tx: cx, ty: cy, op: 0),
        ],
        dur: 340,
        delay: d,
        ease: const Cubic(.3, .6, .4, 1),
      );
      for (var i = 0; i < n; i++) {
        final a = math.pi * 2 * i / n;
        final dist = _rnd(dmin, dmax);
        final dx = math.cos(a) * dist;
        final dy = math.sin(a) * dist;
        final s = _mk(4, 4, [_oval(4, 4, col(_pick(cols)))]);
        _fly(
          s,
          [
            fr(0, tx: cx, ty: cy, op: 0),
            fr(.05, tx: cx, ty: cy, op: 1),
            fr(.55, tx: cx + dx, ty: cy + dy, op: 1, e: Curves.easeIn),
            fr(1, tx: cx + dx * 1.1, ty: cy + dy + 28, s: .5, op: 0),
          ],
          dur: 1000,
          delay: d + 330,
          ease: _cConf1,
        );
      }
      _bump(bc, d + 330);
    }
  }

  /// The Christmas string of lights (24/12) and the Junino bunting need a line across the stage.
  Actor _line(double y, double h, String color) =>
      _mk(stageWidth, h, [_rect(stageWidth, h, col(color))], x: 0, y: y);

  /// A ground strip with its origin at the bottom, growing upward.
  Actor _floor(double h, String color) => _mk(
    stageWidth,
    h,
    [
      PathShape(
        Path()..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(0, 0, stageWidth, h),
            topLeft: const Radius.circular(10),
            topRight: const Radius.circular(10),
          ),
        ),
        fill: col(color),
      ),
    ],
    x: 0,
    y: stageHeight - h,
    origin: Offset(stageWidth / 2, h),
  );

  List<Fr> _twinkle(int ph) {
    final fs = <Fr>[frOp(0, 0), frOp(.1, 1)];
    var o = .14;
    for (var j = 0; j < 8; j++) {
      fs.add(frOp(o, (j + ph).isOdd ? 1 : .35));
      o += .09;
    }
    fs
      ..add(frOp(.88, 1))
      ..add(frOp(1, 0));
    return fs;
  }

  /// The hat/shine/number pieces that sit in the swap layer at the center of the 88 px logo.
  Actor _swapText(Actor a) {
    _center(a, 88, 88);
    swap.items.add(a);
    return a;
  }

  Actor _shine() {
    final s = Actor(
      x: 0,
      y: -26,
      w: 16,
      h: 140,
      items: [_rect(16, 140, col('#ffffff'))],
      opacity: 0,
    );
    swap.items.add(s);
    return s;
  }

  // ---- scenes: each one builds its actors and returns its length in ms ----------------------------------------

  double _normal() {
    const at = _hit - 100;
    _streaks([
      '#4d6b4d',
      '#6f9a6f',
      '#9cc29c',
      '#f2efe8',
      '#6f9a6f',
      '#9cc29c',
    ]);
    _pop('#8fb58f');
    _ring('#6f9a6f', _hit - 60);
    const d = 1500.0;
    final s = _scene(
      art.note,
      '#4d6b4d',
      d,
      fadeAt: .9,
      at: at,
      origins: const {
        't0': Offset(26, 22.5),
        't1': Offset(26, 35.7),
        't2': Offset(26, 45.7),
        't3': Offset(26, 55.7),
      },
    );
    _anim(
      s.root,
      [fr(0, s: .6, r: -8, e: _cOut), fr(.12, s: 1.06, r: 2), fr(.2), fr(1)],
      dur: d,
      delay: at,
      fill: Fill.both,
    );
    _sx(s['t0'], at + 100, 240);
    _sx(s['t1'], at + 380, 240);
    _sx(s['t2'], at + 660, 200);
    _sx(s['t3'], at + 900, 160);
    Fr p(double x, double y, double o, double op) =>
        fr(o, tx: x, ty: y, op: op);
    _anim(
      s['pen'],
      [
        p(26, 22, 0, 0),
        p(26, 22, .05, 1),
        p(26, 22.5, .0667, 1),
        p(56, 22.5, .2267, 1),
        p(26, 36, .2533, 1),
        p(64, 36, .4133, 1),
        p(26, 46, .44, 1),
        p(58, 46, .5733, 1),
        p(26, 56, .6, 1),
        p(50, 56, .7067, 1),
        p(66, 62, .8, 0),
        p(66, 62, 1, 0),
      ],
      dur: d,
      delay: at,
      fill: Fill.both,
    );
    _anim(
      s['chk'],
      [
        fr(0, s: 0, op: 0),
        fr(.66, s: 0, op: 0),
        fr(.8, s: 1.4, op: 1),
        fr(.9, op: 1),
        fr(1, op: 1),
      ],
      dur: d,
      delay: at,
      fill: Fill.both,
    );
    _bump('#8fb58f', at + 1050);
    _burst(8, at + 1050, ['#f2c94c', '#f4f1ea', '#9cc29c', '#8fb58f'], 55, 95);
    _conf(
      16,
      1050,
      1250,
      at: at,
      cols: ['#4d6b4d', '#6f9a6f', '#9cc29c', '#f2efe8', '#f2c94c'],
    );
    _ring('#9cc29c', at + 1050);
    return _hit + 1600;
  }

  double _halloween() {
    const d = 1800.0;
    final s = _scene(
      art.vamp,
      '#2b1a3a',
      d,
      fadeAt: .84,
      origins: const {'mouth': Offset(44, 56)},
    );
    final fade = [frOp(0, 0), frOp(.06, 1), frOp(.84, 1), frOp(1, 0)];
    _anim(oring, fade, dur: d, fill: Fill.both);
    final fs = <Fr>[fr(0, ty: 88, e: _cOut), fr(.24)];
    var o = .28;
    for (var k = 0; k < 10; k++) {
      fs.add(fr(o, ty: k.isOdd ? 2 : -3, r: k.isOdd ? 3 : -3));
      o += .04;
    }
    fs
      ..add(fr(.72))
      ..add(fr(.88, ty: 88, e: Curves.easeIn))
      ..add(fr(1, ty: 88));
    _anim(s.root, fs, dur: d, fill: Fill.both);
    _anim(
      s['mouth'],
      [fr(0), fr(1, sy: .5)],
      dur: 100,
      delay: (d * .28).roundToDouble(),
      iters: 8,
      alt: true,
    );
    _anim(
      logo,
      [fr(0), fr(.1, s: 1.08), fr(.7, s: 1.08), fr(.9), fr(1)],
      dur: d,
      ease: Curves.easeOut,
    );
    for (var i = 0; i < 9; i++) {
      final sz = _rnd(26, 38).roundToDouble();
      final h = (sz * .94).roundToDouble();
      final (p, _) = _mkSvg(art.pump, sz, h);
      _toss(
        p,
        _rnd(-130, 130),
        _rnd(60, 105),
        _rnd(125, 150),
        _rnd(-240, 240),
        _rnd(550, 750).roundToDouble(),
        .4,
      );
    }
    for (var j = 0; j < 3; j++) {
      final dir = j == 1 ? -1.0 : 1.0;
      final yEnd = -_rnd(80, 120);
      final (w, _) = _mkSvg(art.witch, 52, 42);
      _fly(
        w,
        [
          fr(0, r: -6 * dir, sx: .3 * dir, sy: .3, op: 0),
          fr(.22, tx: dir * 55, ty: -30, r: -10 * dir, sx: dir, op: 1),
          fr(.6, tx: dir * 150, ty: yEnd * .35, r: 6 * dir, sx: dir, op: 1),
          fr(.92, tx: dir * 280, ty: yEnd, r: -8 * dir, sx: dir, op: 1),
          fr(1, tx: dir * 310, ty: yEnd, r: -8 * dir, sx: dir, op: 0),
        ],
        dur: 1300,
        delay: 650 + j * 280,
        ease: Curves.easeInOut,
      );
    }
    _ring(art.o, 500);
    _ring('#8a6ad8', 900);
    return 2500;
  }

  double _d24() {
    const d = 3000.0;
    swap.bg = col('#2d4a37');
    final num = _swapText(_text('24', 44, col('#f4f1ea')));
    final hat = Actor(
      w: 88,
      h: 88,
      items: [parseSvg(art.hatNatal).root],
      opacity: 0,
    );
    swap.items.add(hat);
    _anim(
      hat,
      [fr(0, ty: -50, op: 0, e: _cOut), fr(.6, ty: 4, op: 1), fr(1, op: 1)],
      dur: 450,
      delay: 600,
      fill: Fill.both,
    );
    _swapFade(d, fadeAt: .86);
    _anim(
      num,
      [fr(0, s: .7, op: 0, e: _cOut), fr(.5, s: 1.1, op: 1), fr(1, op: 1)],
      dur: 500,
      fill: Fill.both,
    );
    _anim(
      logo,
      [fr(0), fr(.08, s: 1.1), fr(.18), fr(1)],
      dur: d,
      ease: Curves.easeOut,
    );
    final floor = _floor(16, '#e8ecf5');
    _fly(
      floor,
      [fr(0, sy: 0, op: 1), fr(.12, op: 1), fr(.9, op: 1), fr(1, op: 0)],
      dur: 2900,
      delay: 100,
    );
    final (tree, ts) = _mkSvg(art.tree, 70, 112, origin: const Offset(35, 112));
    Fr tr(
      double o,
      double sx,
      double sy,
      double op, [
      Curve e = Curves.linear,
    ]) => fr(o, tx: 112, ty: 70, sx: sx, sy: sy, op: op, e: e);
    _fly(
      tree,
      [
        tr(0, 1, 0, 1, _cOut),
        tr(.25, 1.04, 1.1, 1),
        tr(.35, 1, 1, 1),
        tr(.9, 1, 1, 1),
        tr(1, 1, 1, 0),
      ],
      dur: 2650,
      delay: 350,
    );
    final orns = ts.classes['orn']!;
    for (var i = 0; i < orns.length; i++) {
      _anim(
        orns[i],
        [frOp(0, 1), frOp(1, .3)],
        dur: 420 + i * 70,
        delay: 900,
        iters: 5,
        alt: true,
      );
    }
    const gifts = [
      (82.0, 26.0),
      (146.0, 24.0),
      (-10.0, 24.0),
      (-52.0, 22.0),
      (112.0, 22.0),
    ];
    for (var i = 0; i < gifts.length; i++) {
      final (x, s) = gifts[i];
      final y = 126 - s / 2;
      final dl = 900.0 + i * 140;
      final p = _pick(art.giftColors);
      final (el, _) = _mkSvg(art.gift(p[0], p[1]), s, s);
      _fly(
        el,
        [
          fr(0, tx: x, ty: y - 44, s: .4, op: 0, e: const Cubic(.3, .9, .4, 1)),
          fr(.3, tx: x, ty: y, sx: 1.1, sy: .9, op: 1),
          fr(.45, tx: x, ty: y, op: 1),
          fr(.9, tx: x, ty: y, op: 1),
          fr(1, tx: x, ty: y, op: 0),
        ],
        dur: 2900 - dl,
        delay: dl,
      );
    }
    const cols = ['#d9453f', '#f2c94c', '#3dbb6a', '#2f80ed'];
    const n = 9;
    final str = _line(12, 2, '#4a4f48');
    _fly(
      str,
      [frOp(0, 0), frOp(.1, 1), frOp(.88, 1), frOp(1, 0)],
      dur: 2800,
      delay: 200,
    );
    for (var i = 0; i < n; i++) {
      final b = _mk(
        8,
        8,
        [_oval(8, 8, col(cols[i % 4]))],
        x: (i + .5) / n * stageWidth - 4,
        y: 10 + (8 * math.sin(i / (n - 1) * math.pi)).roundToDouble(),
      );
      _fly(b, _twinkle(i % 2), dur: 2800, delay: 250 + i * 40);
    }
    _snowfall(12, 300, 1500);
    _ring('#3a7d52', 700);
    _ring('#d9453f', 1000);
    return d + 100;
  }

  double _d25() {
    const d = 3200.0;
    swap.bg = col('#b8352f');
    final num = _swapText(_text('25', 44, col('#f4f1ea')));
    final shine = _shine();
    _swapFade(d, fadeAt: .86, inAt: .05);
    _anim(
      num,
      [
        fr(0, s: 0, r: -12, e: _cOut),
        fr(.5, s: 1.35, r: 5),
        fr(.75, s: .94, r: -2),
        fr(1),
      ],
      dur: 520,
      fill: Fill.both,
    );
    _anim(
      shine,
      [fr(0, tx: -30, r: 20, op: .5), fr(1, tx: 120, r: 20, op: .5)],
      dur: 500,
      delay: 700,
      fill: Fill.both,
    );
    _anim(logo, [
      fr(0),
      fr(.06, s: 1.14),
      fr(.12, s: .96),
      fr(.2, s: 1.06),
      fr(.3),
      fr(1),
    ], dur: d);
    _flashFade('#f2c94c', [
      frOp(0, 0),
      frOp(.06, .5),
      frOp(.2, 0),
      frOp(1, 0),
    ], d);
    for (var i = 0; i < 9; i++) {
      final s = _rnd(24, 34).roundToDouble();
      final p = _pick(art.giftColors);
      final (g, _) = _mkSvg(art.gift(p[0], p[1]), s, s);
      _toss(
        g,
        _rnd(-140, 140),
        _rnd(60, 110),
        _rnd(120, 150),
        _rnd(-240, 240),
        _rnd(350, 600).roundToDouble(),
        .4,
      );
    }
    final (sl, _) = _mkSvg(art.sleigh, 156, 58);
    final sleighFrames = [
      fr(0, s: .25, op: 0),
      fr(.2, tx: 45, ty: -18, s: .7, r: -6, op: 1),
      fr(.5, tx: 140, ty: -60, r: -10, op: 1),
      fr(.8, tx: 250, ty: -105, r: -12, op: 1),
      fr(1, tx: 350, ty: -140, s: 1.05, r: -12, op: 0),
    ];
    _fly(sl, sleighFrames, dur: 2100, delay: 900, ease: Curves.easeIn);
    _trail(sl, 900, 1900);
    final hh = _text('Ho ho ho!', 20, col('#f4f1ea'), italic: true);
    final hoho = _mk(hh.w, hh.h, hh.items);
    _fly(
      hoho,
      [
        fr(0, ty: -70, s: .6, op: 0),
        fr(.25, ty: -84, op: 1),
        fr(.7, ty: -92, op: 1),
        fr(1, ty: -102, op: 0),
      ],
      dur: 1500,
      delay: 1300,
      ease: Curves.easeOut,
    );
    _snowfall(18, 0, 1600);
    _ring('#d9453f', 300);
    _ring('#f2c94c', 1100);
    return d + 100;
  }

  /// Sparks behind a moving element: the prototype read the sleigh's position every 70 ms; here the
  /// position is sampled from its own animation at the same instants.
  void _trail(Actor el, double start, double dur) {
    for (var t = 0.0; t <= dur; t += 70) {
      final pose = el.anims.first.sample(start + t)!;
      final tf = pose.tf!;
      // the prototype puts the dot's left/top at (center - 50, center + 6)
      final x = _cx + tf.tx - 50;
      final y = _cy + tf.ty + 6;
      final st = _mk(
        6,
        6,
        [
          _oval(6, 6, col(_pick(['#f2c94c', '#f4f1ea', '#9fd0f0']))),
        ],
        x: x,
        y: y,
      );
      _fly(
        st,
        [fr(0, op: .9), fr(1, tx: -16, ty: 6, s: .2, op: 0)],
        dur: 700,
        delay: start + t,
      );
    }
  }

  double _d31() {
    const d = 2800.0;
    final s = _scene(
      '<svg viewBox="0 0 88 88" width="88" height="88"><rect x="3" y="3" width="82" height="82" rx="17" fill="none" stroke="#34405e" stroke-width="3"/><rect id="prog" x="3" y="3" width="82" height="82" rx="17" fill="none" stroke="#d9b44a" stroke-width="3" stroke-linecap="round" stroke-dasharray="300" stroke-dashoffset="300"/></svg>',
      '#222c45',
      d,
      fadeAt: .86,
      inAt: .12,
    );
    final num = _swapText(_text('31', 44, col('#d8dde8')));
    Fr nf(double sc, String c, double o, [double op = 1]) =>
        fr(o, s: sc, op: op, c: col(c));
    _anim(
      num,
      [
        nf(.9, '#d8dde8', 0, 0),
        nf(1, '#d8dde8', .16),
        nf(1.04, '#d8dde8', .35),
        nf(1, '#d8dde8', .5),
        nf(1.04, '#d8dde8', .6),
        nf(1.25, '#f2c94c', .66),
        nf(1, '#f2c94c', .76),
        nf(1, '#f2c94c', 1),
      ],
      dur: d,
      fill: Fill.both,
    );
    _anim(
      s['prog'],
      [fr(0, v: 0, tf: false), fr(1, v: 300, tf: false)],
      dur: 1500,
      delay: 300,
      fill: Fill.both,
    );
    _anim(
      logo,
      [
        fr(0),
        fr(.25, s: .97),
        fr(.6, s: .97),
        fr(.67, s: 1.12),
        fr(.76),
        fr(1),
      ],
      dur: d,
      ease: Curves.easeInOut,
    );
    for (var i = 0; i < 16; i++) {
      final x = (i.isOdd ? 1 : -1) * _rnd(70, 170);
      var y = _rnd(-120, 120);
      if (x.abs() < 75 && y.abs() < 60) y = y < 0 ? -70 : 70;
      final sz = _rnd(2, 4).roundToDouble();
      final st = _mk(sz, sz, [
        _oval(sz, sz, col(_pick(['#d9b44a', '#e8ecf5', '#b8c4e0']))),
      ]);
      _fly(
        st,
        [
          fr(0, tx: x, ty: y, op: 0),
          fr(.5, tx: x, ty: y - 6, op: .9),
          fr(1, tx: x, ty: y - 12, op: 0),
        ],
        dur: _rnd(1400, 2000).roundToDouble(),
        delay: _rnd(0, 1100).roundToDouble(),
        ease: Curves.easeInOut,
      );
    }
    _fw(
      const [(-92, -52, 1750), (96, -64, 2000)],
      ['#f2c94c', '#e8ecf5', '#9fd0f0'],
      12,
      26,
      44,
      '#f2c94c',
    );
    _conf(18, 1850, 2100);
    _ring('#d9b44a', 1800);
    return d + 100;
  }

  double _d1() {
    const d = 3400.0;
    const cols = ['#f2c94c', '#f2efe8', '#9fd0f0', '#f4b6c8', '#8fb58f'];
    swap.bg = col('#f2c94c');
    final one = TextShape(
      '1',
      TextStyle(
        fontFamily: 'serif',
        fontSize: 58,
        height: 1,
        color: col('#2d3f2d'),
      ),
    );
    final deg = TextShape(
      'º',
      TextStyle(
        fontFamily: 'serif',
        fontSize: 26,
        height: 1,
        color: col('#2d3f2d'),
      ),
      at: Offset(one.width, 9),
    );
    final num = _swapText(
      Actor(w: one.width + deg.width, h: 58, items: [one, deg]),
    );
    final shine = _shine();
    final hat = Actor(
      w: 88,
      h: 88,
      items: [parseSvg(art.hatParty).root],
      opacity: 0,
    );
    swap.items.add(hat);
    _swapFade(d, fadeAt: .88, inAt: .03);
    _anim(
      num,
      [
        fr(0, s: 0, r: -14, e: _cOut),
        fr(.5, s: 1.35, r: 6),
        fr(.75, s: .94, r: -2),
        fr(1),
      ],
      dur: 520,
      fill: Fill.both,
    );
    _anim(
      hat,
      [fr(0, ty: -50, op: 0, e: _cOut), fr(.6, ty: 4, op: 1), fr(1, op: 1)],
      dur: 420,
      delay: 500,
      fill: Fill.both,
    );
    final sweep = [
      fr(0, tx: -30, r: 20, op: .55),
      fr(1, tx: 120, r: 20, op: .55),
    ];
    _anim(shine, sweep, dur: 500, delay: 700, fill: Fill.both);
    _anim(shine, sweep, dur: 500, delay: 1700, fill: Fill.forwards);
    Fr j(double y, double sx, double sy, double o) =>
        fr(o, ty: y, sx: sx, sy: sy);
    _anim(
      logo,
      [
        j(0, 1, 1, 0),
        j(-14, .98, 1.04, .05),
        j(0, 1.08, .92, .09),
        j(-10, .98, 1.04, .14),
        j(0, 1.06, .94, .18),
        j(-6, 1, 1, .22),
        j(0, 1, 1, .26),
        j(0, 1, 1, .4),
        j(-12, .98, 1.04, .46),
        j(0, 1.08, .92, .5),
        j(0, 1, 1, .56),
        j(0, 1, 1, 1),
      ],
      dur: d,
      ease: Curves.easeOut,
    );
    _flashFade('#f2c94c', [
      frOp(0, 0),
      frOp(.05, .5),
      frOp(.15, 0),
      frOp(1, 0),
    ], d);
    _fw(
      const [
        (-112, -45, 150),
        (108, -62, 500),
        (-45, -100, 850),
        (55, -105, 1200),
        (0, 95, 1550),
      ],
      cols,
      18,
      40,
      70,
      '#f2c94c',
    );
    _conf(56, 250, 800);
    _rain(30, 700, 2000);
    const bc = ['#e9558f', '#2f80ed', '#f2c94c', '#3dbb6a', '#e2862c'];
    for (var i = 0; i < 5; i++) {
      final x = -150 + i * 75 + _rnd(-18, 18);
      final (b, _) = _mkSvg(art.balloon(bc[i]), 26, 56);
      _fly(
        b,
        [
          fr(0, tx: x, ty: 170, op: 0),
          fr(.06, tx: x, ty: 120, op: 1),
          fr(.5, tx: x + 14, ty: -10, op: 1),
          fr(.8, tx: x - 12, ty: -110, op: 1),
          fr(1, tx: x + 6, ty: -190, op: .9),
        ],
        dur: 2100,
        delay: 400 + i * 220,
        ease: Curves.easeInOut,
      );
    }
    _ring('#f2c94c', 150);
    _ring('#e9558f', 1000);
    _ring('#2f80ed', 1800);
    return d + 100;
  }

  double _carnaval() {
    const d = 2500.0;
    final s = _scene(
      art.mask,
      '#3a1f5c',
      d,
      fadeAt: .88,
      origins: const {'fe': Offset(70, 40)},
    );
    _anim(swap, [
      fr(0, c: col('#3a1f5c'), tf: false),
      fr(.25, c: col('#5b2a86'), tf: false),
      fr(.5, c: col('#7a1f5c'), tf: false),
      fr(.75, c: col('#1f3a7a'), tf: false),
      fr(1, c: col('#3a1f5c'), tf: false),
    ], dur: d);
    final fs = <Fr>[
      fr(0, ty: 70, r: -30, s: .5, e: _cOut),
      fr(.14, ty: -6, r: 6, s: 1.1),
      fr(.2),
    ];
    var o = .24;
    for (var k = 0; k < 8; k++) {
      fs.add(
        fr(o, ty: k.isOdd ? 0 : -5, r: k.isOdd ? 9 : -9, s: k.isOdd ? 1 : 1.06),
      );
      o += .075;
    }
    fs
      ..add(fr(.88))
      ..add(fr(1));
    _anim(s.root, fs, dur: d, fill: Fill.both);
    _anim(
      s['mk'],
      [
        fr(0, c: col('#f2c94c'), tf: false),
        fr(.25, c: col('#e9558f'), tf: false),
        fr(.5, c: col('#9fd0f0'), tf: false),
        fr(.75, c: col('#3dbb6a'), tf: false),
        fr(1, c: col('#f2c94c'), tf: false),
      ],
      dur: 2000,
      delay: 300,
    );
    for (final (i, id) in [(0, 'g1'), (1, 'g2')]) {
      _anim(
        s[id],
        [frOp(0, 1), frOp(1, .1)],
        dur: 200.0 + i * 60,
        delay: 400,
        iters: 10,
        alt: true,
      );
    }
    _anim(
      s['fe'],
      [fr(0, r: -8), fr(1, r: 8)],
      dur: 300,
      delay: 400,
      iters: 8,
      alt: true,
      ease: Curves.easeInOut,
    );
    _anim(logo, [
      fr(0),
      fr(.2, r: -6, s: 1.06),
      fr(.4, r: 6, s: 1.06),
      fr(.6, r: -6, s: 1.06),
      fr(.8),
      fr(1),
    ], dur: 2200);
    const cols = [
      '#f2c94c',
      '#3dbb6a',
      '#2f80ed',
      '#e9558f',
      '#9b51e0',
      '#f2994a',
    ];
    for (var i = 0; i < 10; i++) {
      final h = _rnd(46, 90).roundToDouble();
      final a = _rnd(-math.pi * .95, -math.pi * .05);
      final dd = _rnd(90, 170);
      final dx = math.cos(a) * dd;
      final dy = math.sin(a) * dd;
      final fall = _rnd(140, 200);
      final rot = _rnd(-540, 540);
      final st = _mk(3, h, [_rect(3, h, col(_pick(cols)), 2)]);
      _fly(
        st,
        [
          fr(0, op: 0, e: _cConf1),
          fr(.35, tx: dx, ty: dy, r: rot * .4, op: 1, e: _cConf2),
          fr(.9, tx: dx * 1.15, ty: dy + fall, r: rot, op: 1),
          fr(1, tx: dx * 1.15, ty: dy + fall, r: rot, op: 0),
        ],
        dur: 1600,
        delay: _rnd(150, 500).roundToDouble(),
      );
    }
    _conf(24, 150, 450);
    _conf(24, 1100, 1500);
    _flashFade('#f2c94c', [
      frOp(0, 0),
      frOp(.06, .45),
      frOp(.2, 0),
      frOp(1, 0),
    ], d);
    _ring('#f2c94c', 60);
    _ring('#e9558f', 1200);
    return d + 300;
  }

  double _pascoa() {
    const d = 2500.0;
    final s = _scene(
      art.bunny,
      '#bfe3cf',
      d,
      fadeAt: .88,
      origins: const {'e1': Offset(33, 42), 'e2': Offset(55, 42)},
    );
    Fr b(double o, double y, double sx, double sy, [Curve e = Curves.linear]) =>
        fr(o, ty: y, sx: sx, sy: sy, e: e);
    _anim(
      s.root,
      [
        b(0, 88, 1, 1, _cOut),
        b(.2, 0, 1, 1),
        b(.32, -14, .96, 1.06, Curves.easeIn),
        b(.42, 0, 1.08, .92),
        b(.54, -14, .96, 1.06, Curves.easeIn),
        b(.64, 0, 1.08, .92),
        b(.7, 0, 1, 1),
        b(.78, 0, 1, 1),
        b(.92, 88, 1, 1, Curves.easeIn),
        b(1, 88, 1, 1),
      ],
      dur: d,
      fill: Fill.both,
    );
    _wob(s['e1'], const [-14, 8, -10, 6, -8, 0], 500, 170);
    _wob(s['e2'], const [12, -7, 10, -6, 8, 0], 560, 170);
    for (final id in ['y1', 'y2']) {
      for (final dl in [900.0, 1500.0]) {
        _anim(s[id], [fr(0), fr(.5, sy: .1), fr(1)], dur: 180, delay: dl);
      }
    }
    _anim(
      s['nz'],
      [fr(0), fr(1, s: 1.35)],
      dur: 110,
      delay: 700,
      iters: 10,
      alt: true,
    );
    final floor = _floor(18, '#6fb583');
    _fly(
      floor,
      [fr(0, sy: 0, op: 1), fr(.1, op: 1), fr(.92, op: 1), fr(1, op: 0)],
      dur: 2700,
      delay: 50,
    );
    const pc = ['#f4b6c8', '#b9a7e8', '#a8dcc0', '#f6e08f', '#9fd0f0'];
    for (var i = 0; i < 11; i++) {
      final w = _rnd(14, 20).roundToDouble();
      final h = (w * 1.3).roundToDouble();
      final c = col(pc[i % 5]);
      final c2 = col(pc[(i + 2) % 5]);
      final egg = Path()
        ..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(0, 0, w, h),
            topLeft: Radius.elliptical(w / 2, h * .62),
            topRight: Radius.elliptical(w / 2, h * .62),
            bottomLeft: Radius.elliptical(w / 2, h * .38),
            bottomRight: Radius.elliptical(w / 2, h * .38),
          ),
        );
      final stripe = Path.combine(
        PathOperation.intersect,
        egg,
        Path()..addRect(Rect.fromLTWH(0, h / 2, w, 3)),
      );
      final e = _mk(w, h, [
        PathShape(egg, fill: c),
        PathShape(stripe, fill: c2),
      ]);
      _toss(
        e,
        _rnd(-125, 125),
        _rnd(70, 115),
        _rnd(112, 128),
        _rnd(-200, 200),
        _rnd(550, 1100).roundToDouble(),
        1,
      );
    }
    final (c1, _) = _mkSvg(art.carrot, 18, 36);
    _toss(c1, -100, 90, 112, -160, 900, .6);
    final (c2, _) = _mkSvg(art.carrot, 18, 36);
    _toss(c2, 105, 80, 112, 150, 1200, .6);
    const flies = [
      (-1.0, -70.0, 400.0, '#e9558f', '#f4b6c8'),
      (1.0, -100.0, 1000.0, '#9b51e0', '#b9a7e8'),
    ];
    for (final (dir, y, dl, k1, k2) in flies) {
      final wings = parseSvg(art.butterfly(k1, k2)).root;
      final bf = _mk(24, 20, [wings]);
      _anim(
        wings,
        [fr(0), fr(1, sx: .35)],
        dur: 110,
        delay: dl,
        iters: 16,
        alt: true,
      );
      _fly(
        bf,
        [
          fr(0, tx: -dir * 200, ty: y + 20, op: 0),
          fr(.15, tx: -dir * 120, ty: y - 16, op: 1),
          fr(.4, tx: -dir * 30, ty: y + 14, op: 1),
          fr(.65, tx: dir * 60, ty: y - 14, op: 1),
          fr(1, tx: dir * 210, ty: y + 6, op: 0),
        ],
        dur: 1800,
        delay: dl,
      );
    }
    _flashFade('#f6e08f', [
      frOp(0, 0),
      frOp(.08, .5),
      frOp(.25, 0),
      frOp(1, 0),
    ], d);
    _ring('#b9a7e8', 300);
    _ring('#6fb583', 1300);
    return d + 300;
  }

  double _namorados() {
    const d = 2500.0;
    final s = _scene(
      art.bigheart,
      '#b83a5a',
      d,
      fadeAt: .9,
      origins: const {'arw': Offset.zero},
    );
    Fr h(double o, double sx, [double? sy]) => fr(o, sx: sx, sy: sy ?? sx);
    _anim(
      s.root,
      [
        fr(0, s: .3, r: -10, e: _cOut),
        fr(.1, s: 1.15),
        h(.14, 1),
        h(.2, 1.12),
        h(.24, 1),
        h(.28, 1.1),
        h(.32, 1),
        h(.448, 1),
        h(.47, .86, 1.1),
        h(.5, 1.14),
        h(.54, .96),
        h(.58, 1),
        h(.66, 1.14),
        h(.7, 1),
        h(.74, 1.12),
        h(.78, 1),
        h(1, 1),
      ],
      dur: d,
      fill: Fill.both,
    );
    Fr a(
      double rot,
      double x,
      double op,
      double o, [
      Curve e = Curves.linear,
    ]) => fr(o, tx: 44, ty: 46, r: rot, lx: x, op: op, e: e);
    _anim(
      s['arw'],
      [
        a(45, -80, 0, 0),
        a(45, -80, 0, .34),
        a(45, -70, 1, .35, const Cubic(.5, 0, .9, .5)),
        a(45, 0, 1, .448),
        a(49, 0, 1, .5),
        a(41, 0, 1, .54),
        a(45, 0, 1, .6),
        a(45, 0, 1, 1),
      ],
      dur: d,
      fill: Fill.both,
    );
    final (cp, _) = _mkSvg(art.cupid, 44, 40);
    _fly(
      cp,
      [
        fr(0, tx: -210, ty: -90, s: .7, op: 0),
        fr(.25, tx: -92, ty: -82, op: 1),
        fr(.33, tx: -88, ty: -90, op: 1),
        fr(.42, tx: -92, ty: -84, op: 1),
        fr(.52, tx: -88, ty: -90, op: 1),
        fr(.62, tx: -60, ty: -110, op: 1),
        fr(1, tx: 60, ty: -130, s: .8, op: 0),
      ],
      dur: 2000,
      delay: 100,
      ease: Curves.easeInOut,
    );
    _bump('#ff6f91', 1120);
    for (var i = 0; i < 13; i++) {
      final sz = _rnd(14, 26).roundToDouble();
      final sw = _rnd(18, 46) * (i.isOdd ? 1 : -1);
      final x0 = _rnd(-30, 30);
      final rise = _rnd(110, 140);
      final (hh, _) = _mkSvg(
        art.heartIcon,
        sz,
        sz,
        color: col(_pick(['#e9558f', '#f4b6c8', '#c0453f', '#f2efe8'])),
      );
      _fly(
        hh,
        [
          fr(0, tx: x0, s: .3, op: 0),
          fr(.3, tx: x0 + sw, ty: -rise * .45, op: 1),
          fr(.7, tx: x0 - sw * .6, ty: -rise * .8, op: 1),
          fr(1, tx: x0 + sw * .4, ty: -rise, s: .9, op: 0),
        ],
        dur: 1500,
        delay: _rnd(1150, 1750).roundToDouble(),
        ease: Curves.easeOut,
      );
    }
    _burst(8, 1120, ['#f4b6c8', '#f4f1ea', '#ff6f91'], 50, 90);
    _ring('#e9558f', 1120);
    _ring('#f4b6c8', 1800);
    return d + 300;
  }

  double _junino() {
    const d = 2700.0;
    const flame = Offset(44, 76);
    final s = _scene(
      art.bonfire,
      '#1c2447',
      d,
      fadeAt: .9,
      origins: const {'fl': flame, 'f1': flame, 'f2': flame, 'f3': flame},
    );
    _anim(
      s['fl'],
      [
        fr(0, sx: .2, sy: 0, e: _cOut),
        fr(.14, sx: 1.15, sy: 1.2),
        fr(.2),
        fr(1),
      ],
      dur: d,
      fill: Fill.both,
    );
    for (var i = 0; i < 3; i++) {
      final dur = 150.0 + i * 55;
      _anim(
        s['f${i + 1}'],
        [
          fr(0),
          fr(1, sx: .93 - i * .02, sy: 1.1 + i * .04, k: i.isOdd ? 4 : -4),
        ],
        dur: dur,
        delay: 450,
        iters: (2000 / dur).round(),
        alt: true,
        ease: Curves.easeInOut,
      );
    }
    final stars = s.classes['st']!;
    for (var i = 0; i < stars.length; i++) {
      _anim(
        stars[i],
        [frOp(0, 1), frOp(1, .2)],
        dur: 300.0 + i * 90,
        iters: 12,
        alt: true,
      );
    }
    const cols = [
      '#e9558f',
      '#f2c94c',
      '#3dbb6a',
      '#2f80ed',
      '#e2862c',
      '#9b51e0',
    ];
    const n = 10;
    final line = _line(12, 2, '#c9a56a');
    _fly(line, [
      frOp(0, 0),
      frOp(.1, .9),
      frOp(.88, .9),
      frOp(1, 0),
    ], dur: 2700);
    for (var i = 0; i < n; i++) {
      final flag = _mk(
        20,
        24,
        [
          PathShape(
            Path()
              ..moveTo(0, 0)
              ..lineTo(20, 0)
              ..lineTo(10, 24)
              ..close(),
            fill: col(cols[i % cols.length]),
          ),
        ],
        x: (i + .5) / n * stageWidth - 10,
        y: 13,
        origin: const Offset(10, 0),
      );
      Fr r(double deg, double o, [double op = 1]) => fr(o, r: deg, op: op);
      _fly(
        flag,
        [
          fr(0, ty: -40, op: 0),
          r(0, .1),
          r(7, .25),
          r(-7, .4),
          r(5, .55),
          r(-4, .7),
          r(0, .88),
          r(0, 1, 0),
        ],
        dur: 2600,
        delay: i * 70.0,
        ease: Curves.easeOut,
      );
    }
    const balloons = [
      (-105.0, '#e9558f', 200.0),
      (110.0, '#f2c94c', 500.0),
      (-30.0, '#3dbb6a', 850.0),
      (45.0, '#e2862c', 1150.0),
    ];
    for (final (x, c, dl) in balloons) {
      final (bl, _) = _mkSvg(art.festaBalloon(c), 28, 44);
      _fly(
        bl,
        [
          fr(0, tx: x, ty: 170, s: .8, op: 0),
          fr(.2, tx: x + 12, ty: 90, s: .9, op: 1),
          fr(.5, tx: x - 10, op: 1),
          fr(.8, tx: x + 12, ty: -90, op: 1),
          fr(1, tx: x - 6, ty: -170, op: 0),
        ],
        dur: 2100,
        delay: dl,
        ease: Curves.easeInOut,
      );
    }
    for (var k = 0; k < 24; k++) {
      final sz = _rnd(3, 5).roundToDouble();
      final x = _rnd(-16, 16);
      final y0 = _rnd(10, 34);
      final rise = _rnd(110, 190);
      final sp = _mk(sz, sz, [
        _oval(sz, sz, col(_pick(['#e2862c', '#f2c94c', '#f2994a', '#c0453f']))),
      ], top: true);
      _fly(
        sp,
        [
          fr(0, tx: x, ty: y0, op: 0),
          fr(.25, tx: x + _rnd(-18, 18), ty: y0 - rise * .4, op: 1),
          fr(.7, tx: x + _rnd(-30, 30), ty: y0 - rise * .75, op: .8),
          fr(1, tx: x + _rnd(-40, 40), ty: y0 - rise, op: 0),
        ],
        dur: 1100,
        delay: _rnd(250, 1900).roundToDouble(),
        ease: Curves.easeOut,
      );
    }
    _fw(
      const [(-95, -72, 1500), (100, -88, 1900), (5, -112, 2300)],
      ['#f2c94c', '#e9558f', '#9fd0f0', '#f4f1ea'],
      14,
      30,
      60,
      '#f2c94c',
    );
    _anim(logo, [
      fr(0),
      fr(.1, s: 1.06),
      fr(.2),
      fr(.4, s: 1.04),
      fr(.6),
      fr(1),
    ], dur: 1800);
    _flashFade('#e2862c', [
      frOp(0, 0),
      frOp(.1, .5),
      frOp(.25, 0),
      frOp(1, 0),
    ], d);
    _ring('#e2862c', 400);
    return d + 300;
  }

  double _dev() {
    const d = 1800.0;
    const chars = '01{}<>/;=()[]&|';
    swap.bg = col('#1e2d1e');
    _swapText(_text('<P/>', 24, col('#cfe8cf'), mono: true, spacing: -1));
    _anim(
      swap,
      [
        frOp(0, 0),
        frOp(.1, 1),
        frOp(.14, .3),
        frOp(.18, 1),
        frOp(.22, .5),
        frOp(.26, 1),
        frOp(.6, 1),
        frOp(.7, 0),
        frOp(1, 0),
      ],
      dur: d,
      fill: Fill.both,
    );
    _anim(
      logo,
      [fr(0), fr(.18, s: 1.1), fr(.3), fr(1)],
      dur: d,
      ease: Curves.easeOut,
    );
    const cols = 16;
    for (var i = 0; i < cols; i++) {
      final len = 5 + _rnd(0, 3).floor();
      final items = <Drawable>[];
      double w = 0;
      for (var j = 0; j < len; j++) {
        final ch = chars[_rng.nextInt(chars.length)];
        final last = j == len - 1;
        final t = TextShape(
          ch,
          TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 15 / 13,
            color: col(last ? '#cfe8cf' : '#6f9a6f'),
          ),
          opacity: .25 + .75 * j / (len - 1),
        );
        w = math.max(w, t.width);
        items.add(t);
      }
      // each row is centered in the column, like the prototype's `text-align:center`
      for (var j = 0; j < items.length; j++) {
        final t = items[j] as TextShape;
        items[j] = TextShape(
          t.text,
          t.style,
          at: Offset((w - t.width) / 2, j * 15.0),
          opacity: t.opacity,
        );
      }
      final c = _mk(
        w,
        len * 15.0,
        items,
        x: (i + .5) / cols * stageWidth - 4,
        y: 0,
      );
      _fly(
        c,
        [
          fr(0, ty: -110, op: 0),
          fr(.15, ty: 10, op: 1),
          fr(.7, ty: 160, op: .9),
          fr(1, ty: 300, op: 0),
        ],
        dur: _rnd(1100, 1500),
        delay: _rnd(0, 500).roundToDouble(),
      );
    }
    _flashFade('#9cc29c', [
      frOp(0, 0),
      frOp(.6, 0),
      frOp(.68, .5),
      frOp(.85, 0),
      frOp(1, 0),
    ], d);
    _ring('#6f9a6f', 900);
    return d + 300;
  }
}
