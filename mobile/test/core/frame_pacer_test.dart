// The frame limiter: when it holds a frame back, and when the monitor says a device is too slow for the full rate.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/performance/frame_pacer.dart';

void main() {
  setUp(FramePacer.reset);
  tearDown(FramePacer.reset);

  group('hold', () {
    test('does nothing while neither the setting nor the monitor asks for it', () {
      expect(FramePacer.hold(Duration.zero), isNull);
      expect(FramePacer.hold(const Duration(milliseconds: 5)), isNull);
    });

    test('with the setting on, a frame asked too soon waits for the 30 a second rhythm, a late one goes at once', () {
      FramePacer.mode.value = PowerMode.saving;
      final soon = FramePacer.hold(const Duration(milliseconds: 2))!;
      // 33.3 ms between frames, asked 8 ms early so the screen refresh after it is the right one
      expect(soon.inMilliseconds, inInclusiveRange(22, 24));
      expect(FramePacer.hold(const Duration(milliseconds: 30)), isNull, reason: 'less than the early margin is left');
      expect(FramePacer.hold(const Duration(seconds: 5)), isNull, reason: 'an idle app draws at once when something changes');
    });

    test('asks half a screen refresh early: 8 ms at 60 Hz, 3.5 ms at 144 Hz, and survives odd rates', () {
      FramePacer.mode.value = PowerMode.saving;
      expect(FramePacer.hold(Duration.zero, 60)!.inMicroseconds, closeTo(33333 - 8333, 2));
      expect(FramePacer.hold(Duration.zero, 144)!.inMicroseconds, closeTo(33333 - 3472, 2));
      for (final hz in [0.0, -5.0, double.nan, double.infinity, 1e9]) {
        expect(FramePacer.hold(Duration.zero, hz), isNotNull);
      }
    });

    test('the monitor turns it on too, in automatic', () {
      FramePacer.slow = true;
      expect(FramePacer.hold(Duration.zero), isNotNull);
    });

    test('"sempre fluido" ignores the monitor: a struggling device is never limited', () {
      FramePacer.mode.value = PowerMode.smooth;
      FramePacer.slow = true;
      expect(FramePacer.hold(Duration.zero), isNull);
      expect(FramePacer.saving, false);
    });

    test('economy limits whatever the monitor says', () {
      FramePacer.mode.value = PowerMode.saving;
      FramePacer.slow = false;
      expect(FramePacer.hold(Duration.zero), isNotNull);
      expect(FramePacer.saving, true);
    });

    test('the saved word comes back as the mode; anything else is automatic', () {
      for (final m in PowerMode.values) {
        expect(PowerMode.parse(m.name), m);
      }
      expect(PowerMode.parse(null), PowerMode.auto);
      expect(PowerMode.parse('30fps'), PowerMode.auto);
      expect(PowerMode.parse(''), PowerMode.auto);
    });
  });

  group('PaceMonitor', () {
    final t0 = DateTime(2026, 1, 1);

    PaceMonitor feed(double ms, int n, {double hz = 60, DateTime? at, PaceMonitor? into}) {
      final m = into ?? PaceMonitor();
      for (var i = 0; i < n; i++) {
        m.record(ms, hz, at ?? t0);
      }
      return m;
    }

    test('fast frames never turn it on, however many', () => expect(feed(6, 1000).slow, false));

    test('frames over the 60 Hz budget, most of the time, turn it on', () => expect(feed(22, 90).slow, true));

    test('a verdict needs a whole window of frames', () => expect(feed(40, 89).slow, false));

    test('a few hitches among good frames are not a verdict', () {
      final m = PaceMonitor();
      for (var i = 0; i < 300; i++) {
        m.record(i % 10 == 0 ? 80 : 7, 60, t0);
      }
      expect(m.slow, false);
    });

    test('a 120 Hz screen is judged against 60: a 12 ms frame is fine, 30 is only the fall-back', () => expect(feed(12, 200, hz: 120).slow, false));

    test('it gets another chance after a minute, then two: a busy phone is not condemned for good', () {
      final m = feed(25, 90);
      expect(m.slow, true);
      m.record(25, 60, t0.add(const Duration(seconds: 59)));
      expect(m.slow, true, reason: 'still waiting');
      m.record(25, 60, t0.add(const Duration(minutes: 1)));
      expect(m.slow, false, reason: 'tries the full rate again');
      final again = t0.add(const Duration(minutes: 1));
      feed(25, 90, at: again, into: m);
      expect(m.slow, true, reason: 'still late');
      m.record(25, 60, again.add(const Duration(seconds: 119)));
      expect(m.slow, true, reason: 'the second wait is longer');
      m.record(25, 60, again.add(const Duration(minutes: 2)));
      expect(m.slow, false);
    });

    test('a device that holds up when tried again forgets the failure', () {
      final m = feed(25, 90);
      m.record(5, 60, t0.add(const Duration(minutes: 1)));
      feed(5, 200, at: t0.add(const Duration(minutes: 1)), into: m);
      expect(m.slow, false);
      feed(25, 90, at: t0.add(const Duration(minutes: 2)), into: m);
      expect(m.slow, true);
      m.record(25, 60, t0.add(const Duration(minutes: 3)));
      expect(m.slow, false, reason: 'one minute again, not two');
    });

    test('odd readings (zero, negative, huge, a bad refresh rate) do not break it', () {
      final m = PaceMonitor();
      for (final v in [0.0, -3.0, 1e9, double.nan]) {
        m.record(v, 0, t0);
        m.record(v, 1000, t0);
      }
      expect(() => feed(10, 500, into: m), returnsNormally);
    });
  });
}
