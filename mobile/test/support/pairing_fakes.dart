import 'dart:async';
import 'dart:math';

import 'package:mobile/core/network/pairing.dart';

/// A pairing function that behaves like [pairWithDigits] without a network: each call is a new session with the next digits,
/// the person's answer decides, and not answering in [confirmTimeout] expires the digits.
class FakePairer {
  FakePairer(this.digits, {this.result, this.name = 'Casa', this.yourAddress = '192.168.1.77'});
  final String yourAddress;
  final List<String> digits;
  final String name;
  final PairingResult? result;
  int calls = 0;
  final shown = <String>[];

  Future<PairingResult> call({
    required String host,
    required int port,
    required PairedStore store,
    required Future<bool> Function(SasPrompt prompt) confirm,
    Duration timeout = pairingTimeout,
    Duration confirmTimeout = sasConfirmTimeout,
    Random? random,
    String serverId = '',
  }) async {
    final d = digits[calls++ % digits.length];
    shown.add(d);
    if (result != null) return result!;
    bool same;
    var expired = false;
    try {
      same = await confirm(SasPrompt(digits: d, name: name, hostPort: '$host:$port', yourAddress: yourAddress, expiresAt: DateTime.now().add(confirmTimeout))).timeout(confirmTimeout);
    } on TimeoutException {
      same = false;
      expired = true;
    }
    if (!same) return PairingFailed(expired ? PairingFailure.expired : PairingFailure.declined);
    return Paired(PairedServer(hostPort: '$host:$port', fingerprint: 'f' * 64, caPem: 'x', name: name, serverId: serverId));
  }
}
