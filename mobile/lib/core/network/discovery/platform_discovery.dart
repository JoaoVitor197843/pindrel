import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'mdns_discovery.dart';
import 'nsd_discovery.dart';
import 'server_discovery.dart';

/// The right discovery for the system the app runs on.
///
/// Android, iOS, macOS and Windows use the native service (`nsd` plugin); Linux,
/// which the plugin does not cover, does the mDNS sweeps on its own.
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
