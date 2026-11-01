import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'mdns_discovery.dart';
import 'nsd_discovery.dart';
import 'server_discovery.dart';

/// The right discovery for the system the app runs on.
///
/// Android, iOS and macOS use the native service (`nsd` plugin); Linux, which the
/// plugin does not cover, and Windows, where the plugin sends its results from a
/// non-platform thread and loses them, do the mDNS sweeps on their own.
ServerDiscovery createPlatformDiscovery() {
  if (kIsWeb) return const NoDiscovery();
  if (Platform.isLinux || Platform.isWindows) return MdnsDiscovery();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return NsdDiscovery();
  }
  return const NoDiscovery();
}
