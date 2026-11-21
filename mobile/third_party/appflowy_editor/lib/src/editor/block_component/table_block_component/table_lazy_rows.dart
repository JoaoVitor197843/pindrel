// Pindrel: a column of rows of which only the ones near the screen exist, built as richly as the page's speed allows.
//
// A table is one item of the page's list, so Flutter builds all of its rows together however long it is. This widget
// keeps a height per row (measured, or guessed until then) and builds only the rows inside the scrollable's viewport
// plus a margin; the others are two spacers (above and below) of the summed height. The same idea as the web's `Lazy`
// boxes. A row in [keep] is built wherever it is (the one being edited must not be torn down while the page scrolls
// past it).
//
// A row is built at one of three levels of detail, by how the page moves, because what it costs decides whether the
// frame is on time (measured on the real page: a paragraph of the editor ~1 ms, so a row of eight ~8 ms, and a frame at
// 120 Hz has 8 ms, at 60 Hz 16):
//  * skeleton: an empty box of the row's height, while the page is going fast (nobody reads text flying by);
//  * light: plain text, while it moves slower;
//  * full: the paragraphs of the editor, 100 ms after it stopped.
// Rows already built are raised, one a frame (the ones nearest the top of the screen first), so no frame pays for all.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

enum RowDetail { skeleton, light, full }

/// Whether this device can draw rows of text while the page moves and keep to its frame budget.
///
/// Measured with the real page and a CPU limited to half a core: text in the rows that go by cost a frame 12-13 ms
/// against 7-8 for the skeleton (93% of the frames in 16.7 ms against 70%), most of it in drawing the glyphs. A
/// phone that can afford the text should show it, one that cannot should not try, so the frames drawn while rows of
/// text are going by are timed: when they average over four fifths of a frame's time, text waits for the page to stop
/// (a skeleton is drawn instead) for a minute, and then it is tried again.
class RowBudget {
  RowBudget._();

  static bool _registered = false;
  static bool textOk = true;

  /// The person asked to spare the battery: rows going by are bars, never text, whatever the timing says.
  static bool saving = false;
  static bool lightOnScreen = false; // set by a LazyRows while it shows rows of plain text that are moving
  static double _average = 0;
  static int _samples = 0;
  static DateTime? _retryAt;

  static void ensure() {
    if (_registered) return;
    _registered = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    if (!textOk) {
      if (_retryAt != null && now.isAfter(_retryAt!)) {
        textOk = true;
        _average = 0;
        _samples = 0;
      }
      return;
    }
    if (!lightOnScreen) return;
    final display = WidgetsBinding.instance.platformDispatcher.views.firstOrNull?.display.refreshRate ?? 60;
    for (final t in timings) {
      // the two threads work side by side: a frame is late when the slower of them is
      final ms = (t.buildDuration > t.rasterDuration ? t.buildDuration : t.rasterDuration).inMicroseconds / 1000;
      record(ms, display);
    }
  }

  /// One frame that took [ms] on a screen of [refreshRate] Hz, drawn while rows of text were going by.
  static void record(double ms, [double refreshRate = 60]) {
    if (!textOk || !lightOnScreen) return;
    final budget = 1000 / (refreshRate < 30 ? 60 : refreshRate);
    // a hitch (a collection of garbage, a page opening) counts for no more than two frames' worth: a verdict needs many
    final capped = ms < budget * 2 ? ms : budget * 2;
    _average = _samples == 0 ? capped : _average * 0.9 + capped * 0.1;
    _samples++;
    if (_samples >= 30 && _average > budget * 0.8) {
      textOk = false;
      _retryAt = DateTime.now().add(const Duration(minutes: 1));
    }
  }

  /// Tests and probes: forget what was measured.
  static void reset() {
    textOk = true;
    lightOnScreen = false;
    _average = 0;
    _samples = 0;
    _retryAt = null;
  }
}

class LazyRows extends StatefulWidget {
  const LazyRows({
    super.key,
    required this.count,
    required this.rowBuilder,
    this.estimateFor,
    this.keep = const {},
    this.initial = 12,
    this.fastSpeed = 1600,
  });

  final int count;

  /// Builds row [row] at [detail]; [height] is what the row is expected to measure.
  final Widget Function(BuildContext context, int row, RowDetail detail, double height) rowBuilder;

  /// The height guessed for a row that was never built (28 when not given).
  final double Function(int row)? estimateFor;

  /// Rows that stay built while off screen.
  final Set<int> keep;

  /// Rows built before the viewport is known (the first frame).
  final int initial;

  /// Pixels a second above which rows are built as skeletons.
  final double fastSpeed;

  @override
  State<LazyRows> createState() => LazyRowsState();
}

