// This is a generated file - do not edit.
//
// Generated from shared/protos/auth.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class SyncStatus extends $pb.ProtobufEnum {
  static const SyncStatus SYNC_STATUS_UNSPECIFIED =
      SyncStatus._(0, _omitEnumNames ? '' : 'SYNC_STATUS_UNSPECIFIED');
  static const SyncStatus SYNC_STATUS_OK =
      SyncStatus._(1, _omitEnumNames ? '' : 'SYNC_STATUS_OK');
  static const SyncStatus SYNC_STATUS_CONFLICT =
      SyncStatus._(2, _omitEnumNames ? '' : 'SYNC_STATUS_CONFLICT');

  static const $core.List<SyncStatus> values = <SyncStatus>[
    SYNC_STATUS_UNSPECIFIED,
    SYNC_STATUS_OK,
    SYNC_STATUS_CONFLICT,
  ];

  static final $core.List<SyncStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static SyncStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SyncStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
