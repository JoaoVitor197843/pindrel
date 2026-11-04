import 'dart:convert';
import 'dart:typed_data';

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
        '192.168.1', // incomplete
        '192.168.1.256',
        '192.168.1.-1',
        '192.168.01.5', // leading zero is ambiguous
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

  group('id do servidor', () {
    test('só texto curto e simples é um id', () {
      for (final ok in [
        'a',
        '0123456789abcdef0123456789abcdef',
        'Casa-2025',
        'x' * 64,
      ]) {
        expect(isValidServerId(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '',
        ' ',
        'a b',
        'a/b',
        'a\nb',
        'ü',
        'x' * 65,
        'a;b',
        '<b>',
      ]) {
        expect(isValidServerId(bad), isFalse, reason: bad);
      }
    });

    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

    test('a porta HTTPS do TXT do nsd: só portas válidas, o resto vira 0', () {
      expect(tlsPortFromTxt({'tls': bytes('8443')}), 8443);
      expect(tlsPortFromTxt({'id': bytes('abc'), 'tls': bytes('1024')}), 1024);
      for (final bad in ['80', '1023', '65536', '-1', 'abc', '', '84 43', '8443.0', '0', '123456']) {
        expect(tlsPortFromTxt({'tls': bytes(bad)}), 0, reason: bad);
      }
      expect(tlsPortFromTxt(null), 0);
      expect(tlsPortFromTxt({}), 0);
      expect(tlsPortFromTxt({'tls': null}), 0);
      expect(tlsPortFromTxt({'tls': bytes('9' * 5000)}), 0);
      expect(tlsPortFromTxt({'tls': Uint8List.fromList([0xff, 0xfe, 0x38])}), 0);
    });

    test('a porta HTTPS do texto do multicast_dns', () {
      expect(tlsPortFromTxtText('name=Casa\nid=abc\ntls=8443'), 8443);
      expect(tlsPortFromTxtText('tls=8443'), 8443);
      expect(tlsPortFromTxtText('name=Casa\nid=abc'), 0);
      expect(tlsPortFromTxtText(''), 0);
      for (final bad in ['tls=80', 'tls=', 'tls=abc', 'tls=999999', 'tls=${'9' * 500}', 'xtls=8443']) {
        expect(tlsPortFromTxtText(bad), 0, reason: bad);
      }
    });

    test('o servidor com HTTPS oferece o endereço seguro; sem HTTPS só o comum', () {
      const secure = DiscoveredServer(
        name: 'Casa',
        host: 'casa',
        addresses: ['192.168.1.10'],
        port: 8080,
        tlsPort: 8443,
      );
      expect(secure.secureUri.toString(), 'https://192.168.1.10:8443');
      expect(secure.baseUri.toString(), 'http://192.168.1.10:8080');
      const plain = DiscoveredServer(
        name: 'Casa',
        host: 'casa',
        addresses: ['192.168.1.10'],
        port: 8080,
      );
      expect(plain.secureUri, isNull);
      expect(plain.baseUri.toString(), 'http://192.168.1.10:8080');
      expect(secure == plain, isFalse, reason: 'a porta HTTPS conta na igualdade');
      expect(secure.hashCode == plain.hashCode, isFalse);
    });

    test('do TXT do nsd: o id válido passa, o resto vira vazio', () {
      expect(
        serverIdFromTxt({'id': bytes('abc-1'), 'name': bytes('Casa')}),
        'abc-1',
      );
      expect(serverIdFromTxt(null), '');
      expect(serverIdFromTxt({}), '');
      expect(serverIdFromTxt({'id': null}), '');
      expect(serverIdFromTxt({'id': bytes('com espaço')}), '');
      expect(serverIdFromTxt({'id': bytes('x' * 5000)}), '');
      expect(
        serverIdFromTxt({
          'id': Uint8List.fromList([0xff, 0xfe, 0x41]),
        }),
        '',
      );
    });

    test('do TXT do multicast_dns: procura a linha id= e valida', () {
      expect(serverIdFromTxtText('name=Casa\nid=abc123'), 'abc123');
      expect(serverIdFromTxtText('id=abc'), 'abc');
      expect(serverIdFromTxtText('name=Casa'), '');
      expect(serverIdFromTxtText(''), '');
      expect(serverIdFromTxtText('id='), '');
      expect(serverIdFromTxtText('xid=abc'), '');
      expect(serverIdFromTxtText('id=a b'), '');
      expect(serverIdFromTxtText('id=${'a' * 100_000}'), '');
    });

    test('o id entra na igualdade: outro id é outro servidor', () {
      expect(server('A', id: 'x'), server('A', id: 'x'));
      expect(server('A', id: 'x'), isNot(server('A', id: 'y')));
      expect(server('A', id: 'x'), isNot(server('A')));
    });
  });
}
