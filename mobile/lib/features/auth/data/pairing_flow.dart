import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/pairing.dart';
import '../../../core/network/server_security.dart';

/// Where the screen is in pairing with one server by six digits.
enum FlowPhase {
  /// Asking the server where its HTTPS is.
  looking,

  /// The server offers no HTTPS: nothing to pair with. The person may use it without encryption, or give up.
  noTls,

  /// The digits are on screen, waiting for the person.
  showing,

  /// The digits expired (the server drops them after a minute): new ones are being asked for.
  renewing,

  paired,
  failed,
  cancelled,
}

/// How the person answers: compares the numbers of the two screens and taps, or types the numbers the server shows, or has
/// the master code of the server's log (nothing to compare: the app and the server prove the code to each other).
enum FlowMode { compare, type, master }

class PairingFlowState {
  const PairingFlowState({
    this.phase = FlowPhase.looking,
    this.prompt,
    this.failure,
    this.paired,
    this.serverId = '',
    this.round = 1,
    this.wrongTries = 0,
    this.tlsPort,
  });

  final FlowPhase phase;

  /// The digits to show (phase `showing`).
  final SasPrompt? prompt;
  final PairingFailure? failure;
  final PairedServer? paired;
  final String serverId;

  /// Which set of digits this is: it grows every time they expire.
  final int round;

  /// Numbers typed that did not match (mode `type`).
  final int wrongTries;
  final int? tlsPort;

  PairingFlowState copy({
    FlowPhase? phase,
    SasPrompt? prompt,
    PairingFailure? failure,
    PairedServer? paired,
    String? serverId,
    int? round,
    int? wrongTries,
    int? tlsPort,
    bool clearPrompt = false,
  }) => PairingFlowState(
    phase: phase ?? this.phase,
    prompt: clearPrompt ? null : prompt ?? this.prompt,
    failure: failure ?? this.failure,
    paired: paired ?? this.paired,
    serverId: serverId ?? this.serverId,
    round: round ?? this.round,
    wrongTries: wrongTries ?? this.wrongTries,
    tlsPort: tlsPort ?? this.tlsPort,
  );
}

/// Pairs with one server by six digits, as many times as it takes while the screen stays open.
///
/// Each set of digits is a session of the protocol (see `pairWithDigits`): it lives one minute and answers once. When it
/// expires, or the person types it wrong, a new session with new digits starts; nothing from an old one is reused. The
/// person's answer is [confirmSame]/[reject] in mode [FlowMode.compare], or [submit] with the digits the server shows in
/// mode [FlowMode.type].
class PairingFlow extends ChangeNotifier {
  PairingFlow({
    required this.base,
    required this.mode,
    required this.store,
    required this.pairer,
    required this.offerFor,
    this.room = '',
    this.master = '',
    this.masterPairer = pairWithMaster,
    this.maxRounds = 10,
    this.maxWrongTries = 3,
    this.timeout = pairingTimeout,
    this.confirmTimeout = sasConfirmTimeout,
  });

  /// The server as the person reached it: `http://ip:port` (announced, or typed) or an explicit `https://...`.
  final Uri base;
  final FlowMode mode;
  final PairedStore store;
  final DigitsPairer pairer;
  final Future<TlsOffer?> Function(Uri base) offerFor;

  /// The code of the room the person opened on a page of the server (modes `compare` and `type`).
  final String room;

  /// The master code from the server's log (mode `master`).
  final String master;
  final MasterPairer masterPairer;

  /// Sets of digits asked for before giving up (a forgotten screen does not ask forever).
  final int maxRounds;

  /// Wrong numbers typed before the session is dropped (mode `type`).
  final int maxWrongTries;
  final Duration timeout;
  final Duration confirmTimeout;

  PairingFlowState _state = const PairingFlowState();
  PairingFlowState get state => _state;

  Completer<bool>? _answer;
  bool _stopped = false;
  bool _started = false;

