// This is a generated file - do not edit.
//
// Generated from auth.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'auth.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'auth.pbenum.dart';

class ErrorHttp extends $pb.GeneratedMessage {
  factory ErrorHttp({
    $core.String? code,
    $core.String? message,
  }) {
    final result = ErrorHttp._();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    return result;
  }

  ErrorHttp._();

  factory ErrorHttp.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorHttp()..mergeFromBuffer(data, registry);
  factory ErrorHttp.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorHttp()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorHttp',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: ErrorHttp.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorHttp clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorHttp copyWith(void Function(ErrorHttp) updates) =>
      super.copyWith((message) => updates(message as ErrorHttp)) as ErrorHttp;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ErrorHttp() / ErrorHttp.new instead')
  static ErrorHttp create() => ErrorHttp._();
  static $pb.GeneratedMessage $_createMessage() => ErrorHttp._();
  @$core.override
  ErrorHttp createEmptyInstance() => ErrorHttp._();
  @$core.pragma('dart2js:noInline')
  static ErrorHttp getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ErrorHttp>(ErrorHttp.$_createMessage);
  static ErrorHttp? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

class ErrorWebSocket extends $pb.GeneratedMessage {
  factory ErrorWebSocket({
    $core.int? statusCode,
    $core.String? code,
    $core.String? message,
  }) {
    final result = ErrorWebSocket._();
    if (statusCode != null) result.statusCode = statusCode;
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    return result;
  }

  ErrorWebSocket._();

  factory ErrorWebSocket.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorWebSocket()..mergeFromBuffer(data, registry);
  factory ErrorWebSocket.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorWebSocket()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorWebSocket',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: ErrorWebSocket.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'statusCode')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorWebSocket clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorWebSocket copyWith(void Function(ErrorWebSocket) updates) =>
      super.copyWith((message) => updates(message as ErrorWebSocket))
          as ErrorWebSocket;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ErrorWebSocket() / ErrorWebSocket.new instead')
  static ErrorWebSocket create() => ErrorWebSocket._();
  static $pb.GeneratedMessage $_createMessage() => ErrorWebSocket._();
  @$core.override
  ErrorWebSocket createEmptyInstance() => ErrorWebSocket._();
  @$core.pragma('dart2js:noInline')
  static ErrorWebSocket getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorWebSocket>(
          ErrorWebSocket.$_createMessage);
  static ErrorWebSocket? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get statusCode => $_getIZ(0);
  @$pb.TagNumber(1)
  set statusCode($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatusCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatusCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField(3);
}

class UserSummary extends $pb.GeneratedMessage {
  factory UserSummary({
    $core.String? id,
    $core.String? email,
    $core.String? username,
  }) {
    final result = UserSummary._();
    if (id != null) result.id = id;
    if (email != null) result.email = email;
    if (username != null) result.username = username;
    return result;
  }

  UserSummary._();

