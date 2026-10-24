import 'dart:async';

const tapsToFire = 5;
const tapWindow = Duration(milliseconds: 1800);

enum TapResult { press, fire, ignored }

/// Counts taps on the logo: five in a row, each at most [window] after the previous one. The first four
/// only press the logo; the fifth fires. While a scene plays ([hold]) every tap is ignored.
class TapTrigger {
  TapTrigger({this.window = tapWindow});

  final Duration window;
  int _count = 0;
  Timer? _timer;
  bool _busy = false;

  int get taps => _count;

  TapResult tap() {
    if (_busy) return TapResult.ignored;
    _timer?.cancel();
    _count++;
    if (_count >= tapsToFire) {
      _count = 0;
      return TapResult.fire;
    }
    _timer = Timer(window, () => _count = 0);
    return TapResult.press;
  }

  /// Ignores taps for [duration] (the length of the scene).
  void hold(Duration duration) {
    _busy = true;
    _count = 0;
    _timer?.cancel();
    _timer = Timer(duration, () => _busy = false);
  }

  /// Cancels the hold and any pending count (scene cut short, widget gone).
  void release() {
    _busy = false;
    _count = 0;
    _timer?.cancel();
  }
}
