// This is a generated file - do not edit.
//
// Generated from auth.proto.

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

@$core.Deprecated('Use syncStatusDescriptor instead')
const SyncStatus$json = {
  '1': 'SyncStatus',
  '2': [
    {'1': 'SYNC_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'SYNC_STATUS_OK', '2': 1},
    {'1': 'SYNC_STATUS_CONFLICT', '2': 2},
  ],
};

/// Descriptor for `SyncStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List syncStatusDescriptor = $convert.base64Decode(
    'CgpTeW5jU3RhdHVzEhsKF1NZTkNfU1RBVFVTX1VOU1BFQ0lGSUVEEAASEgoOU1lOQ19TVEFUVV'
    'NfT0sQARIYChRTWU5DX1NUQVRVU19DT05GTElDVBAC');

@$core.Deprecated('Use errorHttpDescriptor instead')
const ErrorHttp$json = {
  '1': 'ErrorHttp',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 9, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `ErrorHttp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorHttpDescriptor = $convert.base64Decode(
    'CglFcnJvckh0dHASEgoEY29kZRgBIAEoCVIEY29kZRIYCgdtZXNzYWdlGAIgASgJUgdtZXNzYW'
    'dl');

@$core.Deprecated('Use errorWebSocketDescriptor instead')
const ErrorWebSocket$json = {
  '1': 'ErrorWebSocket',
  '2': [
    {'1': 'status_code', '3': 1, '4': 1, '5': 5, '10': 'statusCode'},
    {'1': 'code', '3': 2, '4': 1, '5': 9, '10': 'code'},
    {'1': 'message', '3': 3, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `ErrorWebSocket`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorWebSocketDescriptor = $convert.base64Decode(
    'Cg5FcnJvcldlYlNvY2tldBIfCgtzdGF0dXNfY29kZRgBIAEoBVIKc3RhdHVzQ29kZRISCgRjb2'
    'RlGAIgASgJUgRjb2RlEhgKB21lc3NhZ2UYAyABKAlSB21lc3NhZ2U=');

@$core.Deprecated('Use userSummaryDescriptor instead')
const UserSummary$json = {
  '1': 'UserSummary',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'email', '3': 2, '4': 1, '5': 9, '10': 'email'},
    {'1': 'username', '3': 3, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `UserSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userSummaryDescriptor = $convert.base64Decode(
    'CgtVc2VyU3VtbWFyeRIOCgJpZBgBIAEoCVICaWQSFAoFZW1haWwYAiABKAlSBWVtYWlsEhoKCH'
    'VzZXJuYW1lGAMgASgJUgh1c2VybmFtZQ==');

@$core.Deprecated('Use registerInputDescriptor instead')
const RegisterInput$json = {
  '1': 'RegisterInput',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 3, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `RegisterInput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerInputDescriptor = $convert.base64Decode(
    'Cg1SZWdpc3RlcklucHV0EhQKBWVtYWlsGAEgASgJUgVlbWFpbBIaCgh1c2VybmFtZRgCIAEoCV'
    'IIdXNlcm5hbWUSGgoIcGFzc3dvcmQYAyABKAlSCHBhc3N3b3Jk');

@$core.Deprecated('Use registerResponseDescriptor instead')
const RegisterResponse$json = {
  '1': 'RegisterResponse',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.sync.UserSummary',
      '10': 'user'
    },
  ],
};

/// Descriptor for `RegisterResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerResponseDescriptor = $convert.base64Decode(
    'ChBSZWdpc3RlclJlc3BvbnNlEiUKBHVzZXIYASABKAsyES5zeW5jLlVzZXJTdW1tYXJ5UgR1c2'
    'Vy');

@$core.Deprecated('Use loginInputDescriptor instead')
const LoginInput$json = {
  '1': 'LoginInput',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {'1': 'session_only', '3': 3, '4': 1, '5': 8, '10': 'sessionOnly'},
  ],
};

/// Descriptor for `LoginInput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginInputDescriptor = $convert.base64Decode(
    'CgpMb2dpbklucHV0EhQKBWVtYWlsGAEgASgJUgVlbWFpbBIaCghwYXNzd29yZBgCIAEoCVIIcG'
    'Fzc3dvcmQSIQoMc2Vzc2lvbl9vbmx5GAMgASgIUgtzZXNzaW9uT25seQ==');

@$core.Deprecated('Use loginRefreshResponseDescriptor instead')
const LoginRefreshResponse$json = {
  '1': 'LoginRefreshResponse',
  '2': [
    {'1': 'access_token', '3': 1, '4': 1, '5': 9, '10': 'accessToken'},
    {'1': 'expires_in', '3': 2, '4': 1, '5': 5, '10': 'expiresIn'},
  ],
};

/// Descriptor for `LoginRefreshResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRefreshResponseDescriptor = $convert.base64Decode(
    'ChRMb2dpblJlZnJlc2hSZXNwb25zZRIhCgxhY2Nlc3NfdG9rZW4YASABKAlSC2FjY2Vzc1Rva2'
    'VuEh0KCmV4cGlyZXNfaW4YAiABKAVSCWV4cGlyZXNJbg==');

@$core.Deprecated('Use documentSyncRequestDescriptor instead')
const DocumentSyncRequest$json = {
  '1': 'DocumentSyncRequest',
  '2': [
    {'1': 'document_id', '3': 1, '4': 1, '5': 9, '10': 'documentId'},
    {'1': 'base_revision', '3': 2, '4': 1, '5': 3, '10': 'baseRevision'},
    {'1': 'client_timestamp', '3': 3, '4': 1, '5': 3, '10': 'clientTimestamp'},
    {'1': 'content', '3': 4, '4': 1, '5': 12, '10': 'content'},
  ],
};

/// Descriptor for `DocumentSyncRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List documentSyncRequestDescriptor = $convert.base64Decode(
    'ChNEb2N1bWVudFN5bmNSZXF1ZXN0Eh8KC2RvY3VtZW50X2lkGAEgASgJUgpkb2N1bWVudElkEi'
    'MKDWJhc2VfcmV2aXNpb24YAiABKANSDGJhc2VSZXZpc2lvbhIpChBjbGllbnRfdGltZXN0YW1w'
    'GAMgASgDUg9jbGllbnRUaW1lc3RhbXASGAoHY29udGVudBgEIAEoDFIHY29udGVudA==');

@$core.Deprecated('Use documentSyncResponseDescriptor instead')
const DocumentSyncResponse$json = {
  '1': 'DocumentSyncResponse',
  '2': [
    {'1': 'document_id', '3': 1, '4': 1, '5': 9, '10': 'documentId'},
    {'1': 'new_revision', '3': 2, '4': 1, '5': 3, '10': 'newRevision'},
    {
      '1': 'status',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.sync.SyncStatus',
      '10': 'status'
    },
    {'1': 'conflict_doc_id', '3': 4, '4': 1, '5': 9, '10': 'conflictDocId'},
  ],
};

/// Descriptor for `DocumentSyncResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List documentSyncResponseDescriptor = $convert.base64Decode(
    'ChREb2N1bWVudFN5bmNSZXNwb25zZRIfCgtkb2N1bWVudF9pZBgBIAEoCVIKZG9jdW1lbnRJZB'
    'IhCgxuZXdfcmV2aXNpb24YAiABKANSC25ld1JldmlzaW9uEigKBnN0YXR1cxgDIAEoDjIQLnN5'
    'bmMuU3luY1N0YXR1c1IGc3RhdHVzEiYKD2NvbmZsaWN0X2RvY19pZBgEIAEoCVINY29uZmxpY3'
    'REb2NJZA==');
