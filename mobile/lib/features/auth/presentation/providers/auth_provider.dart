import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/auth_api.dart';
import '../../data/auth_session.dart';
import 'servers_provider.dart';

/// The signed-in session of the device. Tests swap it for one over a fake server.
final authSessionProvider = Provider<AuthSession>((ref) {
  final session = AuthSession(
    store: ref.watch(keyValueStoreProvider),
    apiFactory: authApiFactory(ref.watch(pairedStoreProvider)),
  );
  ref.onDispose(session.dispose);
  return session;
});

/// A session found on start: the account and the server it belongs to.
typedef RestoredSession = ({Account user, Uri server});

/// On start: is there a session to go back to? Null means "the notes of the device". Never throws, and never waits
/// longer than the request's own timeout.
final sessionRestoreProvider = FutureProvider<RestoredSession?>((ref) async {
  final session = ref.watch(authSessionProvider);
  try {
    if (await session.restore() && session.user != null && session.server != null) {
      return (user: session.user!, server: session.server!);
    }
  } catch (_) {}
  return null;
});
