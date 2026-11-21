import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Decides when the app may draw 60 (or 120) frames a second and when it should settle for a steady 30.
///
/// Why 30 and not "as many as it can": on a phone that needs 20-25 ms for a frame, asking for 60 makes the frames
/// uneven and keeps the CPU/GPU busy all the time (heat, battery). Not asking for the frames in between costs nothing
/// at all: no build, no layout, no raster, no composition by the system.
///
/// Two things turn it on: the person's "Energia" setting ("Economia"; "Sempre fluido" turns the limiter off for good), and a device that is seen to be late
/// ([PaceMonitor]). The limiter itself is [PacedFrames], a mixin of the binding that delays the request for a frame.
/// Configurações > Energia.
enum PowerMode {
  /// Full rate; 30 only while the device is seen to be late ([PaceMonitor]).
  auto,

  /// Never limited, even when the device struggles.
  smooth,

  /// Always 30, no decorative motion, table rows as bars while scrolling.
  saving;

  static PowerMode parse(String? v) => PowerMode.values.where((m) => m.name == v).firstOrNull ?? PowerMode.auto;
}

class FramePacer {
  FramePacer._();

  /// The person's setting.
  static final ValueNotifier<PowerMode> mode = ValueNotifier(PowerMode.auto);

  static bool get saving => mode.value == PowerMode.saving;

  /// Set by [PaceMonitor] when the device cannot keep up with the full rate.
  static bool slow = false;

  /// Frames are limited to this many a second while [active].
  static const int pacedFps = 30;

  static bool get active => saving || (slow && mode.value == PowerMode.auto);

  static Duration get interval => Duration(microseconds: 1000000 ~/ pacedFps);

  /// A frame asked for [sinceLast] after the previous one starts at the next screen refresh after the request.
  /// Asking half a refresh early makes that refresh the second one after the last frame, not the third
  /// (8 ms on a 60 Hz screen, 3.5 ms on a 144 Hz one: a fixed 8 ms let a frame through every ~28 ms there).
  static Duration _early(double hz) => Duration(microseconds: (500000 / (hz.isFinite ? hz.clamp(30, 240) : 60)).round());

  /// How long to hold a request for a frame, or null to let it through now. [hz] is the screen's refresh rate.
  static Duration? hold(Duration sinceLast, [double hz = 60]) {
    if (!active) return null;
    final wait = interval - sinceLast - _early(hz);
    return wait > Duration.zero ? wait : null;
  }

  static PaceMonitor? _monitor;

  /// Starts watching the frames of the real app (not called in tests, which have no real frames).
  static void watch() {
    if (_monitor != null) return;
    final m = _monitor = PaceMonitor();
    SchedulerBinding.instance.addTimingsCallback((timings) {
      final hz = PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate ?? 60;
      for (final t in timings) {
        // the two threads run side by side: a frame is late when the slower one is
        final ms = (t.buildDuration > t.rasterDuration ? t.buildDuration : t.rasterDuration).inMicroseconds / 1000;
        m.record(ms, hz, DateTime.now());
      }
      slow = m.slow;
    });
  }

  @visibleForTesting
  static void reset() {
    mode.value = PowerMode.auto;
    slow = false;
    _monitor = null;
  }
}

/// Reads the cost of the frames and says when the device is too slow for the full rate.
///
/// Only frames of a busy screen reach it (an idle app draws none), so "late" is judged on what the person sees:
/// scrolling, typing, animations. A verdict needs many frames: a hitch (garbage collection, a page opening) counts for
/// no more than two frames' worth, like [RowBudget]. The device is given another chance after a wait that doubles each
/// time it fails (1 min up to 16 min): a phone that was busy with something else is not condemned for good.
class PaceMonitor {
  PaceMonitor({this.window = 90, this.lateShare = 0.4});

  final int window;
  final double lateShare;

  bool slow = false;
  int _seen = 0, _late = 0;
  DateTime? _retryAt;
  Duration _wait = const Duration(minutes: 1);

  /// One frame that took [ms] (the slower thread) on a screen of [hz] Hz, seen at [now].
  void record(double ms, double hz, DateTime now) {
    if (slow) {
      // at 30 a second frames cost what they cost: nothing to learn. Only the clock decides.
      if (_retryAt != null && !now.isBefore(_retryAt!)) {
        slow = false;
        _seen = 0;
        _late = 0;
      }
      return;
    }
    final budget = 1000 / (hz < 30 ? 60 : (hz > 60 ? 60 : hz)); // 120 Hz screens are judged against 60: 30 is what we fall to
    final capped = ms < budget * 2 ? ms : budget * 2;
    _seen++;
    if (capped > budget * 0.9) _late++;
    if (_seen < window) return;
    if (_late / _seen >= lateShare) {
      slow = true;
      _retryAt = now.add(_wait);
      _wait = _wait * 2 > const Duration(minutes: 16) ? const Duration(minutes: 16) : _wait * 2;
    } else {
      _wait = const Duration(minutes: 1); // it holds the full rate: forget earlier failures
    }
    _seen = 0;
    _late = 0;
  }
}

/// The binding's side: delays the request for the next frame while [FramePacer.active].
mixin PacedFrames on SchedulerBinding {
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastFrame = Duration.zero;
  Timer? _held;

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _lastFrame = _clock.elapsed;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void scheduleFrame() {
    if (_held != null) return; // already waiting: one request is enough
    final hz = PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate ?? 60;
    final wait = FramePacer.hold(_clock.elapsed - _lastFrame, hz);
    if (wait == null) {
      super.scheduleFrame();
      return;
    }
    _held = Timer(wait, () {
      _held = null;
      super.scheduleFrame();
    });
  }
}

/// The same bindings as `WidgetsFlutterBinding`, plus [PacedFrames].
class PindrelBinding extends BindingBase with GestureBinding, SchedulerBinding, ServicesBinding, PaintingBinding, SemanticsBinding, RendererBinding, WidgetsBinding, PacedFrames {
  /// Does nothing when another binding already owns the app (the integration test's, which `main()` is called under).
  static void ensureInitialized() {
    if (_instance != null) return;
    try {
      WidgetsBinding.instance;
      return;
    } catch (_) {
      // none yet: ours is the one
    }
    PindrelBinding();
  }

  PindrelBinding() {
    _instance = this;
  }

  static PindrelBinding? _instance;
}
