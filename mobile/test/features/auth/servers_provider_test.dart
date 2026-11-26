import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/presentation/providers/servers_provider.dart';

import '../../support/discovery_fakes.dart';

void main() {
  late PausableDiscovery discovery;
  late ProviderContainer container;
  late ProviderSubscription<Object?> screen;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    discovery = PausableDiscovery(sampleServers);
    container = ProviderContainer(
      overrides: [serverDiscoveryProvider.overrideWithValue(discovery)],
    );
    // the login screen watches the list
    screen = container.listen(serverListControllerProvider, (_, _) {});
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

  test('sem tela mostrando a lista (saiu do login para as notas), a busca para e volta com a tela', () async {
    // before: the search went on for the whole session, a multicast sweep every few seconds
    await Future<void>.delayed(Duration.zero);
    expect(discovery.pauses, 0);
    screen.close();
    await Future<void>.delayed(Duration.zero);
    expect(discovery.pauses, 1);
    // coming back from the background must not restart a search no screen shows
    lifecycle(AppLifecycleState.paused);
    lifecycle(AppLifecycleState.resumed);
    expect(discovery.resumes, 0);
    final again = container.listen(serverListControllerProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(discovery.resumes, 1);
    again.close();
  });

  test('depois de descartar o provider, o ciclo de vida não faz mais nada', () {
    container.dispose();
    lifecycle(AppLifecycleState.paused);
    expect(discovery.pauses, 0);
    // tearDown disposes again: allowed
    container = ProviderContainer();
  });
}