class LazyRowsState extends State<LazyRows> {
  final _heights = <int, double>{};
  // The widgets of the rows in the window, kept while the window moves so only the rows that enter are built
  // (the same widget object is skipped by Flutter). The parent rebuilding means the rows may differ: start over.
  final _built = <int, Widget>{};
  final _detail = <int, RowDetail>{};
  // Rows above the top of the screen that were measured for the first time since the last look: the page is moved
  // by how much they differ from the guess, so what is on screen stays where it is.
  var _shift = 0.0;
  var _topRow = 0; // the row at the top of the screen at the last look
  int _from = 0, _to = 0; // built rows: [_from, _to)
  ScrollPosition? _position;
  bool _scheduled = false;
  var _moving = false, _fast = false;
  Timer? _settleTimer;
  double _lastPixels = 0, _speed = 0;
  var _fastUntil = 0;
  var _lastAt = 0;

  /// How many rows are built right now (the tests read it).
  int get built => _to - _from;

  /// What the widget is doing, for tests and probes.
  String get summary => 'rows $_from..$_to moving=$_moving fast=$_fast speed=${_speed.round()} details=${{for (final d in RowDetail.values) d.name: _detail.values.where((e) => e == d).length}}';

  RowDetail get _want => _fast || (_moving && (!RowBudget.textOk || RowBudget.saving)) ? RowDetail.skeleton : (_moving ? RowDetail.light : RowDetail.full);

