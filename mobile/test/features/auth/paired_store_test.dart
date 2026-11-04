import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/pairing.dart';
import 'package:mobile/core/network/server_security.dart';
import 'package:mobile/features/auth/data/secure_paired_store.dart';
import 'package:mobile/features/auth/data/server_trust.dart';

String fixture(String name) => File('test/fixtures/pairing/$name').readAsStringSync();

PairedServer paired(String hostPort, {String name = 'Casa', String id = 'abc', String ca = 'good'}) {
  final pem = fixture('$ca-ca.pem');
  return PairedServer(hostPort: hostPort, fingerprint: fingerprintOfPem(pem), caPem: pem, name: name, serverId: id);
}

class ThrowingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('no keyring');

  @override
  Future<void> write(String key, String value) async => throw StateError('no keyring');
}

void main() {
  group('SecurePairedStore', () {
    late MemoryKeyValueStore raw;
    late SecurePairedStore store;
    setUp(() {
      raw = MemoryKeyValueStore();
      store = SecurePairedStore(raw);
    });

    test('guarda, acha, lista e esquece', () async {
      expect(await store.all(), isEmpty);
      await store.save(paired('10.0.0.1:8443'));
      await store.save(paired('10.0.0.2:8443', name: 'Nuvem'));
      expect((await store.find('10.0.0.1:8443'))!.name, 'Casa');
      expect((await store.find('10.0.0.1:8443'))!.serverId, 'abc');
      expect(await store.find('10.0.0.9:8443'), isNull);
      expect((await store.all()).map((p) => p.name), ['Casa', 'Nuvem']);
      await store.forget('10.0.0.1:8443');
      expect((await store.all()).map((p) => p.name), ['Nuvem']);
    });

    test('guardar o mesmo endereço de novo troca, não duplica', () async {
      await store.save(paired('10.0.0.1:8443', name: 'Velho'));
      await store.save(paired('10.0.0.1:8443', name: 'Novo'));
      expect((await store.all()).map((p) => p.name), ['Novo']);
    });

    test('o limite derruba os mais antigos', () async {
      for (var i = 0; i < SecurePairedStore.maxPaired + 5; i++) {
        await store.save(paired('10.0.${i ~/ 200}.${i % 200}:8443', name: 'n$i'));
      }
      final all = await store.all();
      expect(all, hasLength(SecurePairedStore.maxPaired));
      expect(all.first.name, 'n5');
      expect(all.last.name, 'n${SecurePairedStore.maxPaired + 4}');
    });

    test('lixo no armazenamento vira lista vazia, sem exceção', () async {
      for (final junk in ['', 'não é json', '{}', '123', 'null', '[1,2,3]', '[{"hostPort":1}]', '[[]]', '"x"']) {
        raw.data[SecurePairedStore.storageKey] = junk;
        expect(await store.all(), isEmpty, reason: junk);
      }
    });

    test('uma entrada cuja CA não é a que diz ser é descartada, as outras ficam', () async {
      final good = paired('10.0.0.1:8443');
      final forged = good.toJson()..['fingerprint'] = '0' * 64; // names another CA than the one it carries
      raw.data[SecurePairedStore.storageKey] = jsonEncode([forged, paired('10.0.0.2:8443', name: 'Nuvem').toJson()]);
      expect((await store.all()).map((p) => p.name), ['Nuvem']);
    });

    test('um armazenamento que falha não derruba o app: nada é lembrado', () async {
      final broken = SecurePairedStore(ThrowingStore());
      expect(await broken.all(), isEmpty);
      expect(await broken.find('10.0.0.1:8443'), isNull);
      await expectLater(broken.save(paired('10.0.0.1:8443')), throwsStateError, reason: 'the caller (the dialog) is the one who handles it');
    });

    test('uma entrada antiga, sem id do servidor, ainda é lida', () async {
      final old = paired('10.0.0.1:8443').toJson()..remove('serverId');
      raw.data[SecurePairedStore.storageKey] = jsonEncode([old]);
      expect((await store.all()).single.serverId, '');
    });
  });

  group('fetchTlsOffer', () {
    Future<HttpServer> serve(Map<String, String> headers, {int status = 200, Duration delay = Duration.zero}) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) async {
        await Future<void>.delayed(delay);
        headers.forEach(req.response.headers.set);
        req.response.statusCode = status;
        await req.response.close();
      });
      return s;
    }

    Uri base(HttpServer s) => Uri.parse('http://127.0.0.1:${s.port}');

    Future<PairingFailure?> lookupFailure(Uri uri, {Duration timeout = const Duration(seconds: 2)}) async {
      try {
        await fetchTlsOffer(uri, timeout: timeout);
        return null;
      } on ServerLookupFailed catch (e) {
        return e.reason;
      }
    }

    test('lê a porta segura e o id que o servidor anuncia', () async {
      final s = await serve({tlsHeader: '8443', idHeader: 'a1b2c3'});
      addTearDown(() => s.close(force: true));
      final offer = await fetchTlsOffer(base(s));
      expect((offer!.port, offer.serverId), (8443, 'a1b2c3'));
    });

    test('um servidor Pindrel sem lado seguro, ou com um valor que não é porta, não oferece HTTPS (e não é erro)', () async {
      for (final value in ['', 'abc', '0', '-1', '65536', '99999999999', '8.4']) {
        final s = await serve({tlsHeader: value, idHeader: 'a1b2c3'});
        expect(await fetchTlsOffer(base(s)), isNull, reason: '"$value"');
        await s.close(force: true);
      }
      final plain = await serve({idHeader: 'a1b2c3'});
      expect(await fetchTlsOffer(base(plain)), isNull);
      await plain.close(force: true);
    });

    test('o que responde mas não é um servidor Pindrel (um site, outro programa) não é "sem HTTPS": é "não é Pindrel"', () async {
      // no id header, whatever else it says; or an error page; or a redirect that leads nowhere useful
      for (final (headers, status) in <(Map<String, String>, int)>[
        ({}, 200),
        ({tlsHeader: '8443'}, 200), // a port without the id: it is not a gateway
        ({idHeader: 'a1b2c3'}, 404),
        ({idHeader: 'a1b2c3'}, 500),
        ({idHeader: ''}, 200),
        ({idHeader: 'x y/<script>'}, 200),
        ({idHeader: 'a' * 65}, 200),
        ({'server': 'gws', 'content-type': 'text/html'}, 404),
      ]) {
        final s = await serve(headers, status: status);
        expect(await lookupFailure(base(s)), PairingFailure.notPindrel, reason: '$headers $status');
        await s.close(force: true);
      }
    });

    test('um servidor de verdade que não é o Pindrel (resposta HTML grande) também não é', () async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) async {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html>${'x' * 200000}</html>');
        await req.response.close();
      });
      addTearDown(() => s.close(force: true));
      expect(await lookupFailure(base(s)), PairingFailure.notPindrel);
    });

    test('ninguém na porta, ou mudo: "sem resposta", sem exceção solta e sem esperar para sempre', () async {
      final mute = await serve({tlsHeader: '8443', idHeader: 'abc'}, delay: const Duration(seconds: 5));
      final sw = Stopwatch()..start();
      expect(await lookupFailure(base(mute), timeout: const Duration(milliseconds: 300)), PairingFailure.unreachable);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      await mute.close(force: true);
      final closed = await serve({});
      final gone = base(closed);
      await closed.close(force: true);
      expect(await lookupFailure(gone), PairingFailure.unreachable);
      // a name that does not exist is the same: nobody answered
      expect(await lookupFailure(Uri.parse('http://nome-que-nao-existe.invalid:8080')), PairingFailure.unreachable);
    });
  });
}
