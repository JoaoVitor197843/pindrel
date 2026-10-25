// This is a generated file - do not edit.
//
// Generated from server.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class ServerInfo extends $pb.GeneratedMessage {
  factory ServerInfo({
    $core.String? name,
    $core.bool? registrationEnabled,
  }) {
    final result = ServerInfo._();
    if (name != null) result.name = name;
    if (registrationEnabled != null)
      result.registrationEnabled = registrationEnabled;
    return result;
  }

  ServerInfo._();

  factory ServerInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerInfo()..mergeFromBuffer(data, registry);
  factory ServerInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: ServerInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOB(2, _omitFieldNames ? '' : 'registrationEnabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerInfo copyWith(void Function(ServerInfo) updates) =>
      super.copyWith((message) => updates(message as ServerInfo)) as ServerInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ServerInfo() / ServerInfo.new instead')
  static ServerInfo create() => ServerInfo._();
  static $pb.GeneratedMessage $_createMessage() => ServerInfo._();
  @$core.override
  ServerInfo createEmptyInstance() => ServerInfo._();
  @$core.pragma('dart2js:noInline')
  static ServerInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServerInfo>(ServerInfo.$_createMessage);
  static ServerInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get registrationEnabled => $_getBF(1);
  @$pb.TagNumber(2)
  set registrationEnabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRegistrationEnabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearRegistrationEnabled() => $_clearField(2);
}

/// Plany servers found on the local network (answer of GET /server/discover/, built by the gateway).
class DiscoveredServer extends $pb.GeneratedMessage {
  factory DiscoveredServer({
    $core.String? name,
    $core.String? host,
    $core.Iterable<$core.String>? addresses,
    $core.int? port,
    $core.String? id,
  }) {
    final result = DiscoveredServer._();
    if (name != null) result.name = name;
    if (host != null) result.host = host;
    if (addresses != null) result.addresses.addAll(addresses);
    if (port != null) result.port = port;
    if (id != null) result.id = id;
    return result;
  }

  DiscoveredServer._();

  factory DiscoveredServer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DiscoveredServer()..mergeFromBuffer(data, registry);
  factory DiscoveredServer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DiscoveredServer()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiscoveredServer',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: DiscoveredServer.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'host')
    ..pPS(3, _omitFieldNames ? '' : 'addresses')
    ..aI(4, _omitFieldNames ? '' : 'port')
    ..aOS(5, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveredServer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveredServer copyWith(void Function(DiscoveredServer) updates) =>
      super.copyWith((message) => updates(message as DiscoveredServer))
          as DiscoveredServer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DiscoveredServer() / DiscoveredServer.new instead')
  static DiscoveredServer create() => DiscoveredServer._();
  static $pb.GeneratedMessage $_createMessage() => DiscoveredServer._();
  @$core.override
  DiscoveredServer createEmptyInstance() => DiscoveredServer._();
  @$core.pragma('dart2js:noInline')
  static DiscoveredServer getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiscoveredServer>(
          DiscoveredServer.$_createMessage);
  static DiscoveredServer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get host => $_getSZ(1);
  @$pb.TagNumber(2)
  set host($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHost() => $_has(1);
  @$pb.TagNumber(2)
  void clearHost() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get addresses => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get port => $_getIZ(3);
  @$pb.TagNumber(4)
  set port($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPort() => $_has(3);
  @$pb.TagNumber(4)
  void clearPort() => $_clearField(4);

  /// Random id the server generated once and keeps (empty: an older server). Lets a client notice that "Casa" is no
  /// longer the same server it opened before.
  @$pb.TagNumber(5)
  $core.String get id => $_getSZ(4);
  @$pb.TagNumber(5)
  set id($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasId() => $_has(4);
  @$pb.TagNumber(5)
  void clearId() => $_clearField(5);
}

class DiscoveredServers extends $pb.GeneratedMessage {
  factory DiscoveredServers({
    $core.Iterable<DiscoveredServer>? servers,
  }) {
    final result = DiscoveredServers._();
    if (servers != null) result.servers.addAll(servers);
    return result;
  }

  DiscoveredServers._();

  factory DiscoveredServers.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DiscoveredServers()..mergeFromBuffer(data, registry);
  factory DiscoveredServers.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DiscoveredServers()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiscoveredServers',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: DiscoveredServers.$_createMessage)
    ..pPM<DiscoveredServer>(1, _omitFieldNames ? '' : 'servers',
        subBuilder: DiscoveredServer.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveredServers clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiscoveredServers copyWith(void Function(DiscoveredServers) updates) =>
      super.copyWith((message) => updates(message as DiscoveredServers))
          as DiscoveredServers;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DiscoveredServers() / DiscoveredServers.new instead')
  static DiscoveredServers create() => DiscoveredServers._();
  static $pb.GeneratedMessage $_createMessage() => DiscoveredServers._();
  @$core.override
  DiscoveredServers createEmptyInstance() => DiscoveredServers._();
  @$core.pragma('dart2js:noInline')
  static DiscoveredServers getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DiscoveredServers>(
          DiscoveredServers.$_createMessage);
  static DiscoveredServers? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DiscoveredServer> get servers => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
