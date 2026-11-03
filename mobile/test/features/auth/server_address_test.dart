import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/data/server_address.dart';

void main() {
  test('endereços comuns', () {
    expect(parseServerAddress('192.168.1.5:8086').toString(), 'http://192.168.1.5:8086');
    expect(parseServerAddress('  casa.lan  ')?.port, 80, reason: 'spaces around are the person\'s, not part of the address');
    expect(parseServerAddress('CASA.LAN:8080/').toString(), 'http://casa.lan:8080');
    expect(parseServerAddress('http://10.0.0.2:8086').toString(), 'http://10.0.0.2:8086');
    expect(parseServerAddress('https://192.168.1.5:8443').toString(), 'https://192.168.1.5:8443');
    expect(parseServerAddress('https://casa.lan')?.port, 443);
    expect(parseServerAddress('[fe80::1]:8086')?.host, 'fe80::1');
    expect(parseServerAddress('meu-servidor:9000')?.port, 9000);
  });

  test('o que não é um endereço é recusado, sem exceção', () {
    for (final bad in [
      '',
      '   ',
      'http://',
      'https://:8443',
      ':8080',
      '192.168.1.5:0',
      '192.168.1.5:65536',
      '192.168.1.5:-1',
      '192.168.1.5:abc',
      '192.168.1.5:99999999999999999999',
      '999.1.1.1',
      '1.2.3',
      '1.2.3.4.5',
      'a b',
      'casa lan:8080',
      'user@casa.lan',
      'http://user:pass@casa.lan',
      'casa.lan/path',
      'casa.lan:8080/api',
      'casa.lan?x=1',
      'casa.lan#frag',
      'ftp://casa.lan',
      'javascript:alert(1)',
      '-casa.lan',
      'casa-.lan',
      'casa..lan',
      '.lan',
      '[1.2.3.4]:80',
      '[::1',
      '::1',
      '${'a' * 300}.lan',
      'casa.lan\nx',
      'http://casa.lan:80:90',
    ]) {
      expect(parseServerAddress(bad), isNull, reason: bad);
    }
  });

  test('texto aleatório e enorme não quebra', () {
    for (var i = 0; i < 300; i++) {
      final s = String.fromCharCodes(List.generate(i % 40, (j) => (i * 31 + j * 17) % 128));
      parseServerAddress(s);
    }
    expect(parseServerAddress('a' * 100000), isNull);
  });
}