  factory UserSummary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserSummary()..mergeFromBuffer(data, registry);
  factory UserSummary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserSummary()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserSummary',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: UserSummary.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'email')
    ..aOS(3, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserSummary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserSummary copyWith(void Function(UserSummary) updates) =>
      super.copyWith((message) => updates(message as UserSummary))
          as UserSummary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UserSummary() / UserSummary.new instead')
  static UserSummary create() => UserSummary._();
  static $pb.GeneratedMessage $_createMessage() => UserSummary._();
  @$core.override
  UserSummary createEmptyInstance() => UserSummary._();
  @$core.pragma('dart2js:noInline')
  static UserSummary getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserSummary>(
          UserSummary.$_createMessage);
  static UserSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get email => $_getSZ(1);
  @$pb.TagNumber(2)
  set email($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmail() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmail() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get username => $_getSZ(2);
  @$pb.TagNumber(3)
  set username($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUsername() => $_has(2);
  @$pb.TagNumber(3)
  void clearUsername() => $_clearField(3);
}

class RegisterInput extends $pb.GeneratedMessage {
  factory RegisterInput({
    $core.String? email,
    $core.String? username,
    $core.String? password,
  }) {
    final result = RegisterInput._();
    if (email != null) result.email = email;
    if (username != null) result.username = username;
    if (password != null) result.password = password;
    return result;
  }

  RegisterInput._();

  factory RegisterInput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterInput()..mergeFromBuffer(data, registry);
  factory RegisterInput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterInput()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterInput',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: RegisterInput.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterInput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterInput copyWith(void Function(RegisterInput) updates) =>
      super.copyWith((message) => updates(message as RegisterInput))
          as RegisterInput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RegisterInput() / RegisterInput.new instead')
  static RegisterInput create() => RegisterInput._();
  static $pb.GeneratedMessage $_createMessage() => RegisterInput._();
  @$core.override
  RegisterInput createEmptyInstance() => RegisterInput._();
  @$core.pragma('dart2js:noInline')
  static RegisterInput getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RegisterInput>(
          RegisterInput.$_createMessage);
  static RegisterInput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get password => $_getSZ(2);
  @$pb.TagNumber(3)
  set password($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPassword() => $_has(2);
  @$pb.TagNumber(3)
  void clearPassword() => $_clearField(3);
}

class RegisterResponse extends $pb.GeneratedMessage {
  factory RegisterResponse({
    UserSummary? user,
  }) {
    final result = RegisterResponse._();
    if (user != null) result.user = user;
    return result;
  }

  RegisterResponse._();

  factory RegisterResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterResponse()..mergeFromBuffer(data, registry);
  factory RegisterResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RegisterResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: RegisterResponse.$_createMessage)
    ..aOM<UserSummary>(1, _omitFieldNames ? '' : 'user',
        subBuilder: UserSummary.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterResponse copyWith(void Function(RegisterResponse) updates) =>
      super.copyWith((message) => updates(message as RegisterResponse))
          as RegisterResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RegisterResponse() / RegisterResponse.new instead')
  static RegisterResponse create() => RegisterResponse._();
  static $pb.GeneratedMessage $_createMessage() => RegisterResponse._();
  @$core.override
  RegisterResponse createEmptyInstance() => RegisterResponse._();
  @$core.pragma('dart2js:noInline')
  static RegisterResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RegisterResponse>(
          RegisterResponse.$_createMessage);
  static RegisterResponse? _defaultInstance;

  @$pb.TagNumber(1)
  UserSummary get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(UserSummary value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  UserSummary ensureUser() => $_ensure(0);
}

class LoginInput extends $pb.GeneratedMessage {
  factory LoginInput({
    $core.String? email,
    $core.String? password,
    $core.bool? sessionOnly,
  }) {
    final result = LoginInput._();
    if (email != null) result.email = email;
    if (password != null) result.password = password;
    if (sessionOnly != null) result.sessionOnly = sessionOnly;
    return result;
  }

  LoginInput._();

  factory LoginInput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginInput()..mergeFromBuffer(data, registry);
  factory LoginInput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginInput()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoginInput',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: LoginInput.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..aOB(3, _omitFieldNames ? '' : 'sessionOnly')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginInput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginInput copyWith(void Function(LoginInput) updates) =>
      super.copyWith((message) => updates(message as LoginInput)) as LoginInput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LoginInput() / LoginInput.new instead')
  static LoginInput create() => LoginInput._();
  static $pb.GeneratedMessage $_createMessage() => LoginInput._();
  @$core.override
  LoginInput createEmptyInstance() => LoginInput._();
  @$core.pragma('dart2js:noInline')
  static LoginInput getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoginInput>(LoginInput.$_createMessage);
  static LoginInput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);

  /// true: the refresh cookie lasts until the browser closes instead of its full lifetime ("Manter conectado" unchecked).
  /// Left out, it keeps the long-lived cookie, so clients that do not know the field behave as before.
  @$pb.TagNumber(3)
  $core.bool get sessionOnly => $_getBF(2);
  @$pb.TagNumber(3)
  set sessionOnly($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionOnly() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionOnly() => $_clearField(3);
}

class LoginRefreshResponse extends $pb.GeneratedMessage {
  factory LoginRefreshResponse({
    $core.String? accessToken,
    $core.int? expiresIn,
  }) {
    final result = LoginRefreshResponse._();
    if (accessToken != null) result.accessToken = accessToken;
    if (expiresIn != null) result.expiresIn = expiresIn;
    return result;
  }

  LoginRefreshResponse._();

  factory LoginRefreshResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginRefreshResponse()..mergeFromBuffer(data, registry);
  factory LoginRefreshResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginRefreshResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoginRefreshResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: LoginRefreshResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'accessToken')
    ..aI(2, _omitFieldNames ? '' : 'expiresIn')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRefreshResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRefreshResponse copyWith(void Function(LoginRefreshResponse) updates) =>
      super.copyWith((message) => updates(message as LoginRefreshResponse))
          as LoginRefreshResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use LoginRefreshResponse() / LoginRefreshResponse.new instead')
  static LoginRefreshResponse create() => LoginRefreshResponse._();
  static $pb.GeneratedMessage $_createMessage() => LoginRefreshResponse._();
  @$core.override
  LoginRefreshResponse createEmptyInstance() => LoginRefreshResponse._();
  @$core.pragma('dart2js:noInline')
  static LoginRefreshResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoginRefreshResponse>(
          LoginRefreshResponse.$_createMessage);
  static LoginRefreshResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accessToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set accessToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccessToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccessToken() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get expiresIn => $_getIZ(1);
  @$pb.TagNumber(2)
  set expiresIn($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExpiresIn() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresIn() => $_clearField(2);
}

class DocumentSyncRequest extends $pb.GeneratedMessage {
  factory DocumentSyncRequest({
    $core.String? documentId,
    $fixnum.Int64? baseRevision,
    $fixnum.Int64? clientTimestamp,
    $core.List<$core.int>? content,
  }) {
    final result = DocumentSyncRequest._();
    if (documentId != null) result.documentId = documentId;
    if (baseRevision != null) result.baseRevision = baseRevision;
    if (clientTimestamp != null) result.clientTimestamp = clientTimestamp;
    if (content != null) result.content = content;
    return result;
  }

  DocumentSyncRequest._();

  factory DocumentSyncRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DocumentSyncRequest()..mergeFromBuffer(data, registry);
  factory DocumentSyncRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DocumentSyncRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DocumentSyncRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: DocumentSyncRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'documentId')
    ..aInt64(2, _omitFieldNames ? '' : 'baseRevision')
    ..aInt64(3, _omitFieldNames ? '' : 'clientTimestamp')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DocumentSyncRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DocumentSyncRequest copyWith(void Function(DocumentSyncRequest) updates) =>
      super.copyWith((message) => updates(message as DocumentSyncRequest))
          as DocumentSyncRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DocumentSyncRequest() / DocumentSyncRequest.new instead')
  static DocumentSyncRequest create() => DocumentSyncRequest._();
  static $pb.GeneratedMessage $_createMessage() => DocumentSyncRequest._();
  @$core.override
  DocumentSyncRequest createEmptyInstance() => DocumentSyncRequest._();
  @$core.pragma('dart2js:noInline')
  static DocumentSyncRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DocumentSyncRequest>(
          DocumentSyncRequest.$_createMessage);
  static DocumentSyncRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get documentId => $_getSZ(0);
  @$pb.TagNumber(1)
  set documentId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDocumentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDocumentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get baseRevision => $_getI64(1);
  @$pb.TagNumber(2)
  set baseRevision($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBaseRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearBaseRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get clientTimestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set clientTimestamp($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientTimestamp() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get content => $_getN(3);
  @$pb.TagNumber(4)
  set content($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearContent() => $_clearField(4);
}

class DocumentSyncResponse extends $pb.GeneratedMessage {
  factory DocumentSyncResponse({
    $core.String? documentId,
    $fixnum.Int64? newRevision,
    SyncStatus? status,
    $core.String? conflictDocId,
  }) {
    final result = DocumentSyncResponse._();
    if (documentId != null) result.documentId = documentId;
    if (newRevision != null) result.newRevision = newRevision;
    if (status != null) result.status = status;
    if (conflictDocId != null) result.conflictDocId = conflictDocId;
    return result;
  }

  DocumentSyncResponse._();

  factory DocumentSyncResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DocumentSyncResponse()..mergeFromBuffer(data, registry);
  factory DocumentSyncResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DocumentSyncResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DocumentSyncResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sync'),
      createEmptyInstance: DocumentSyncResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'documentId')
    ..aInt64(2, _omitFieldNames ? '' : 'newRevision')
    ..aE<SyncStatus>(3, _omitFieldNames ? '' : 'status',
        enumValues: SyncStatus.values)
    ..aOS(4, _omitFieldNames ? '' : 'conflictDocId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DocumentSyncResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DocumentSyncResponse copyWith(void Function(DocumentSyncResponse) updates) =>
      super.copyWith((message) => updates(message as DocumentSyncResponse))
          as DocumentSyncResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DocumentSyncResponse() / DocumentSyncResponse.new instead')
  static DocumentSyncResponse create() => DocumentSyncResponse._();
  static $pb.GeneratedMessage $_createMessage() => DocumentSyncResponse._();
  @$core.override
  DocumentSyncResponse createEmptyInstance() => DocumentSyncResponse._();
  @$core.pragma('dart2js:noInline')
  static DocumentSyncResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DocumentSyncResponse>(
          DocumentSyncResponse.$_createMessage);
  static DocumentSyncResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get documentId => $_getSZ(0);
  @$pb.TagNumber(1)
  set documentId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDocumentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDocumentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get newRevision => $_getI64(1);
  @$pb.TagNumber(2)
  set newRevision($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNewRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  SyncStatus get status => $_getN(2);
  @$pb.TagNumber(3)
  set status(SyncStatus value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get conflictDocId => $_getSZ(3);
  @$pb.TagNumber(4)
  set conflictDocId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConflictDocId() => $_has(3);
  @$pb.TagNumber(4)
  void clearConflictDocId() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
