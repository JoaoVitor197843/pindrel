import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';

import '../../support/discovery_fakes.dart';

void main() {
  late PausableDiscovery discovery;
  late ProviderContainer container;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    discovery = PausableDiscovery(sampleServers);
    container = ProviderContainer(
      overrides: [serverDiscoveryProvider.overrideWithValue(discovery)],
    );
    container.read(serverListControllerProvider);
  });

  tearDown(() => container.dispose());

  void lifecycle(AppLifecycleState state) =>
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);

  test('app em segundo plano pausa a busca; ao voltar, retoma', () {
    lifecycle(AppLifecycleState.paused);
    expect(discovery.pauses, 1);
    lifecycle(AppLifecycleState.resumed);
    expect(discovery.resumes, 1);
  });

  test('inactive (diálogo de permissão, cortina) não interrompe a busca', () {
    lifecycle(AppLifecycleState.inactive);
    expect(discovery.pauses, 0);
  });

  test('hidden também pausa, e idas e vindas repetidas não confundem', () {
    for (var i = 0; i < 5; i++) {
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.paused);
      lifecycle(AppLifecycleState.inactive);
      lifecycle(AppLifecycleState.resumed);
      lifecycle(AppLifecycleState.resumed);
    }
    expect(discovery.pauses, 5);
    expect(discovery.resumes, 5);
  });

  test('depois de descartar o provider, o ciclo de vida não faz mais nada', () {
    container.dispose();
    lifecycle(AppLifecycleState.paused);
    expect(discovery.pauses, 0);
    // tearDown disposes again: allowed
    container = ProviderContainer();
  });
}
