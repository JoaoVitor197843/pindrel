// This is a generated file - do not edit.
//
// Generated from server.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use serverInfoDescriptor instead')
const ServerInfo$json = {
  '1': 'ServerInfo',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'registration_enabled',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'registrationEnabled'
    },
  ],
};

/// Descriptor for `ServerInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverInfoDescriptor = $convert.base64Decode(
    'CgpTZXJ2ZXJJbmZvEhIKBG5hbWUYASABKAlSBG5hbWUSMQoUcmVnaXN0cmF0aW9uX2VuYWJsZW'
    'QYAiABKAhSE3JlZ2lzdHJhdGlvbkVuYWJsZWQ=');

@$core.Deprecated('Use discoveredServerDescriptor instead')
const DiscoveredServer$json = {
  '1': 'DiscoveredServer',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'host', '3': 2, '4': 1, '5': 9, '10': 'host'},
    {'1': 'addresses', '3': 3, '4': 3, '5': 9, '10': 'addresses'},
    {'1': 'port', '3': 4, '4': 1, '5': 5, '10': 'port'},
    {'1': 'id', '3': 5, '4': 1, '5': 9, '10': 'id'},
    {'1': 'tls_port', '3': 6, '4': 1, '5': 5, '10': 'tlsPort'},
  ],
};

/// Descriptor for `DiscoveredServer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List discoveredServerDescriptor = $convert.base64Decode(
    'ChBEaXNjb3ZlcmVkU2VydmVyEhIKBG5hbWUYASABKAlSBG5hbWUSEgoEaG9zdBgCIAEoCVIEaG'
    '9zdBIcCglhZGRyZXNzZXMYAyADKAlSCWFkZHJlc3NlcxISCgRwb3J0GAQgASgFUgRwb3J0Eg4K'
    'AmlkGAUgASgJUgJpZBIZCgh0bHNfcG9ydBgGIAEoBVIHdGxzUG9ydA==');

@$core.Deprecated('Use discoveredServersDescriptor instead')
const DiscoveredServers$json = {
  '1': 'DiscoveredServers',
  '2': [
    {
      '1': 'servers',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.sync.DiscoveredServer',
      '10': 'servers'
    },
  ],
};

/// Descriptor for `DiscoveredServers`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List discoveredServersDescriptor = $convert.base64Decode(
    'ChFEaXNjb3ZlcmVkU2VydmVycxIwCgdzZXJ2ZXJzGAEgAygLMhYuc3luYy5EaXNjb3ZlcmVkU2'
    'VydmVyUgdzZXJ2ZXJz');
