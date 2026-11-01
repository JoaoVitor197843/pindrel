import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/mdns_discovery.dart';
import 'package:mobile/core/network/discovery/nsd_discovery.dart';
import 'package:mobile/core/network/discovery/platform_discovery.dart';
import 'package:mobile/core/network/discovery/server_discovery.dart';

void main() {
  test('cada sistema usa a descoberta que funciona nele', () {
    final discovery = createPlatformDiscovery();
    if (Platform.isLinux || Platform.isWindows) {
      expect(
        discovery,
        isA<MdnsDiscovery>(),
        reason:
            'o plugin nsd não existe no Linux e perde mensagens no Windows '
            '(envia da thread errada)',
      );
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      expect(discovery, isA<NsdDiscovery>());
    }
  });

  test('NoDiscovery emite uma lista vazia e termina', () async {
    expect(await const NoDiscovery().watch().toList(), [isEmpty]);
  });
}
