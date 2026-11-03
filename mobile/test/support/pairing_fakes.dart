import 'dart:async';
import 'dart:math';

import 'package:mobile/core/network/pairing.dart';

/// A pairing function that behaves like [pairWithDigits] without a network: each call is a new session with the next digits,
/// the person's answer decides, and not answering in [confirmTimeout] expires the digits.
class FakePairer {
  FakePairer(this.digits, {this.result, this.name = 'Casa', this.validRoom = '4821'});
  final List<String> digits;
  final String name;
  final PairingResult? result;

  /// The only room that exists: any other is answered as the server would (`badRoom`).
  final String validRoom;
  int calls = 0;
  final shown = <String>[];

  /// The room each call asked for.
  final rooms = <String>[];

  Future<PairingResult> call({
    required String host,
    required int port,
    required String room,
    required PairedStore store,
    required Future<bool> Function(SasPrompt prompt) confirm,
    Duration timeout = pairingTimeout,
    Duration confirmTimeout = sasConfirmTimeout,
    Random? random,
    String serverId = '',
  }) async {
    rooms.add(room);
    if (room != validRoom) {
      calls++;
      return const PairingFailed(PairingFailure.badRoom);
    }
    final d = digits[calls++ % digits.length];
    shown.add(d);
    if (result != null) return result!;
    bool same;
    var expired = false;
    try {
      same = await confirm(SasPrompt(digits: d, name: name, hostPort: '$host:$port', expiresAt: DateTime.now().add(confirmTimeout))).timeout(confirmTimeout);
    } on TimeoutException {
      same = false;
      expired = true;
    }
    if (!same) return PairingFailed(expired ? PairingFailure.expired : PairingFailure.declined);
    return Paired(PairedServer(hostPort: '$host:$port', fingerprint: 'f' * 64, caPem: 'x', name: name, serverId: serverId));
  }
}

/// A master pairing that behaves like [pairWithMaster] without a network: it accepts one code (as the log would show it).
class FakeMasterPairer {
  FakeMasterPairer({this.accepts = '0410-6105-0R3G-G28A', this.name = 'Casa', this.result});
  final String accepts;
  final String name;
  final PairingResult? result;
  final tried = <String>[];

  Future<PairingResult> call({
    required String host,
    required int port,
    required String master,
    required PairedStore store,
    Duration timeout = pairingTimeout,
    Random? random,
    String serverId = '',
  }) async {
    tried.add(master);
    if (result != null) return result!;
    if (parseMasterCode(master) == null || !_same(parseMasterCode(master)!, parseMasterCode(accepts)!)) {
      return const PairingFailed(PairingFailure.badCode);
    }
    final server = PairedServer(hostPort: '$host:$port', fingerprint: 'f' * 64, caPem: 'x', name: name, serverId: serverId);
    await store.save(server);
    return Paired(server);
  }

  static bool _same(List<int> a, List<int> b) => a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
}
