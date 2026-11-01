import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/discovery/mdns_discovery.dart';

({String name, List<InternetAddress> addresses}) nic(
  String name,
  List<String> ips,
) => (name: name, addresses: [for (final ip in ips) InternetAddress(ip)]);

void main() {
  group('keepJoinable (interfaces que aceitam o grupo mDNS)', () {
    test('tira as que recusam e mantém a ordem', () async {
      final kept = await keepJoinable([
        'Wi-Fi',
        'Tailscale',
        'Ethernet',
      ], (name) async => name != 'Tailscale');
      expect(kept, ['Wi-Fi', 'Ethernet']);
    });

    test(
      'se todas recusam, devolve todas: o erro de verdade aparece',
      () async {
        final kept = await keepJoinable(['a', 'b'], (_) async => false);
        expect(kept, ['a', 'b']);
      },
    );

    test('se todas aceitam, devolve todas', () async {
      expect(await keepJoinable([1, 2, 3], (_) async => true), [1, 2, 3]);
    });

    test('sem interfaces nenhuma, devolve vazio sem quebrar', () async {
      expect(await keepJoinable(<String>[], (_) async => true), isEmpty);
    });

    test('pergunta uma interface por vez, nunca duas ao mesmo tempo', () async {
      var running = 0;
      var maxRunning = 0;
      await keepJoinable(List.generate(8, (i) => i), (_) async {
        running++;
        if (running > maxRunning) maxRunning = running;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        running--;
        return true;
      });
      expect(maxRunning, 1);
    });

    test('um erro inesperado do teste não é engolido', () async {
      expect(
        keepJoinable(['a'], (_) async => throw StateError('boom')),
        throwsStateError,
      );
    });
  });

  group('pickLanAddress (por onde saem as perguntas no Windows)', () {
    String? pick(List<({String name, List<InternetAddress> addresses})> n) =>
        pickLanAddress(n)?.address;

    test('192.168 vem antes de 10, que vem antes de 172.16/12', () {
      expect(
        pick([
          nic('Ethernet', ['172.20.0.5']),
          nic('Ethernet 2', ['10.0.0.8']),
          nic('Wi-Fi', ['192.168.1.20']),
        ]),
        '192.168.1.20',
      );
      expect(
        pick([
          nic('Ethernet', ['172.20.0.5']),
          nic('Wi-Fi', ['10.0.0.8']),
        ]),
        '10.0.0.8',
      );
    });

    test('a ordem das interfaces não muda o resultado', () {
      final a = nic('Wi-Fi', ['192.168.1.20']);
      final b = nic('Ethernet', ['10.0.0.8']);
      final c = nic('Outra', ['172.20.0.5']);
      for (final order in [
        [a, b, c],
        [c, b, a],
        [b, a, c],
        [c, a, b],
      ]) {
        expect(pick(order), '192.168.1.20');
      }
    });

    test('Tailscale, link-local, públicos, loopback e IPv6 não servem', () {
      expect(
        pick([
          nic('Tailscale', ['100.64.0.1', '100.107.201.60']),
          nic('Auto', ['169.254.10.5']),
          nic('Publico', ['8.8.8.8', '172.32.0.1', '172.15.0.1']),
          nic('Loopback', ['127.0.0.1']),
          nic('V6', ['fe80::1', '::1', 'fd00::5']),
        ]),
        isNull,
      );
    });

    test('os limites do 172.16/12: 16 a 31 entram, 15 e 32 não', () {
      expect(
        pick([
          nic('a', ['172.16.0.1']),
        ]),
        '172.16.0.1',
      );
      expect(
        pick([
          nic('a', ['172.31.255.1']),
        ]),
        '172.31.255.1',
      );
      expect(
        pick([
          nic('a', ['172.15.255.1']),
        ]),
        isNull,
      );
      expect(
        pick([
          nic('a', ['172.32.0.1']),
        ]),
        isNull,
      );
    });

    test('um adaptador físico vence um virtual, mesmo com faixa pior', () {
      expect(
        pick([
          nic('vEthernet (WSL)', ['192.168.50.1']),
          nic('Ethernet', ['172.20.0.5']),
        ]),
        '172.20.0.5',
      );
    });

    test('nomes de adaptadores virtuais comuns perdem para o Wi-Fi', () {
      for (final virtual in [
        'vEthernet (WSL)',
        'vEthernet (Default Switch)',
        'docker0',
        'br-1a2b3c4d',
        'veth9f8e7d',
        'VirtualBox Host-Only Network',
        'VMware Network Adapter VMnet8',
        'Hyper-V Virtual Ethernet Adapter',
      ]) {
        expect(
          pick([
            nic(virtual, ['192.168.99.1']),
            nic('Wi-Fi', ['192.168.1.20']),
          ]),
          '192.168.1.20',
          reason: virtual,
        );
      }
    });

    test('nomes de adaptadores reais não são tomados por virtuais', () {
      for (final real in [
        'Wi-Fi',
        'Ethernet',
        'Ethernet 3',
        'wlan0',
        'eth0',
        'enp64s0',
        'wlp63s0',
      ]) {
        expect(
          pick([
            nic('docker0', ['192.168.99.1']),
            nic(real, ['172.20.0.5']),
          ]),
          '172.20.0.5',
          reason: real,
        );
      }
    });

    test('só há virtuais: usa o melhor deles em vez de desistir', () {
      expect(
        pick([
          nic('docker0', ['172.17.0.1']),
          nic('vEthernet (WSL)', ['192.168.50.1']),
        ]),
        '192.168.50.1',
      );
    });

    test('empate: vale o primeiro da lista', () {
      expect(
        pick([
          nic('Wi-Fi', ['192.168.1.20']),
          nic('Ethernet', ['192.168.7.9']),
        ]),
        '192.168.1.20',
      );
    });

    test('vários endereços na mesma interface: o melhor deles', () {
      expect(
        pick([
          nic('Wi-Fi', ['10.0.0.8', '192.168.1.20']),
        ]),
        '192.168.1.20',
      );
    });

    test('sem interfaces, ou interface sem endereço: nulo', () {
      expect(pick([]), isNull);
      expect(pick([nic('Wi-Fi', [])]), isNull);
    });
  });

  group('askUpTo (cada pergunta é feita até 3 vezes)', () {
    test('para na primeira resposta e não pergunta de novo', () async {
      var calls = 0;
      final result = await askUpTo<int>((_) async {
        calls++;
        return [1];
      }, const Duration(seconds: 3));
      expect(result, [1]);
      expect(calls, 1);
    });

    test(
      'tenta de novo quando a resposta vem vazia (pacote perdido)',
      () async {
        var calls = 0;
        final result = await askUpTo<String>((_) async {
          calls++;
          return calls < 3 ? <String>[] : ['achou'];
        }, const Duration(seconds: 3));
        expect(result, ['achou']);
        expect(calls, 3);
      },
    );

    test('desiste depois de 3 tentativas e devolve vazio', () async {
      var calls = 0;
      final result = await askUpTo<int>((_) async {
        calls++;
        return <int>[];
      }, const Duration(seconds: 3));
      expect(result, isEmpty);
      expect(calls, 3);
    });

    test('divide o tempo: cada pergunta recebe um terço', () async {
      final slices = <Duration>[];
      await askUpTo<int>((slice) async {
        slices.add(slice);
        return <int>[];
      }, const Duration(seconds: 3));
      expect(slices, everyElement(const Duration(seconds: 1)));
      expect(slices, hasLength(3));
    });

    test('o número de tentativas é ajustável', () async {
      var calls = 0;
      await askUpTo<int>(
        (_) async {
          calls++;
          return <int>[];
        },
        const Duration(seconds: 4),
        asks: 1,
      );
      expect(calls, 1);
    });

    test('um erro da pergunta passa adiante, sem tentar de novo', () async {
      var calls = 0;
      await expectLater(
        askUpTo<int>((_) async {
          calls++;
          throw const SocketException('rede caiu');
        }, const Duration(seconds: 3)),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 1);
    });
  });
}