  void _set(PairingFlowState s) {
    if (_stopped && s.phase != FlowPhase.cancelled) return;
    _state = s;
    notifyListeners();
  }

  /// Looks for the HTTPS side and starts the first set of digits. Safe to call once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final TlsOffer? offer;
    if (base.scheme == 'https') {
      offer = TlsOffer(port: base.port);
    } else {
      offer = await offerFor(base);
    }
    if (_stopped) return;
    if (offer == null) {
      _set(_state.copy(phase: FlowPhase.noTls));
      return;
    }
    _set(_state.copy(tlsPort: offer.port, serverId: offer.serverId));
    if (mode == FlowMode.master) {
      final result = await masterPairer(
        host: base.host,
        port: offer.port,
        master: master,
        store: store,
        serverId: offer.serverId,
        timeout: timeout,
      );
      if (_stopped) return;
      switch (result) {
        case Paired(:final server):
          _set(_state.copy(phase: FlowPhase.paired, paired: server, clearPrompt: true));
        case PairingFailed(:final reason):
          _set(_state.copy(phase: FlowPhase.failed, failure: reason, clearPrompt: true));
      }
      return;
    }
    for (var round = 1; round <= maxRounds && !_stopped; round++) {
      _set(_state.copy(round: round, clearPrompt: true, phase: round == 1 ? FlowPhase.looking : FlowPhase.renewing));
      final result = await pairer(
        host: base.host,
        port: offer.port,
        room: room,
        store: store,
        serverId: offer.serverId,
        timeout: timeout,
        confirmTimeout: confirmTimeout,
        confirm: _ask,
      );
      if (_stopped) return;
      switch (result) {
        case Paired(:final server):
          _set(_state.copy(phase: FlowPhase.paired, paired: server, clearPrompt: true));
          return;
        case PairingFailed(:final reason) when reason == PairingFailure.expired:
          continue; // new digits, new session
        case PairingFailed(:final reason):
          _set(_state.copy(phase: FlowPhase.failed, failure: reason, clearPrompt: true));
          return;
      }
    }
    if (!_stopped) _set(_state.copy(phase: FlowPhase.failed, failure: PairingFailure.expired, clearPrompt: true));
  }

  Future<bool> _ask(SasPrompt prompt) {
    final answer = Completer<bool>();
    _answer = answer;
    _set(_state.copy(phase: FlowPhase.showing, prompt: prompt, wrongTries: 0));
    return answer.future;
  }

  /// Mode `compare`: the numbers are the same on both screens.
  void confirmSame() {
    if (mode == FlowMode.compare) _finish(true);
  }

  /// The numbers are different, or the person changed their mind: nothing is kept.
  void reject() => _finish(false);

  /// Mode `type`: the person typed what the server shows. Returns whether it matched. A wrong number is counted, and after
  /// [maxWrongTries] the session is dropped.
  bool submit(String typed) {
    final prompt = _state.prompt;
    if (mode != FlowMode.type || prompt == null || _state.phase != FlowPhase.showing) return false;
    final digits = typed.replaceAll(RegExp(r'\s'), '');
    if (digits == prompt.digits) {
      _finish(true);
      return true;
    }
    final wrong = _state.wrongTries + 1;
    if (wrong >= maxWrongTries) {
      _finish(false);
    } else {
      _set(_state.copy(wrongTries: wrong));
    }
    return false;
  }

  void _finish(bool same) {
    final answer = _answer;
    _answer = null;
    if (answer != null && !answer.isCompleted) answer.complete(same);
  }

  /// The person closed the screen: whatever is waiting is dropped and nothing is kept.
  void cancel() {
    if (_stopped) return;
    _stopped = true;
    _finish(false);
    _set(_state.copy(phase: FlowPhase.cancelled, clearPrompt: true));
  }

  @override
  void dispose() {
    _stopped = true;
    _finish(false);
    super.dispose();
  }
}