  @override
  void initState() {
    super.initState();
    RowBudget.ensure();
    _to = widget.initial.clamp(0, widget.count);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = _verticalScrollable()?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_onScroll);
      _position = position?..addListener(_onScroll);
      _lastPixels = position?.hasPixels == true ? position!.pixels : 0;
    }
    _schedule();
  }

  @override
  void didUpdateWidget(LazyRows old) {
    super.didUpdateWidget(old);
    _built.clear();
    _detail.clear();
    if (old.count != widget.count) {
      _heights.removeWhere((r, _) => r >= widget.count);
      _to = _to.clamp(0, widget.count);
      _from = _from.clamp(0, _to);
    }
    // rows changed: their old heights are guesses until they are built again
    _schedule();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    RowBudget.lightOnScreen = false;
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  ScrollableState? _verticalScrollable() {
    var ctx = context;
    for (var i = 0; i < 8; i++) {
      final s = Scrollable.maybeOf(ctx);
      if (s == null) return null;
      if (s.axisDirection == AxisDirection.down || s.axisDirection == AxisDirection.up) return s;
      ctx = s.context;
    }
    return null;
  }

  var _correcting = false; // the page is being moved by this widget, to keep what is on screen where it is

  void _onScroll() {
    final p = _position;
    if (_correcting) {
      // not the person's movement: no speed, no motion
      if (p != null && p.hasPixels) _lastPixels = p.pixels;
      return;
    }
    if (p != null && p.hasPixels) {
      // the clock of the frames (not the wall's): what the page moves by, and what a test can advance; read outside a frame, too
      final now = SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      final dt = (now - _lastAt) / 1e6;
      final moved = (p.pixels - _lastPixels).abs();
      // pixels a second, smoothed (one jump of the page is a spike, not a speed); a long pause says nothing about speed
      if (dt >= 0.25) {
        _speed = 0;
      } else if (dt > 0.001) {
        _speed = _speed * 0.5 + (moved / dt) * 0.5;
      }
      _lastPixels = p.pixels;
      _lastAt = now;
      // with some give, so the level does not flicker around the limit
      // a jump of more than a screen is too fast whatever the clock says (the scroll bar, a link in the contents)
      // and stays so for a moment, however small the little movements after it
      if (moved > p.viewportDimension) _fastUntil = now + 300000;
      _fast = _speed > widget.fastSpeed * (_fast ? 0.6 : 1) || now < _fastUntil;
    }
    if (!_moving) {
      _moving = true;
    }
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 100), _settle);
    RowBudget.lightOnScreen = _want == RowDetail.light;
    _schedule();
    _raise();
  }

  void _settle() {
    _moving = false;
    RowBudget.lightOnScreen = false;
    _fast = false;
    _speed = 0;
    _fastUntil = 0;
    _raise();
  }

  bool _raising = false;

  /// One row comes up a level (the nearest to the top of the screen first), then the next frame the next.
  void _raise() {
    if (_raising || !mounted) return;
    _raising = true;
    WidgetsBinding.instance.scheduleFrame(); // a post-frame callback waits for a frame; there may be none coming
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _raising = false;
      if (!mounted) return;
      final want = _want;
      final lower = [
        for (final e in _detail.entries)
          if (e.key >= _from && e.key < _to && _built.containsKey(e.key) && e.value.index < want.index) e.key,
      ];
      if (lower.isEmpty) return;
      lower.sort((a, b) => (a - _topRow).abs().compareTo((b - _topRow).abs()));
      final next = lower.first;
      // not both levels at once: a skeleton becomes light first
      setState(() {
        _built.remove(next);
        _detail.remove(next);
      });
      // on a device that could not keep up with the text, a row of paragraphs every frame would be a hitch every
      // frame: one in four
      if (RowBudget.textOk && !RowBudget.saving) {
        _raise();
        WidgetsBinding.instance.scheduleFrame();
      } else {
        Timer(const Duration(milliseconds: 64), _raise);
      }
    });
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _update();
    });
  }

  double _guess(int r) => widget.estimateFor?.call(r) ?? 28;

  double _h(int r) => _heights[r] ?? _guess(r);

  void _measured(int r, double h) {
    if (!_heights.containsKey(r) && r < _topRow) _shift += h - _guess(r);
    _heights[r] = h;
  }

  void _update() {
    final box = context.findRenderObject();
    final scrollable = _verticalScrollable();
    final viewport = scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || viewport is! RenderBox || !viewport.attached) return;
    final position = _position;
    if (_shift != 0 && position != null && position.hasPixels) {
      final by = _shift;
      _shift = 0;
      _correcting = true;
      position.jumpTo(position.pixels + by);
      _correcting = false;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final vTop = viewport.localToGlobal(Offset.zero).dy;
    final margin = viewport.size.height / 4;
    final lo = vTop - margin, hi = vTop + viewport.size.height + margin;
    var y = top, from = -1, to = -1, topRow = -1;
    for (var r = 0; r < widget.count; r++) {
      final h = _h(r);
      if (topRow < 0 && y + h > vTop) topRow = r;
      if (y + h >= lo && y <= hi) {
        from = from < 0 ? r : from;
        to = r + 1;
      }
      y += h;
      if (y > hi) break;
    }
    if (from < 0) from = to = 0;
    _topRow = topRow < 0 ? widget.count : topRow;
    if (from != _from || to != _to) {
      setState(() {
        _from = from;
        _to = to;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _from.clamp(0, widget.count), to = _to.clamp(from, widget.count);
    double sum(int a, int b) {
      var s = 0.0;
      for (var r = a; r < b; r++) {
        s += _h(r);
      }
      return s;
    }

    final rows = <Widget>[];
    final kept = widget.keep.where((r) => r >= 0 && r < widget.count && (r < from || r >= to)).toList()..sort();
    // the pinned rows before the window, the window, then the pinned rows after it, spacers in between
    var cursor = 0;
    void spacerUpTo(int r) {
      // keyed by where it ends, so a spacer is matched with itself and never with a row
      if (r > cursor) rows.add(SizedBox(key: ValueKey('gap$r'), height: sum(cursor, r)));
      cursor = r;
    }

    Widget row(int r) => _built[r] ??= () {
      // a row being edited or pinned is always the real thing
      final detail = widget.keep.contains(r) ? RowDetail.full : _want;
      _detail[r] = detail;
      // A key per row: when the window slides by a row the others keep their elements (they are moved, not rebuilt
      // with another row's text, which was every row of the window laid out again at every frame).
      return KeyedSubtree(key: ValueKey(r), child: _Measure(onHeight: detail == RowDetail.skeleton ? null : (h) => _measured(r, h), child: widget.rowBuilder(context, r, detail, _h(r))));
    }();
    for (final r in kept.where((r) => r < from)) {
      spacerUpTo(r);
      rows.add(row(r));
      cursor = r + 1;
    }
    spacerUpTo(from);
    for (var r = from; r < to; r++) {
      rows.add(row(r));
    }
    cursor = to;
    for (final r in kept.where((r) => r >= to)) {
      spacerUpTo(r);
      rows.add(row(r));
      cursor = r + 1;
    }
    spacerUpTo(widget.count);
    final live = {for (var r = from; r < to; r++) r, ...kept};
    _built.removeWhere((r, _) => !live.contains(r));
    _detail.removeWhere((r, _) => !live.contains(r));
    // the rows built now are measured after this frame, and the guesses for the others change with them:
    // look again (it stops as soon as the window is the same twice)
    _schedule();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// Reports its child's height after layout.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({required this.onHeight, required super.child});
  /// Null for a skeleton, whose height is the guess itself and says nothing about the row.
  final void Function(double height)? onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) => renderObject.onHeight = onHeight;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onHeight);
  void Function(double)? onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight?.call(size.height);
  }
}
