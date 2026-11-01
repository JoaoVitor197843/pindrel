/// When a discovery should restart its search, and when a failure is worth showing.
///
/// Wi-Fi drops multicast packets and the system's own retries grow further and
/// further apart, so a search that finds nothing is restarted. Restarting forever
/// at a fixed pace would wake a phone every few seconds on a network that simply has no
/// server, so the wait doubles after every restart ([base], 2x, 4x...) up to
/// [max]; finding a server, or the app coming back to the foreground, starts over.
///
/// Both discoveries (nsd and Linux mDNS) share it, so the rule lives in one place.
class RestartPolicy {
  RestartPolicy({
    this.base = const Duration(seconds: 15),
    this.max = const Duration(minutes: 5),
    this.errorThreshold = 3,
  });

  final Duration base;
  final Duration max;

  /// How many failures in a row before a restart error is reported.
  final int errorThreshold;

  int _restarts = 0;
  int _failures = 0;

  /// How long to wait before the next restart.
  Duration get delay {
    var d = base;
    for (var i = 0; i < _restarts && d < max; i++) {
      d *= 2;
    }
    return d < max ? d : max;
  }

  /// A restart was made: the next wait is longer.
  void restarted() => _restarts++;

  /// Something was found, or the app came back: the wait starts over.
  void reset() {
    _restarts = 0;
    _failures = 0;
  }

  /// The search started: failures in a row are forgotten.
  void succeeded() => _failures = 0;

  /// A start failed. Returns whether the error should reach the user: right away when
  /// [surfaceNow] (the very first start, where a missing permission is a real answer),
  /// otherwise only after [errorThreshold] failures in a row, once, so a hiccup of
  /// a restart does not flash an error that the next try would fix.
  bool failed({bool surfaceNow = false}) {
    _failures++;
    return surfaceNow || _failures == errorThreshold;
  }
}
