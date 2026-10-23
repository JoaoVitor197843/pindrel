import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'mdns_discovery.dart';
import 'nsd_discovery.dart';
import 'server_discovery.dart';

/// A descoberta certa para o sistema em que o app roda.
///
/// Android, iOS, macOS e Windows usam o serviço nativo (plugin `nsd`); o
/// Linux, que o plugin não cobre, faz as varreduras mDNS por conta própria.
ServerDiscovery createPlatformDiscovery() {
  if (kIsWeb) return const NoDiscovery();
  if (Platform.isLinux) return MdnsDiscovery();
  if (Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows) {
    return NsdDiscovery();
  }
  return const NoDiscovery();
}
