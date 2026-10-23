import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/discovered_server.dart';

import '../../../support/discovery_fakes.dart';

void main() {
  group('DiscoveredServer', () {
    test('conecta pelo primeiro IPv4; sem IP, pelo nome mDNS da máquina', () {
      final withIp = server(
        'A',
        host: 'a',
        addresses: ['192.168.1.5', '10.0.0.2'],
        port: 8095,
      );
      expect(withIp.address, '192.168.1.5');
      expect(withIp.baseUri, Uri.parse('http://192.168.1.5:8095'));

      final byName = server('B', host: 'raspberry-joao');
      expect(byName.address, 'raspberry-joao.local');
      expect(byName.baseUri.toString(), 'http://raspberry-joao.local:8080');

      expect(server('C').address, isEmpty);
    });

    test('igualdade considera todos os campos', () {
      final a = server('A', host: 'h', addresses: ['10.0.0.1'], port: 80);
      expect(a, server('A', host: 'h', addresses: ['10.0.0.1'], port: 80));
      expect(
        a.hashCode,
        server('A', host: 'h', addresses: ['10.0.0.1'], port: 80).hashCode,
      );
      expect(
        a == server('A', host: 'h', addresses: ['10.0.0.2'], port: 80),
        isFalse,
      );
      expect(
        a == server('A', host: 'h', addresses: ['10.0.0.1'], port: 81),
        isFalse,
      );
      expect(
        a == server('B', host: 'h', addresses: ['10.0.0.1'], port: 80),
        isFalse,
      );
    });
  });

  group('isUsableIpv4', () {
    test('aceita IPv4 comuns de rede local', () {
      for (final ip in ['192.168.1.116', '10.0.0.1', '172.19.0.1', '8.8.8.8']) {
        expect(isUsableIpv4(ip), isTrue, reason: ip);
      }
    });

    test('recusa o que não leva a um servidor da rede', () {
      for (final ip in [
        '127.0.0.1', // loopback
        '169.254.10.20', // link-local
        '0.0.0.0',
        '224.0.0.251', // multicast
        '255.255.255.255',
        'fe80::1', // IPv6
        '::1',
        '192.168.1', // incompleto
        '192.168.1.256',
        '192.168.1.-1',
        '192.168.01.5', // zero à esquerda é ambíguo
        'a.b.c.d',
        '',
        '1.2.3.4.5',
      ]) {
        expect(isUsableIpv4(ip), isFalse, reason: ip);
      }
    });

    test('usableIpv4 tira repetidos e inválidos e ordena', () {
      expect(
        usableIpv4([
          '192.168.1.9',
          'fe80::1',
          '10.0.0.2',
          '192.168.1.9',
          '127.0.0.1',
        ]),
        ['10.0.0.2', '192.168.1.9'],
      );
    });
  });
}
