// This is a generated file - do not edit.
//
// Generated from kalinka/renderer/v1/renderer.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'renderer.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'renderer.pbenum.dart';

enum Envelope_Payload {
  hello,
  stateSnapshot,
  playbackStateChanged,
  sourceChanged,
  volumeChanged,
  playbackError,
  commandRejected,
  capabilitiesChanged,
  sessionOpenResult,
  sessionClosed,
  configSnapshot,
  configResult,
  upgradeResult,
  playbackEvent,
  welcome,
  command,
  sessionOpen,
  sessionClose,
  configRequest,
  configUpdate,
  upgrade,
  goodbye,
  notSet
}

class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    $fixnum.Int64? messageId,
    $core.String? sessionId,
    $fixnum.Int64? inReplyTo,
    Hello? hello,
    StateSnapshot? stateSnapshot,
    PlaybackStateChanged? playbackStateChanged,
    SourceChanged? sourceChanged,
    VolumeChanged? volumeChanged,
    PlaybackError? playbackError,
    CommandRejected? commandRejected,
    CapabilitiesChanged? capabilitiesChanged,
    SessionOpenResult? sessionOpenResult,
    SessionClosed? sessionClosed,
    ConfigSnapshot? configSnapshot,
    ConfigResult? configResult,
    UpgradeResult? upgradeResult,
    PlaybackEvent? playbackEvent,
    Welcome? welcome,
    Command? command,
    SessionOpen? sessionOpen,
    SessionClose? sessionClose,
    ConfigRequest? configRequest,
    ConfigUpdate? configUpdate,
    Upgrade? upgrade,
    Goodbye? goodbye,
  }) {
    final result = create();
    if (messageId != null) result.messageId = messageId;
    if (sessionId != null) result.sessionId = sessionId;
    if (inReplyTo != null) result.inReplyTo = inReplyTo;
    if (hello != null) result.hello = hello;
    if (stateSnapshot != null) result.stateSnapshot = stateSnapshot;
    if (playbackStateChanged != null)
      result.playbackStateChanged = playbackStateChanged;
    if (sourceChanged != null) result.sourceChanged = sourceChanged;
    if (volumeChanged != null) result.volumeChanged = volumeChanged;
    if (playbackError != null) result.playbackError = playbackError;
    if (commandRejected != null) result.commandRejected = commandRejected;
    if (capabilitiesChanged != null)
      result.capabilitiesChanged = capabilitiesChanged;
    if (sessionOpenResult != null) result.sessionOpenResult = sessionOpenResult;
    if (sessionClosed != null) result.sessionClosed = sessionClosed;
    if (configSnapshot != null) result.configSnapshot = configSnapshot;
    if (configResult != null) result.configResult = configResult;
    if (upgradeResult != null) result.upgradeResult = upgradeResult;
    if (playbackEvent != null) result.playbackEvent = playbackEvent;
    if (welcome != null) result.welcome = welcome;
    if (command != null) result.command = command;
    if (sessionOpen != null) result.sessionOpen = sessionOpen;
    if (sessionClose != null) result.sessionClose = sessionClose;
    if (configRequest != null) result.configRequest = configRequest;
    if (configUpdate != null) result.configUpdate = configUpdate;
    if (upgrade != null) result.upgrade = upgrade;
    if (goodbye != null) result.goodbye = goodbye;
    return result;
  }

  Envelope._();

  factory Envelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Envelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Envelope_Payload> _Envelope_PayloadByTag = {
    1000: Envelope_Payload.hello,
    1001: Envelope_Payload.stateSnapshot,
    1002: Envelope_Payload.playbackStateChanged,
    1003: Envelope_Payload.sourceChanged,
    1005: Envelope_Payload.volumeChanged,
    1008: Envelope_Payload.playbackError,
    1009: Envelope_Payload.commandRejected,
    1010: Envelope_Payload.capabilitiesChanged,
    1012: Envelope_Payload.sessionOpenResult,
    1014: Envelope_Payload.sessionClosed,
    1015: Envelope_Payload.configSnapshot,
    1016: Envelope_Payload.configResult,
    1017: Envelope_Payload.upgradeResult,
    1018: Envelope_Payload.playbackEvent,
    2000: Envelope_Payload.welcome,
    2001: Envelope_Payload.command,
    2003: Envelope_Payload.sessionOpen,
    2004: Envelope_Payload.sessionClose,
    2005: Envelope_Payload.configRequest,
    2006: Envelope_Payload.configUpdate,
    2007: Envelope_Payload.upgrade,
    3000: Envelope_Payload.goodbye,
    0: Envelope_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Envelope',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..oo(0, [
      1000,
      1001,
      1002,
      1003,
      1005,
      1008,
      1009,
      1010,
      1012,
      1014,
      1015,
      1016,
      1017,
      1018,
      2000,
      2001,
      2003,
      2004,
      2005,
      2006,
      2007,
      3000
    ])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'inReplyTo', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<Hello>(1000, _omitFieldNames ? '' : 'hello', subBuilder: Hello.create)
    ..aOM<StateSnapshot>(1001, _omitFieldNames ? '' : 'stateSnapshot',
        subBuilder: StateSnapshot.create)
    ..aOM<PlaybackStateChanged>(
        1002, _omitFieldNames ? '' : 'playbackStateChanged',
        subBuilder: PlaybackStateChanged.create)
    ..aOM<SourceChanged>(1003, _omitFieldNames ? '' : 'sourceChanged',
        subBuilder: SourceChanged.create)
    ..aOM<VolumeChanged>(1005, _omitFieldNames ? '' : 'volumeChanged',
        subBuilder: VolumeChanged.create)
    ..aOM<PlaybackError>(1008, _omitFieldNames ? '' : 'playbackError',
        subBuilder: PlaybackError.create)
    ..aOM<CommandRejected>(1009, _omitFieldNames ? '' : 'commandRejected',
        subBuilder: CommandRejected.create)
    ..aOM<CapabilitiesChanged>(
        1010, _omitFieldNames ? '' : 'capabilitiesChanged',
        subBuilder: CapabilitiesChanged.create)
    ..aOM<SessionOpenResult>(1012, _omitFieldNames ? '' : 'sessionOpenResult',
        subBuilder: SessionOpenResult.create)
    ..aOM<SessionClosed>(1014, _omitFieldNames ? '' : 'sessionClosed',
        subBuilder: SessionClosed.create)
    ..aOM<ConfigSnapshot>(1015, _omitFieldNames ? '' : 'configSnapshot',
        subBuilder: ConfigSnapshot.create)
    ..aOM<ConfigResult>(1016, _omitFieldNames ? '' : 'configResult',
        subBuilder: ConfigResult.create)
    ..aOM<UpgradeResult>(1017, _omitFieldNames ? '' : 'upgradeResult',
        subBuilder: UpgradeResult.create)
    ..aOM<PlaybackEvent>(1018, _omitFieldNames ? '' : 'playbackEvent',
        subBuilder: PlaybackEvent.create)
    ..aOM<Welcome>(2000, _omitFieldNames ? '' : 'welcome',
        subBuilder: Welcome.create)
    ..aOM<Command>(2001, _omitFieldNames ? '' : 'command',
        subBuilder: Command.create)
    ..aOM<SessionOpen>(2003, _omitFieldNames ? '' : 'sessionOpen',
        subBuilder: SessionOpen.create)
    ..aOM<SessionClose>(2004, _omitFieldNames ? '' : 'sessionClose',
        subBuilder: SessionClose.create)
    ..aOM<ConfigRequest>(2005, _omitFieldNames ? '' : 'configRequest',
        subBuilder: ConfigRequest.create)
    ..aOM<ConfigUpdate>(2006, _omitFieldNames ? '' : 'configUpdate',
        subBuilder: ConfigUpdate.create)
    ..aOM<Upgrade>(2007, _omitFieldNames ? '' : 'upgrade',
        subBuilder: Upgrade.create)
    ..aOM<Goodbye>(3000, _omitFieldNames ? '' : 'goodbye',
        subBuilder: Goodbye.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope copyWith(void Function(Envelope) updates) =>
      super.copyWith((message) => updates(message as Envelope)) as Envelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Envelope create() => Envelope._();
  @$core.override
  Envelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Envelope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Envelope>(create);
  static Envelope? _defaultInstance;

  @$pb.TagNumber(1000)
  @$pb.TagNumber(1001)
  @$pb.TagNumber(1002)
  @$pb.TagNumber(1003)
  @$pb.TagNumber(1005)
  @$pb.TagNumber(1008)
  @$pb.TagNumber(1009)
  @$pb.TagNumber(1010)
  @$pb.TagNumber(1012)
  @$pb.TagNumber(1014)
  @$pb.TagNumber(1015)
  @$pb.TagNumber(1016)
  @$pb.TagNumber(1017)
  @$pb.TagNumber(1018)
  @$pb.TagNumber(2000)
  @$pb.TagNumber(2001)
  @$pb.TagNumber(2003)
  @$pb.TagNumber(2004)
  @$pb.TagNumber(2005)
  @$pb.TagNumber(2006)
  @$pb.TagNumber(2007)
  @$pb.TagNumber(3000)
  Envelope_Payload whichPayload() => _Envelope_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1000)
  @$pb.TagNumber(1001)
  @$pb.TagNumber(1002)
  @$pb.TagNumber(1003)
  @$pb.TagNumber(1005)
  @$pb.TagNumber(1008)
  @$pb.TagNumber(1009)
  @$pb.TagNumber(1010)
  @$pb.TagNumber(1012)
  @$pb.TagNumber(1014)
  @$pb.TagNumber(1015)
  @$pb.TagNumber(1016)
  @$pb.TagNumber(1017)
  @$pb.TagNumber(1018)
  @$pb.TagNumber(2000)
  @$pb.TagNumber(2001)
  @$pb.TagNumber(2003)
  @$pb.TagNumber(2004)
  @$pb.TagNumber(2005)
  @$pb.TagNumber(2006)
  @$pb.TagNumber(2007)
  @$pb.TagNumber(3000)
  void clearPayload() => $_clearField($_whichOneof(0));

  /// Monotonic from 1, per connection, per direction. Resets on reconnect.
  @$pb.TagNumber(1)
  $fixnum.Int64 get messageId => $_getI64(0);
  @$pb.TagNumber(1)
  set messageId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => $_clearField(1);

  /// The playback session this message belongs to. Set on commands and on every
  /// state message; empty on the handshake, on the session-lifecycle messages
  /// and on CommandRejected, which carry their own session_id.
  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  /// message_id of the request this answers. Set on the config replies, which
  /// are the only request/response traffic in the protocol.
  @$pb.TagNumber(3)
  $fixnum.Int64 get inReplyTo => $_getI64(2);
  @$pb.TagNumber(3)
  set inReplyTo($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInReplyTo() => $_has(2);
  @$pb.TagNumber(3)
  void clearInReplyTo() => $_clearField(3);

  /// renderer -> core: 1000-1999
  @$pb.TagNumber(1000)
  Hello get hello => $_getN(3);
  @$pb.TagNumber(1000)
  set hello(Hello value) => $_setField(1000, value);
  @$pb.TagNumber(1000)
  $core.bool hasHello() => $_has(3);
  @$pb.TagNumber(1000)
  void clearHello() => $_clearField(1000);
  @$pb.TagNumber(1000)
  Hello ensureHello() => $_ensure(3);

  @$pb.TagNumber(1001)
  StateSnapshot get stateSnapshot => $_getN(4);
  @$pb.TagNumber(1001)
  set stateSnapshot(StateSnapshot value) => $_setField(1001, value);
  @$pb.TagNumber(1001)
  $core.bool hasStateSnapshot() => $_has(4);
  @$pb.TagNumber(1001)
  void clearStateSnapshot() => $_clearField(1001);
  @$pb.TagNumber(1001)
  StateSnapshot ensureStateSnapshot() => $_ensure(4);

  @$pb.TagNumber(1002)
  PlaybackStateChanged get playbackStateChanged => $_getN(5);
  @$pb.TagNumber(1002)
  set playbackStateChanged(PlaybackStateChanged value) =>
      $_setField(1002, value);
  @$pb.TagNumber(1002)
  $core.bool hasPlaybackStateChanged() => $_has(5);
  @$pb.TagNumber(1002)
  void clearPlaybackStateChanged() => $_clearField(1002);
  @$pb.TagNumber(1002)
  PlaybackStateChanged ensurePlaybackStateChanged() => $_ensure(5);

  @$pb.TagNumber(1003)
  SourceChanged get sourceChanged => $_getN(6);
  @$pb.TagNumber(1003)
  set sourceChanged(SourceChanged value) => $_setField(1003, value);
  @$pb.TagNumber(1003)
  $core.bool hasSourceChanged() => $_has(6);
  @$pb.TagNumber(1003)
  void clearSourceChanged() => $_clearField(1003);
  @$pb.TagNumber(1003)
  SourceChanged ensureSourceChanged() => $_ensure(6);

  @$pb.TagNumber(1005)
  VolumeChanged get volumeChanged => $_getN(7);
  @$pb.TagNumber(1005)
  set volumeChanged(VolumeChanged value) => $_setField(1005, value);
  @$pb.TagNumber(1005)
  $core.bool hasVolumeChanged() => $_has(7);
  @$pb.TagNumber(1005)
  void clearVolumeChanged() => $_clearField(1005);
  @$pb.TagNumber(1005)
  VolumeChanged ensureVolumeChanged() => $_ensure(7);

  @$pb.TagNumber(1008)
  PlaybackError get playbackError => $_getN(8);
  @$pb.TagNumber(1008)
  set playbackError(PlaybackError value) => $_setField(1008, value);
  @$pb.TagNumber(1008)
  $core.bool hasPlaybackError() => $_has(8);
  @$pb.TagNumber(1008)
  void clearPlaybackError() => $_clearField(1008);
  @$pb.TagNumber(1008)
  PlaybackError ensurePlaybackError() => $_ensure(8);

  @$pb.TagNumber(1009)
  CommandRejected get commandRejected => $_getN(9);
  @$pb.TagNumber(1009)
  set commandRejected(CommandRejected value) => $_setField(1009, value);
  @$pb.TagNumber(1009)
  $core.bool hasCommandRejected() => $_has(9);
  @$pb.TagNumber(1009)
  void clearCommandRejected() => $_clearField(1009);
  @$pb.TagNumber(1009)
  CommandRejected ensureCommandRejected() => $_ensure(9);

  @$pb.TagNumber(1010)
  CapabilitiesChanged get capabilitiesChanged => $_getN(10);
  @$pb.TagNumber(1010)
  set capabilitiesChanged(CapabilitiesChanged value) => $_setField(1010, value);
  @$pb.TagNumber(1010)
  $core.bool hasCapabilitiesChanged() => $_has(10);
  @$pb.TagNumber(1010)
  void clearCapabilitiesChanged() => $_clearField(1010);
  @$pb.TagNumber(1010)
  CapabilitiesChanged ensureCapabilitiesChanged() => $_ensure(10);

  @$pb.TagNumber(1012)
  SessionOpenResult get sessionOpenResult => $_getN(11);
  @$pb.TagNumber(1012)
  set sessionOpenResult(SessionOpenResult value) => $_setField(1012, value);
  @$pb.TagNumber(1012)
  $core.bool hasSessionOpenResult() => $_has(11);
  @$pb.TagNumber(1012)
  void clearSessionOpenResult() => $_clearField(1012);
  @$pb.TagNumber(1012)
  SessionOpenResult ensureSessionOpenResult() => $_ensure(11);

  @$pb.TagNumber(1014)
  SessionClosed get sessionClosed => $_getN(12);
  @$pb.TagNumber(1014)
  set sessionClosed(SessionClosed value) => $_setField(1014, value);
  @$pb.TagNumber(1014)
  $core.bool hasSessionClosed() => $_has(12);
  @$pb.TagNumber(1014)
  void clearSessionClosed() => $_clearField(1014);
  @$pb.TagNumber(1014)
  SessionClosed ensureSessionClosed() => $_ensure(12);

  @$pb.TagNumber(1015)
  ConfigSnapshot get configSnapshot => $_getN(13);
  @$pb.TagNumber(1015)
  set configSnapshot(ConfigSnapshot value) => $_setField(1015, value);
  @$pb.TagNumber(1015)
  $core.bool hasConfigSnapshot() => $_has(13);
  @$pb.TagNumber(1015)
  void clearConfigSnapshot() => $_clearField(1015);
  @$pb.TagNumber(1015)
  ConfigSnapshot ensureConfigSnapshot() => $_ensure(13);

  @$pb.TagNumber(1016)
  ConfigResult get configResult => $_getN(14);
  @$pb.TagNumber(1016)
  set configResult(ConfigResult value) => $_setField(1016, value);
  @$pb.TagNumber(1016)
  $core.bool hasConfigResult() => $_has(14);
  @$pb.TagNumber(1016)
  void clearConfigResult() => $_clearField(1016);
  @$pb.TagNumber(1016)
  ConfigResult ensureConfigResult() => $_ensure(14);

  @$pb.TagNumber(1017)
  UpgradeResult get upgradeResult => $_getN(15);
  @$pb.TagNumber(1017)
  set upgradeResult(UpgradeResult value) => $_setField(1017, value);
  @$pb.TagNumber(1017)
  $core.bool hasUpgradeResult() => $_has(15);
  @$pb.TagNumber(1017)
  void clearUpgradeResult() => $_clearField(1017);
  @$pb.TagNumber(1017)
  UpgradeResult ensureUpgradeResult() => $_ensure(15);

  @$pb.TagNumber(1018)
  PlaybackEvent get playbackEvent => $_getN(16);
  @$pb.TagNumber(1018)
  set playbackEvent(PlaybackEvent value) => $_setField(1018, value);
  @$pb.TagNumber(1018)
  $core.bool hasPlaybackEvent() => $_has(16);
  @$pb.TagNumber(1018)
  void clearPlaybackEvent() => $_clearField(1018);
  @$pb.TagNumber(1018)
  PlaybackEvent ensurePlaybackEvent() => $_ensure(16);

  /// core -> renderer: 2000-2999
  @$pb.TagNumber(2000)
  Welcome get welcome => $_getN(17);
  @$pb.TagNumber(2000)
  set welcome(Welcome value) => $_setField(2000, value);
  @$pb.TagNumber(2000)
  $core.bool hasWelcome() => $_has(17);
  @$pb.TagNumber(2000)
  void clearWelcome() => $_clearField(2000);
  @$pb.TagNumber(2000)
  Welcome ensureWelcome() => $_ensure(17);

  @$pb.TagNumber(2001)
  Command get command => $_getN(18);
  @$pb.TagNumber(2001)
  set command(Command value) => $_setField(2001, value);
  @$pb.TagNumber(2001)
  $core.bool hasCommand() => $_has(18);
  @$pb.TagNumber(2001)
  void clearCommand() => $_clearField(2001);
  @$pb.TagNumber(2001)
  Command ensureCommand() => $_ensure(18);

  @$pb.TagNumber(2003)
  SessionOpen get sessionOpen => $_getN(19);
  @$pb.TagNumber(2003)
  set sessionOpen(SessionOpen value) => $_setField(2003, value);
  @$pb.TagNumber(2003)
  $core.bool hasSessionOpen() => $_has(19);
  @$pb.TagNumber(2003)
  void clearSessionOpen() => $_clearField(2003);
  @$pb.TagNumber(2003)
  SessionOpen ensureSessionOpen() => $_ensure(19);

  @$pb.TagNumber(2004)
  SessionClose get sessionClose => $_getN(20);
  @$pb.TagNumber(2004)
  set sessionClose(SessionClose value) => $_setField(2004, value);
  @$pb.TagNumber(2004)
  $core.bool hasSessionClose() => $_has(20);
  @$pb.TagNumber(2004)
  void clearSessionClose() => $_clearField(2004);
  @$pb.TagNumber(2004)
  SessionClose ensureSessionClose() => $_ensure(20);

  @$pb.TagNumber(2005)
  ConfigRequest get configRequest => $_getN(21);
  @$pb.TagNumber(2005)
  set configRequest(ConfigRequest value) => $_setField(2005, value);
  @$pb.TagNumber(2005)
  $core.bool hasConfigRequest() => $_has(21);
  @$pb.TagNumber(2005)
  void clearConfigRequest() => $_clearField(2005);
  @$pb.TagNumber(2005)
  ConfigRequest ensureConfigRequest() => $_ensure(21);

  @$pb.TagNumber(2006)
  ConfigUpdate get configUpdate => $_getN(22);
  @$pb.TagNumber(2006)
  set configUpdate(ConfigUpdate value) => $_setField(2006, value);
  @$pb.TagNumber(2006)
  $core.bool hasConfigUpdate() => $_has(22);
  @$pb.TagNumber(2006)
  void clearConfigUpdate() => $_clearField(2006);
  @$pb.TagNumber(2006)
  ConfigUpdate ensureConfigUpdate() => $_ensure(22);

  @$pb.TagNumber(2007)
  Upgrade get upgrade => $_getN(23);
  @$pb.TagNumber(2007)
  set upgrade(Upgrade value) => $_setField(2007, value);
  @$pb.TagNumber(2007)
  $core.bool hasUpgrade() => $_has(23);
  @$pb.TagNumber(2007)
  void clearUpgrade() => $_clearField(2007);
  @$pb.TagNumber(2007)
  Upgrade ensureUpgrade() => $_ensure(23);

  /// either direction
  @$pb.TagNumber(3000)
  Goodbye get goodbye => $_getN(24);
  @$pb.TagNumber(3000)
  set goodbye(Goodbye value) => $_setField(3000, value);
  @$pb.TagNumber(3000)
  $core.bool hasGoodbye() => $_has(24);
  @$pb.TagNumber(3000)
  void clearGoodbye() => $_clearField(3000);
  @$pb.TagNumber(3000)
  Goodbye ensureGoodbye() => $_ensure(24);
}

class ProtocolVersionRange extends $pb.GeneratedMessage {
  factory ProtocolVersionRange({
    $core.int? min,
    $core.int? max,
  }) {
    final result = create();
    if (min != null) result.min = min;
    if (max != null) result.max = max;
    return result;
  }

  ProtocolVersionRange._();

  factory ProtocolVersionRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProtocolVersionRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProtocolVersionRange',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'min', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'max', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProtocolVersionRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProtocolVersionRange copyWith(void Function(ProtocolVersionRange) updates) =>
      super.copyWith((message) => updates(message as ProtocolVersionRange))
          as ProtocolVersionRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProtocolVersionRange create() => ProtocolVersionRange._();
  @$core.override
  ProtocolVersionRange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProtocolVersionRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProtocolVersionRange>(create);
  static ProtocolVersionRange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get min => $_getIZ(0);
  @$pb.TagNumber(1)
  set min($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMin() => $_has(0);
  @$pb.TagNumber(1)
  void clearMin() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get max => $_getIZ(1);
  @$pb.TagNumber(2)
  set max($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMax() => $_has(1);
  @$pb.TagNumber(2)
  void clearMax() => $_clearField(2);
}

class Platform extends $pb.GeneratedMessage {
  factory Platform({
    $core.String? os,
    $core.String? osVersion,
    $core.String? arch,
    $core.String? hostname,
    $core.String? audioBackend,
    $core.String? machineId,
  }) {
    final result = create();
    if (os != null) result.os = os;
    if (osVersion != null) result.osVersion = osVersion;
    if (arch != null) result.arch = arch;
    if (hostname != null) result.hostname = hostname;
    if (audioBackend != null) result.audioBackend = audioBackend;
    if (machineId != null) result.machineId = machineId;
    return result;
  }

  Platform._();

  factory Platform.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Platform.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Platform',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'os')
    ..aOS(2, _omitFieldNames ? '' : 'osVersion')
    ..aOS(3, _omitFieldNames ? '' : 'arch')
    ..aOS(4, _omitFieldNames ? '' : 'hostname')
    ..aOS(5, _omitFieldNames ? '' : 'audioBackend')
    ..aOS(6, _omitFieldNames ? '' : 'machineId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Platform clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Platform copyWith(void Function(Platform) updates) =>
      super.copyWith((message) => updates(message as Platform)) as Platform;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Platform create() => Platform._();
  @$core.override
  Platform createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Platform getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Platform>(create);
  static Platform? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get os => $_getSZ(0);
  @$pb.TagNumber(1)
  set os($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOs() => $_has(0);
  @$pb.TagNumber(1)
  void clearOs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get osVersion => $_getSZ(1);
  @$pb.TagNumber(2)
  set osVersion($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOsVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearOsVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get arch => $_getSZ(2);
  @$pb.TagNumber(3)
  set arch($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasArch() => $_has(2);
  @$pb.TagNumber(3)
  void clearArch() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get hostname => $_getSZ(3);
  @$pb.TagNumber(4)
  set hostname($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHostname() => $_has(3);
  @$pb.TagNumber(4)
  void clearHostname() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get audioBackend => $_getSZ(4);
  @$pb.TagNumber(5)
  set audioBackend($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAudioBackend() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioBackend() => $_clearField(5);

  /// Optional /etc/machine-id; Core uses it only to recognise its own host.
  /// Missing on older renderers, which must upgrade before Core does.
  @$pb.TagNumber(6)
  $core.String get machineId => $_getSZ(5);
  @$pb.TagNumber(6)
  set machineId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMachineId() => $_has(5);
  @$pb.TagNumber(6)
  void clearMachineId() => $_clearField(6);
}

class AudioFormat extends $pb.GeneratedMessage {
  factory AudioFormat({
    $core.int? sampleRateHz,
    $core.int? channels,
    $core.int? bitsPerSample,
    $core.String? sampleFormat,
  }) {
    final result = create();
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (channels != null) result.channels = channels;
    if (bitsPerSample != null) result.bitsPerSample = bitsPerSample;
    if (sampleFormat != null) result.sampleFormat = sampleFormat;
    return result;
  }

  AudioFormat._();

  factory AudioFormat.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioFormat.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioFormat',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'sampleRateHz',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'channels', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'bitsPerSample',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'sampleFormat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFormat clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFormat copyWith(void Function(AudioFormat) updates) =>
      super.copyWith((message) => updates(message as AudioFormat))
          as AudioFormat;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioFormat create() => AudioFormat._();
  @$core.override
  AudioFormat createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioFormat getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioFormat>(create);
  static AudioFormat? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get sampleRateHz => $_getIZ(0);
  @$pb.TagNumber(1)
  set sampleRateHz($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSampleRateHz() => $_has(0);
  @$pb.TagNumber(1)
  void clearSampleRateHz() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get channels => $_getIZ(1);
  @$pb.TagNumber(2)
  set channels($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChannels() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannels() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get bitsPerSample => $_getIZ(2);
  @$pb.TagNumber(3)
  set bitsPerSample($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBitsPerSample() => $_has(2);
  @$pb.TagNumber(3)
  void clearBitsPerSample() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sampleFormat => $_getSZ(3);
  @$pb.TagNumber(4)
  set sampleFormat($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSampleFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearSampleFormat() => $_clearField(4);
}

/// The output side of playback: what the device runs at, and how it is held.
class DeviceInfo extends $pb.GeneratedMessage {
  factory DeviceInfo({
    AudioFormat? format,
    DeviceAccess? access,
  }) {
    final result = create();
    if (format != null) result.format = format;
    if (access != null) result.access = access;
    return result;
  }

  DeviceInfo._();

  factory DeviceInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceInfo',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<AudioFormat>(1, _omitFieldNames ? '' : 'format',
        subBuilder: AudioFormat.create)
    ..aE<DeviceAccess>(2, _omitFieldNames ? '' : 'access',
        enumValues: DeviceAccess.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceInfo copyWith(void Function(DeviceInfo) updates) =>
      super.copyWith((message) => updates(message as DeviceInfo)) as DeviceInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceInfo create() => DeviceInfo._();
  @$core.override
  DeviceInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceInfo>(create);
  static DeviceInfo? _defaultInstance;

  @$pb.TagNumber(1)
  AudioFormat get format => $_getN(0);
  @$pb.TagNumber(1)
  set format(AudioFormat value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormat() => $_clearField(1);
  @$pb.TagNumber(1)
  AudioFormat ensureFormat() => $_ensure(0);

  @$pb.TagNumber(2)
  DeviceAccess get access => $_getN(1);
  @$pb.TagNumber(2)
  set access(DeviceAccess value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAccess() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccess() => $_clearField(2);
}

/// One step the renderer takes the decoded samples through on their way to the
/// device.
class SignalStep extends $pb.GeneratedMessage {
  factory SignalStep({
    $core.String? kind,
    $core.String? name,
    $core.String? summary,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (name != null) result.name = name;
    if (summary != null) result.summary = summary;
    return result;
  }

  SignalStep._();

  factory SignalStep.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SignalStep.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignalStep',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'kind')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'summary')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalStep clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalStep copyWith(void Function(SignalStep) updates) =>
      super.copyWith((message) => updates(message as SignalStep)) as SignalStep;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SignalStep create() => SignalStep._();
  @$core.override
  SignalStep createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SignalStep getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SignalStep>(create);
  static SignalStep? _defaultInstance;

  /// Stable, for a client to key on: "dsd_to_pcm", "dsd_gain", "dither".
  @$pb.TagNumber(1)
  $core.String get kind => $_getSZ(0);
  @$pb.TagNumber(1)
  set kind($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// For a listener: "DSD to PCM".
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// How it is set, for a listener: "DSD64 to 176.4 kHz, 30 kHz filter".
  @$pb.TagNumber(3)
  $core.String get summary => $_getSZ(2);
  @$pb.TagNumber(3)
  set summary($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSummary() => $_has(2);
  @$pb.TagNumber(3)
  void clearSummary() => $_clearField(3);
}

/// What the renderer does to the samples between the decoder and the device, in
/// order. The volume is not a step of it: VolumeState reports that.
class SignalPath extends $pb.GeneratedMessage {
  factory SignalPath({
    $core.Iterable<SignalStep>? steps,
    $core.double? latencyMs,
  }) {
    final result = create();
    if (steps != null) result.steps.addAll(steps);
    if (latencyMs != null) result.latencyMs = latencyMs;
    return result;
  }

  SignalPath._();

  factory SignalPath.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SignalPath.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignalPath',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..pPM<SignalStep>(1, _omitFieldNames ? '' : 'steps',
        subBuilder: SignalStep.create)
    ..aD(2, _omitFieldNames ? '' : 'latencyMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalPath clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignalPath copyWith(void Function(SignalPath) updates) =>
      super.copyWith((message) => updates(message as SignalPath)) as SignalPath;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SignalPath create() => SignalPath._();
  @$core.override
  SignalPath createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SignalPath getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SignalPath>(create);
  static SignalPath? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SignalStep> get steps => $_getList(0);

  /// Audio the processing holds back ahead of what is heard, in milliseconds.
  @$pb.TagNumber(2)
  $core.double get latencyMs => $_getN(1);
  @$pb.TagNumber(2)
  set latencyMs($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLatencyMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatencyMs() => $_clearField(2);
}

enum PlaybackEvent_Kind { clipping, notSet }

/// Something that happened during playback, sent as it happens. Unlike
/// PlaybackStateChanged it states nothing that lasts, so no snapshot repeats it,
/// and unlike PlaybackError it does not stop playback. A run of one kind is sent
/// as one event at most twice a second, carrying the latest of it. A Core
/// ignores a kind it does not know.
class PlaybackEvent extends $pb.GeneratedMessage {
  factory PlaybackEvent({
    $core.String? sourceToken,
    $fixnum.Int64? atUnixMs,
    Clipping? clipping,
  }) {
    final result = create();
    if (sourceToken != null) result.sourceToken = sourceToken;
    if (atUnixMs != null) result.atUnixMs = atUnixMs;
    if (clipping != null) result.clipping = clipping;
    return result;
  }

  PlaybackEvent._();

  factory PlaybackEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlaybackEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PlaybackEvent_Kind>
      _PlaybackEvent_KindByTag = {
    10: PlaybackEvent_Kind.clipping,
    0: PlaybackEvent_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlaybackEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..oo(0, [10])
    ..aOS(1, _omitFieldNames ? '' : 'sourceToken')
    ..aInt64(2, _omitFieldNames ? '' : 'atUnixMs')
    ..aOM<Clipping>(10, _omitFieldNames ? '' : 'clipping',
        subBuilder: Clipping.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackEvent copyWith(void Function(PlaybackEvent) updates) =>
      super.copyWith((message) => updates(message as PlaybackEvent))
          as PlaybackEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlaybackEvent create() => PlaybackEvent._();
  @$core.override
  PlaybackEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlaybackEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlaybackEvent>(create);
  static PlaybackEvent? _defaultInstance;

  @$pb.TagNumber(10)
  PlaybackEvent_Kind whichKind() => _PlaybackEvent_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  void clearKind() => $_clearField($_whichOneof(0));

  /// The source it happened to, when it concerns one.
  @$pb.TagNumber(1)
  $core.String get sourceToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceToken() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get atUnixMs => $_getI64(1);
  @$pb.TagNumber(2)
  set atUnixMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtUnixMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtUnixMs() => $_clearField(2);

  @$pb.TagNumber(10)
  Clipping get clipping => $_getN(2);
  @$pb.TagNumber(10)
  set clipping(Clipping value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasClipping() => $_has(2);
  @$pb.TagNumber(10)
  void clearClipping() => $_clearField(10);
  @$pb.TagNumber(10)
  Clipping ensureClipping() => $_ensure(2);
}

/// The DSP clamped samples to the output's range.
class Clipping extends $pb.GeneratedMessage {
  factory Clipping({
    $fixnum.Int64? clippedSamples,
  }) {
    final result = create();
    if (clippedSamples != null) result.clippedSamples = clippedSamples;
    return result;
  }

  Clipping._();

  factory Clipping.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Clipping.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Clipping',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'clippedSamples', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Clipping clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Clipping copyWith(void Function(Clipping) updates) =>
      super.copyWith((message) => updates(message as Clipping)) as Clipping;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Clipping create() => Clipping._();
  @$core.override
  Clipping createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Clipping getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Clipping>(create);
  static Clipping? _defaultInstance;

  /// Samples clamped with the current room correction settings in this play.
  /// Zero clears a previous clipping report after a settings change.
  @$pb.TagNumber(1)
  $fixnum.Int64 get clippedSamples => $_getI64(0);
  @$pb.TagNumber(1)
  set clippedSamples($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClippedSamples() => $_has(0);
  @$pb.TagNumber(1)
  void clearClippedSamples() => $_clearField(1);
}

class Source extends $pb.GeneratedMessage {
  factory Source({
    $core.String? uri,
    $core.String? mimeType,
    $core.String? sourceToken,
    $fixnum.Int64? startOffsetMs,
  }) {
    final result = create();
    if (uri != null) result.uri = uri;
    if (mimeType != null) result.mimeType = mimeType;
    if (sourceToken != null) result.sourceToken = sourceToken;
    if (startOffsetMs != null) result.startOffsetMs = startOffsetMs;
    return result;
  }

  Source._();

  factory Source.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Source.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Source',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uri')
    ..aOS(2, _omitFieldNames ? '' : 'mimeType')
    ..aOS(3, _omitFieldNames ? '' : 'sourceToken')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'startOffsetMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Source clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Source copyWith(void Function(Source) updates) =>
      super.copyWith((message) => updates(message as Source)) as Source;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Source create() => Source._();
  @$core.override
  Source createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Source getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Source>(create);
  static Source? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get uri => $_getSZ(0);
  @$pb.TagNumber(1)
  set uri($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUri() => $_has(0);
  @$pb.TagNumber(1)
  void clearUri() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mimeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mimeType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMimeType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMimeType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sourceToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceToken() => $_clearField(3);

  /// Where in the stream to begin, so a source can start anywhere without a
  /// seek behind it: resuming a track on another renderer, or one track of a
  /// cue-sheet rip. Positions the renderer reports stay absolute in the stream.
  @$pb.TagNumber(4)
  $fixnum.Int64 get startOffsetMs => $_getI64(3);
  @$pb.TagNumber(4)
  set startOffsetMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStartOffsetMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearStartOffsetMs() => $_clearField(4);
}

class VolumeState extends $pb.GeneratedMessage {
  factory VolumeState({
    $core.bool? supported,
    $core.int? current,
    $core.int? max,
    VolumeBackend? backend,
    $core.Iterable<$core.double>? dbValues,
    $core.String? controlMode,
  }) {
    final result = create();
    if (supported != null) result.supported = supported;
    if (current != null) result.current = current;
    if (max != null) result.max = max;
    if (backend != null) result.backend = backend;
    if (dbValues != null) result.dbValues.addAll(dbValues);
    if (controlMode != null) result.controlMode = controlMode;
    return result;
  }

  VolumeState._();

  factory VolumeState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VolumeState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VolumeState',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'supported')
    ..aI(2, _omitFieldNames ? '' : 'current', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'max', fieldType: $pb.PbFieldType.OU3)
    ..aE<VolumeBackend>(4, _omitFieldNames ? '' : 'backend',
        enumValues: VolumeBackend.values)
    ..p<$core.double>(5, _omitFieldNames ? '' : 'dbValues', $pb.PbFieldType.KD)
    ..aOS(6, _omitFieldNames ? '' : 'controlMode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VolumeState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VolumeState copyWith(void Function(VolumeState) updates) =>
      super.copyWith((message) => updates(message as VolumeState))
          as VolumeState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VolumeState create() => VolumeState._();
  @$core.override
  VolumeState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VolumeState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VolumeState>(create);
  static VolumeState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get supported => $_getBF(0);
  @$pb.TagNumber(1)
  set supported($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSupported() => $_has(0);
  @$pb.TagNumber(1)
  void clearSupported() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get current => $_getIZ(1);
  @$pb.TagNumber(2)
  set current($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrent() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrent() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get max => $_getIZ(2);
  @$pb.TagNumber(3)
  set max($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMax() => $_has(2);
  @$pb.TagNumber(3)
  void clearMax() => $_clearField(3);

  @$pb.TagNumber(4)
  VolumeBackend get backend => $_getN(3);
  @$pb.TagNumber(4)
  set backend(VolumeBackend value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasBackend() => $_has(3);
  @$pb.TagNumber(4)
  void clearBackend() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.double> get dbValues => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get controlMode => $_getSZ(5);
  @$pb.TagNumber(6)
  set controlMode($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasControlMode() => $_has(5);
  @$pb.TagNumber(6)
  void clearControlMode() => $_clearField(6);
}

class ErrorInfo extends $pb.GeneratedMessage {
  factory ErrorInfo({
    ErrorSource? source,
    $core.String? message,
    $core.String? sourceToken,
  }) {
    final result = create();
    if (source != null) result.source = source;
    if (message != null) result.message = message;
    if (sourceToken != null) result.sourceToken = sourceToken;
    return result;
  }

  ErrorInfo._();

  factory ErrorInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ErrorInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorInfo',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aE<ErrorSource>(1, _omitFieldNames ? '' : 'source',
        enumValues: ErrorSource.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'sourceToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorInfo copyWith(void Function(ErrorInfo) updates) =>
      super.copyWith((message) => updates(message as ErrorInfo)) as ErrorInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ErrorInfo create() => ErrorInfo._();
  @$core.override
  ErrorInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ErrorInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorInfo>(create);
  static ErrorInfo? _defaultInstance;

  @$pb.TagNumber(1)
  ErrorSource get source => $_getN(0);
  @$pb.TagNumber(1)
  set source(ErrorSource value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sourceToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceToken() => $_clearField(3);
}

/// Everything the Core needs to render its UI without further round trips. One
/// definition, used on session open, after a reconnect and for RequestSnapshot.
class StateSnapshot extends $pb.GeneratedMessage {
  factory StateSnapshot({
    PlaybackState? playbackState,
    Source? currentSource,
    AudioFormat? format,
    $fixnum.Int64? positionMs,
    $core.bool? positionValid,
    $fixnum.Int64? capturedAtUnixMs,
    VolumeState? volume,
    $core.String? selectedDeviceId,
    ErrorInfo? error,
    $core.Iterable<$core.String>? queuedSourceTokens,
    DeviceInfo? deviceInfo,
    $fixnum.Int64? durationMs,
    SignalPath? signalPath,
  }) {
    final result = create();
    if (playbackState != null) result.playbackState = playbackState;
    if (currentSource != null) result.currentSource = currentSource;
    if (format != null) result.format = format;
    if (positionMs != null) result.positionMs = positionMs;
    if (positionValid != null) result.positionValid = positionValid;
    if (capturedAtUnixMs != null) result.capturedAtUnixMs = capturedAtUnixMs;
    if (volume != null) result.volume = volume;
    if (selectedDeviceId != null) result.selectedDeviceId = selectedDeviceId;
    if (error != null) result.error = error;
    if (queuedSourceTokens != null)
      result.queuedSourceTokens.addAll(queuedSourceTokens);
    if (deviceInfo != null) result.deviceInfo = deviceInfo;
    if (durationMs != null) result.durationMs = durationMs;
    if (signalPath != null) result.signalPath = signalPath;
    return result;
  }

  StateSnapshot._();

  factory StateSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StateSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StateSnapshot',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aE<PlaybackState>(1, _omitFieldNames ? '' : 'playbackState',
        enumValues: PlaybackState.values)
    ..aOM<Source>(2, _omitFieldNames ? '' : 'currentSource',
        subBuilder: Source.create)
    ..aOM<AudioFormat>(3, _omitFieldNames ? '' : 'format',
        subBuilder: AudioFormat.create)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'positionMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(5, _omitFieldNames ? '' : 'positionValid')
    ..aInt64(6, _omitFieldNames ? '' : 'capturedAtUnixMs')
    ..aOM<VolumeState>(7, _omitFieldNames ? '' : 'volume',
        subBuilder: VolumeState.create)
    ..aOS(9, _omitFieldNames ? '' : 'selectedDeviceId')
    ..aOM<ErrorInfo>(10, _omitFieldNames ? '' : 'error',
        subBuilder: ErrorInfo.create)
    ..pPS(11, _omitFieldNames ? '' : 'queuedSourceTokens')
    ..aOM<DeviceInfo>(13, _omitFieldNames ? '' : 'deviceInfo',
        subBuilder: DeviceInfo.create)
    ..a<$fixnum.Int64>(
        14, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<SignalPath>(15, _omitFieldNames ? '' : 'signalPath',
        subBuilder: SignalPath.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateSnapshot copyWith(void Function(StateSnapshot) updates) =>
      super.copyWith((message) => updates(message as StateSnapshot))
          as StateSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StateSnapshot create() => StateSnapshot._();
  @$core.override
  StateSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StateSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StateSnapshot>(create);
  static StateSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  PlaybackState get playbackState => $_getN(0);
  @$pb.TagNumber(1)
  set playbackState(PlaybackState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackState() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackState() => $_clearField(1);

  @$pb.TagNumber(2)
  Source get currentSource => $_getN(1);
  @$pb.TagNumber(2)
  set currentSource(Source value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentSource() => $_clearField(2);
  @$pb.TagNumber(2)
  Source ensureCurrentSource() => $_ensure(1);

  @$pb.TagNumber(3)
  AudioFormat get format => $_getN(2);
  @$pb.TagNumber(3)
  set format(AudioFormat value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFormat() => $_has(2);
  @$pb.TagNumber(3)
  void clearFormat() => $_clearField(3);
  @$pb.TagNumber(3)
  AudioFormat ensureFormat() => $_ensure(2);

  /// Advanced to send time by the renderer. The native StreamState.timestamp is
  /// a steady_clock value local to the renderer process and is not on the wire.
  @$pb.TagNumber(4)
  $fixnum.Int64 get positionMs => $_getI64(3);
  @$pb.TagNumber(4)
  set positionMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPositionMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearPositionMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get positionValid => $_getBF(4);
  @$pb.TagNumber(5)
  set positionValid($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPositionValid() => $_has(4);
  @$pb.TagNumber(5)
  void clearPositionValid() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get capturedAtUnixMs => $_getI64(5);
  @$pb.TagNumber(6)
  set capturedAtUnixMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCapturedAtUnixMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearCapturedAtUnixMs() => $_clearField(6);

  @$pb.TagNumber(7)
  VolumeState get volume => $_getN(6);
  @$pb.TagNumber(7)
  set volume(VolumeState value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasVolume() => $_has(6);
  @$pb.TagNumber(7)
  void clearVolume() => $_clearField(7);
  @$pb.TagNumber(7)
  VolumeState ensureVolume() => $_ensure(6);

  /// The device it is playing out of. Which devices exist is configuration
  /// (ConfigSnapshot), not state; what is in use right now is state.
  @$pb.TagNumber(9)
  $core.String get selectedDeviceId => $_getSZ(7);
  @$pb.TagNumber(9)
  set selectedDeviceId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(9)
  $core.bool hasSelectedDeviceId() => $_has(7);
  @$pb.TagNumber(9)
  void clearSelectedDeviceId() => $_clearField(9);

  @$pb.TagNumber(10)
  ErrorInfo get error => $_getN(8);
  @$pb.TagNumber(10)
  set error(ErrorInfo value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(10)
  void clearError() => $_clearField(10);
  @$pb.TagNumber(10)
  ErrorInfo ensureError() => $_ensure(8);

  /// Prefetched sources not yet playing, in switch order.
  @$pb.TagNumber(11)
  $pb.PbList<$core.String> get queuedSourceTokens => $_getList(9);

  /// The output side; see PlaybackStateChanged.device_info.
  @$pb.TagNumber(13)
  DeviceInfo get deviceInfo => $_getN(10);
  @$pb.TagNumber(13)
  set deviceInfo(DeviceInfo value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasDeviceInfo() => $_has(10);
  @$pb.TagNumber(13)
  void clearDeviceInfo() => $_clearField(13);
  @$pb.TagNumber(13)
  DeviceInfo ensureDeviceInfo() => $_ensure(10);

  /// See PlaybackStateChanged.duration_ms.
  @$pb.TagNumber(14)
  $fixnum.Int64 get durationMs => $_getI64(11);
  @$pb.TagNumber(14)
  set durationMs($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(14)
  $core.bool hasDurationMs() => $_has(11);
  @$pb.TagNumber(14)
  void clearDurationMs() => $_clearField(14);

  /// See PlaybackStateChanged.signal_path.
  @$pb.TagNumber(15)
  SignalPath get signalPath => $_getN(12);
  @$pb.TagNumber(15)
  set signalPath(SignalPath value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasSignalPath() => $_has(12);
  @$pb.TagNumber(15)
  void clearSignalPath() => $_clearField(15);
  @$pb.TagNumber(15)
  SignalPath ensureSignalPath() => $_ensure(12);
}

/// First message on every new connection; registers the renderer with the Core.
class Hello extends $pb.GeneratedMessage {
  factory Hello({
    ProtocolVersionRange? protocolVersions,
    $core.String? rendererId,
    $core.String? instanceId,
    $core.String? friendlyName,
    $core.String? softwareVersion,
    RendererKind? kind,
    Platform? platform,
    Capabilities? capabilities,
    $core.String? activeSessionId,
    $core.String? sessionOwnerServerId,
    $core.bool? upgradeSupported,
  }) {
    final result = create();
    if (protocolVersions != null) result.protocolVersions = protocolVersions;
    if (rendererId != null) result.rendererId = rendererId;
    if (instanceId != null) result.instanceId = instanceId;
    if (friendlyName != null) result.friendlyName = friendlyName;
    if (softwareVersion != null) result.softwareVersion = softwareVersion;
    if (kind != null) result.kind = kind;
    if (platform != null) result.platform = platform;
    if (capabilities != null) result.capabilities = capabilities;
    if (activeSessionId != null) result.activeSessionId = activeSessionId;
    if (sessionOwnerServerId != null)
      result.sessionOwnerServerId = sessionOwnerServerId;
    if (upgradeSupported != null) result.upgradeSupported = upgradeSupported;
    return result;
  }

  Hello._();

  factory Hello.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Hello.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Hello',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<ProtocolVersionRange>(1, _omitFieldNames ? '' : 'protocolVersions',
        subBuilder: ProtocolVersionRange.create)
    ..aOS(2, _omitFieldNames ? '' : 'rendererId')
    ..aOS(3, _omitFieldNames ? '' : 'instanceId')
    ..aOS(4, _omitFieldNames ? '' : 'friendlyName')
    ..aOS(5, _omitFieldNames ? '' : 'softwareVersion')
    ..aE<RendererKind>(6, _omitFieldNames ? '' : 'kind',
        enumValues: RendererKind.values)
    ..aOM<Platform>(7, _omitFieldNames ? '' : 'platform',
        subBuilder: Platform.create)
    ..aOM<Capabilities>(8, _omitFieldNames ? '' : 'capabilities',
        subBuilder: Capabilities.create)
    ..aOS(11, _omitFieldNames ? '' : 'activeSessionId')
    ..aOS(12, _omitFieldNames ? '' : 'sessionOwnerServerId')
    ..aOB(13, _omitFieldNames ? '' : 'upgradeSupported')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hello copyWith(void Function(Hello) updates) =>
      super.copyWith((message) => updates(message as Hello)) as Hello;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Hello create() => Hello._();
  @$core.override
  Hello createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Hello getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Hello>(create);
  static Hello? _defaultInstance;

  @$pb.TagNumber(1)
  ProtocolVersionRange get protocolVersions => $_getN(0);
  @$pb.TagNumber(1)
  set protocolVersions(ProtocolVersionRange value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersions() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersions() => $_clearField(1);
  @$pb.TagNumber(1)
  ProtocolVersionRange ensureProtocolVersions() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get rendererId => $_getSZ(1);
  @$pb.TagNumber(2)
  set rendererId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRendererId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRendererId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get instanceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set instanceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInstanceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearInstanceId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get friendlyName => $_getSZ(3);
  @$pb.TagNumber(4)
  set friendlyName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFriendlyName() => $_has(3);
  @$pb.TagNumber(4)
  void clearFriendlyName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get softwareVersion => $_getSZ(4);
  @$pb.TagNumber(5)
  set softwareVersion($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSoftwareVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearSoftwareVersion() => $_clearField(5);

  @$pb.TagNumber(6)
  RendererKind get kind => $_getN(5);
  @$pb.TagNumber(6)
  set kind(RendererKind value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasKind() => $_has(5);
  @$pb.TagNumber(6)
  void clearKind() => $_clearField(6);

  @$pb.TagNumber(7)
  Platform get platform => $_getN(6);
  @$pb.TagNumber(7)
  set platform(Platform value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPlatform() => $_has(6);
  @$pb.TagNumber(7)
  void clearPlatform() => $_clearField(7);
  @$pb.TagNumber(7)
  Platform ensurePlatform() => $_ensure(6);

  /// What the renderer can play now; absent from a renderer that predates it.
  @$pb.TagNumber(8)
  Capabilities get capabilities => $_getN(7);
  @$pb.TagNumber(8)
  set capabilities(Capabilities value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasCapabilities() => $_has(7);
  @$pb.TagNumber(8)
  void clearCapabilities() => $_clearField(8);
  @$pb.TagNumber(8)
  Capabilities ensureCapabilities() => $_ensure(7);

  /// Playback session the renderer is currently running, if any. Reported to
  /// every Core; only the one whose server_id matches acts on it.
  @$pb.TagNumber(11)
  $core.String get activeSessionId => $_getSZ(8);
  @$pb.TagNumber(11)
  set activeSessionId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(11)
  $core.bool hasActiveSessionId() => $_has(8);
  @$pb.TagNumber(11)
  void clearActiveSessionId() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get sessionOwnerServerId => $_getSZ(9);
  @$pb.TagNumber(12)
  set sessionOwnerServerId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(12)
  $core.bool hasSessionOwnerServerId() => $_has(9);
  @$pb.TagNumber(12)
  void clearSessionOwnerServerId() => $_clearField(12);

  /// Whether this renderer can install a new release of itself on request —
  /// the root-side units that do it are present. False for a build installed
  /// some other way (flatpak, from source), which a Core must not offer to
  /// upgrade.
  @$pb.TagNumber(13)
  $core.bool get upgradeSupported => $_getBF(10);
  @$pb.TagNumber(13)
  set upgradeSupported($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(13)
  $core.bool hasUpgradeSupported() => $_has(10);
  @$pb.TagNumber(13)
  void clearUpgradeSupported() => $_clearField(13);
}

/// What the renderer can play right now, stated whole every time: in Hello, then
/// in a CapabilitiesChanged to every welcomed Core whenever it changes, whichever
/// Core's settings write changed it.
class Capabilities extends $pb.GeneratedMessage {
  factory Capabilities({
    $core.bool? dsd,
    $core.int? livePcm,
    DspCapabilities? dsp,
  }) {
    final result = create();
    if (dsd != null) result.dsd = dsd;
    if (livePcm != null) result.livePcm = livePcm;
    if (dsp != null) result.dsp = dsp;
    return result;
  }

  Capabilities._();

  factory Capabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Capabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Capabilities',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'dsd')
    ..aI(2, _omitFieldNames ? '' : 'livePcm', fieldType: $pb.PbFieldType.OU3)
    ..aOM<DspCapabilities>(3, _omitFieldNames ? '' : 'dsp',
        subBuilder: DspCapabilities.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Capabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Capabilities copyWith(void Function(Capabilities) updates) =>
      super.copyWith((message) => updates(message as Capabilities))
          as Capabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Capabilities create() => Capabilities._();
  @$core.override
  Capabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Capabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Capabilities>(create);
  static Capabilities? _defaultInstance;

  /// DSD sources are taken rather than refused outright. A given track can
  /// still fail on the output it meets.
  @$pb.TagNumber(1)
  $core.bool get dsd => $_getBF(0);
  @$pb.TagNumber(1)
  set dsd($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDsd() => $_has(0);
  @$pb.TagNumber(1)
  void clearDsd() => $_clearField(1);

  /// Framed PCM, output readiness, bounded queues and live position feedback.
  @$pb.TagNumber(2)
  $core.int get livePcm => $_getIZ(1);
  @$pb.TagNumber(2)
  set livePcm($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLivePcm() => $_has(1);
  @$pb.TagNumber(2)
  void clearLivePcm() => $_clearField(2);

  /// What the DSP is built to do, whatever is set.
  @$pb.TagNumber(3)
  DspCapabilities get dsp => $_getN(2);
  @$pb.TagNumber(3)
  set dsp(DspCapabilities value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDsp() => $_has(2);
  @$pb.TagNumber(3)
  void clearDsp() => $_clearField(3);
  @$pb.TagNumber(3)
  DspCapabilities ensureDsp() => $_ensure(2);
}

class DspCapabilities extends $pb.GeneratedMessage {
  factory DspCapabilities({
    $core.bool? dsdToPcm,
    $core.Iterable<$core.String>? steps,
    $core.int? maxOutputChannels,
  }) {
    final result = create();
    if (dsdToPcm != null) result.dsdToPcm = dsdToPcm;
    if (steps != null) result.steps.addAll(steps);
    if (maxOutputChannels != null) result.maxOutputChannels = maxOutputChannels;
    return result;
  }

  DspCapabilities._();

  factory DspCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DspCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DspCapabilities',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'dsdToPcm')
    ..pPS(2, _omitFieldNames ? '' : 'steps')
    ..aI(3, _omitFieldNames ? '' : 'maxOutputChannels',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DspCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DspCapabilities copyWith(void Function(DspCapabilities) updates) =>
      super.copyWith((message) => updates(message as DspCapabilities))
          as DspCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DspCapabilities create() => DspCapabilities._();
  @$core.override
  DspCapabilities createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DspCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DspCapabilities>(create);
  static DspCapabilities? _defaultInstance;

  /// DSD can be converted to PCM.
  @$pb.TagNumber(1)
  $core.bool get dsdToPcm => $_getBF(0);
  @$pb.TagNumber(1)
  set dsdToPcm($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDsdToPcm() => $_has(0);
  @$pb.TagNumber(1)
  void clearDsdToPcm() => $_clearField(1);

  /// The SignalStep kinds the renderer can report.
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get steps => $_getList(1);

  /// The most channels the DSP puts out.
  @$pb.TagNumber(3)
  $core.int get maxOutputChannels => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxOutputChannels($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxOutputChannels() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxOutputChannels() => $_clearField(3);
}

class CapabilitiesChanged extends $pb.GeneratedMessage {
  factory CapabilitiesChanged({
    Capabilities? capabilities,
  }) {
    final result = create();
    if (capabilities != null) result.capabilities = capabilities;
    return result;
  }

  CapabilitiesChanged._();

  factory CapabilitiesChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CapabilitiesChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CapabilitiesChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<Capabilities>(1, _omitFieldNames ? '' : 'capabilities',
        subBuilder: Capabilities.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CapabilitiesChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CapabilitiesChanged copyWith(void Function(CapabilitiesChanged) updates) =>
      super.copyWith((message) => updates(message as CapabilitiesChanged))
          as CapabilitiesChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CapabilitiesChanged create() => CapabilitiesChanged._();
  @$core.override
  CapabilitiesChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CapabilitiesChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CapabilitiesChanged>(create);
  static CapabilitiesChanged? _defaultInstance;

  @$pb.TagNumber(1)
  Capabilities get capabilities => $_getN(0);
  @$pb.TagNumber(1)
  set capabilities(Capabilities value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCapabilities() => $_has(0);
  @$pb.TagNumber(1)
  void clearCapabilities() => $_clearField(1);
  @$pb.TagNumber(1)
  Capabilities ensureCapabilities() => $_ensure(0);
}

/// Core's response to a valid Hello.
class Welcome extends $pb.GeneratedMessage {
  factory Welcome({
    $core.int? protocolVersion,
    $core.String? serverId,
    $core.String? serverName,
    $core.String? serverVersion,
    $core.String? apiVersion,
    $fixnum.Int64? serverTimeUnixMs,
  }) {
    final result = create();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (serverId != null) result.serverId = serverId;
    if (serverName != null) result.serverName = serverName;
    if (serverVersion != null) result.serverVersion = serverVersion;
    if (apiVersion != null) result.apiVersion = apiVersion;
    if (serverTimeUnixMs != null) result.serverTimeUnixMs = serverTimeUnixMs;
    return result;
  }

  Welcome._();

  factory Welcome.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Welcome.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Welcome',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'serverId')
    ..aOS(4, _omitFieldNames ? '' : 'serverName')
    ..aOS(5, _omitFieldNames ? '' : 'serverVersion')
    ..aOS(6, _omitFieldNames ? '' : 'apiVersion')
    ..aInt64(7, _omitFieldNames ? '' : 'serverTimeUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Welcome clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Welcome copyWith(void Function(Welcome) updates) =>
      super.copyWith((message) => updates(message as Welcome)) as Welcome;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Welcome create() => Welcome._();
  @$core.override
  Welcome createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Welcome getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Welcome>(create);
  static Welcome? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get serverId => $_getSZ(1);
  @$pb.TagNumber(2)
  set serverId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerId() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerId() => $_clearField(2);

  /// 3 held for server_instance_id (full design).
  @$pb.TagNumber(4)
  $core.String get serverName => $_getSZ(2);
  @$pb.TagNumber(4)
  set serverName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(4)
  $core.bool hasServerName() => $_has(2);
  @$pb.TagNumber(4)
  void clearServerName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get serverVersion => $_getSZ(3);
  @$pb.TagNumber(5)
  set serverVersion($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasServerVersion() => $_has(3);
  @$pb.TagNumber(5)
  void clearServerVersion() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get apiVersion => $_getSZ(4);
  @$pb.TagNumber(6)
  set apiVersion($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasApiVersion() => $_has(4);
  @$pb.TagNumber(6)
  void clearApiVersion() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get serverTimeUnixMs => $_getI64(5);
  @$pb.TagNumber(7)
  set serverTimeUnixMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(7)
  $core.bool hasServerTimeUnixMs() => $_has(5);
  @$pb.TagNumber(7)
  void clearServerTimeUnixMs() => $_clearField(7);
}

class SessionOpen extends $pb.GeneratedMessage {
  factory SessionOpen({
    $core.String? sessionId,
    $core.bool? forceFixedOutput,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (forceFixedOutput != null) result.forceFixedOutput = forceFixedOutput;
    return result;
  }

  SessionOpen._();

  factory SessionOpen.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionOpen.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionOpen',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOB(2, _omitFieldNames ? '' : 'forceFixedOutput')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionOpen clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionOpen copyWith(void Function(SessionOpen) updates) =>
      super.copyWith((message) => updates(message as SessionOpen))
          as SessionOpen;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionOpen create() => SessionOpen._();
  @$core.override
  SessionOpen createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionOpen getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionOpen>(create);
  static SessionOpen? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  /// Core routes volume to a downstream device for this session. Temporarily
  /// force the renderer to fixed unity output: its selected ALSA playback mixer
  /// at 100% when one exists, software gain at unity, renderer volume commands
  /// disabled, and no session-start ceiling.
  /// Restore the renderer's configured output.volume_mode when the session ends.
  ///
  /// False leaves output.volume_mode entirely renderer-owned. A renderer that is
  /// persistently configured as fixed therefore also supports an amplifier with
  /// only a physical volume knob; no Core-side device module is required.
  @$pb.TagNumber(2)
  $core.bool get forceFixedOutput => $_getBF(1);
  @$pb.TagNumber(2)
  set forceFixedOutput($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasForceFixedOutput() => $_has(1);
  @$pb.TagNumber(2)
  void clearForceFixedOutput() => $_clearField(2);
}

class SessionOpenResult extends $pb.GeneratedMessage {
  factory SessionOpenResult({
    $core.String? sessionId,
    $core.bool? accepted,
    SessionOpenResult_Error? error,
    $core.String? detail,
    $core.String? ownerServerId,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (accepted != null) result.accepted = accepted;
    if (error != null) result.error = error;
    if (detail != null) result.detail = detail;
    if (ownerServerId != null) result.ownerServerId = ownerServerId;
    return result;
  }

  SessionOpenResult._();

  factory SessionOpenResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionOpenResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionOpenResult',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOB(2, _omitFieldNames ? '' : 'accepted')
    ..aE<SessionOpenResult_Error>(3, _omitFieldNames ? '' : 'error',
        enumValues: SessionOpenResult_Error.values)
    ..aOS(4, _omitFieldNames ? '' : 'detail')
    ..aOS(5, _omitFieldNames ? '' : 'ownerServerId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionOpenResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionOpenResult copyWith(void Function(SessionOpenResult) updates) =>
      super.copyWith((message) => updates(message as SessionOpenResult))
          as SessionOpenResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionOpenResult create() => SessionOpenResult._();
  @$core.override
  SessionOpenResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionOpenResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionOpenResult>(create);
  static SessionOpenResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get accepted => $_getBF(1);
  @$pb.TagNumber(2)
  set accepted($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccepted() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccepted() => $_clearField(2);

  @$pb.TagNumber(3)
  SessionOpenResult_Error get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(SessionOpenResult_Error value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get detail => $_getSZ(3);
  @$pb.TagNumber(4)
  set detail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDetail() => $_has(3);
  @$pb.TagNumber(4)
  void clearDetail() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get ownerServerId => $_getSZ(4);
  @$pb.TagNumber(5)
  set ownerServerId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOwnerServerId() => $_has(4);
  @$pb.TagNumber(5)
  void clearOwnerServerId() => $_clearField(5);
}

class SessionClose extends $pb.GeneratedMessage {
  factory SessionClose({
    $core.String? sessionId,
    SessionClose_Reason? reason,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (reason != null) result.reason = reason;
    return result;
  }

  SessionClose._();

  factory SessionClose.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionClose.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionClose',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aE<SessionClose_Reason>(2, _omitFieldNames ? '' : 'reason',
        enumValues: SessionClose_Reason.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionClose clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionClose copyWith(void Function(SessionClose) updates) =>
      super.copyWith((message) => updates(message as SessionClose))
          as SessionClose;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionClose create() => SessionClose._();
  @$core.override
  SessionClose createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionClose getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionClose>(create);
  static SessionClose? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  SessionClose_Reason get reason => $_getN(1);
  @$pb.TagNumber(2)
  set reason(SessionClose_Reason value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class SessionClosed extends $pb.GeneratedMessage {
  factory SessionClosed({
    $core.String? sessionId,
    SessionClosed_Reason? reason,
    $core.String? detail,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (reason != null) result.reason = reason;
    if (detail != null) result.detail = detail;
    return result;
  }

  SessionClosed._();

  factory SessionClosed.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionClosed.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionClosed',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aE<SessionClosed_Reason>(2, _omitFieldNames ? '' : 'reason',
        enumValues: SessionClosed_Reason.values)
    ..aOS(3, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionClosed clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionClosed copyWith(void Function(SessionClosed) updates) =>
      super.copyWith((message) => updates(message as SessionClosed))
          as SessionClosed;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionClosed create() => SessionClosed._();
  @$core.override
  SessionClosed createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionClosed getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionClosed>(create);
  static SessionClosed? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  SessionClosed_Reason get reason => $_getN(1);
  @$pb.TagNumber(2)
  set reason(SessionClosed_Reason value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get detail => $_getSZ(2);
  @$pb.TagNumber(3)
  set detail($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDetail() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetail() => $_clearField(3);
}

enum Command_Op {
  setSource,
  enqueueSource,
  removeSource,
  clearQueue,
  resume,
  pause,
  stop,
  setVolume,
  requestSnapshot,
  seek,
  notSet
}

class Command extends $pb.GeneratedMessage {
  factory Command({
    SetSource? setSource,
    EnqueueSource? enqueueSource,
    RemoveSource? removeSource,
    ClearQueue? clearQueue,
    Resume? resume,
    Pause? pause,
    Stop? stop,
    SetVolume? setVolume,
    RequestSnapshot? requestSnapshot,
    Seek? seek,
  }) {
    final result = create();
    if (setSource != null) result.setSource = setSource;
    if (enqueueSource != null) result.enqueueSource = enqueueSource;
    if (removeSource != null) result.removeSource = removeSource;
    if (clearQueue != null) result.clearQueue = clearQueue;
    if (resume != null) result.resume = resume;
    if (pause != null) result.pause = pause;
    if (stop != null) result.stop = stop;
    if (setVolume != null) result.setVolume = setVolume;
    if (requestSnapshot != null) result.requestSnapshot = requestSnapshot;
    if (seek != null) result.seek = seek;
    return result;
  }

  Command._();

  factory Command.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Command.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Command_Op> _Command_OpByTag = {
    10: Command_Op.setSource,
    11: Command_Op.enqueueSource,
    12: Command_Op.removeSource,
    13: Command_Op.clearQueue,
    14: Command_Op.resume,
    15: Command_Op.pause,
    16: Command_Op.stop,
    17: Command_Op.setVolume,
    18: Command_Op.requestSnapshot,
    22: Command_Op.seek,
    0: Command_Op.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Command',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 22])
    ..aOM<SetSource>(10, _omitFieldNames ? '' : 'setSource',
        subBuilder: SetSource.create)
    ..aOM<EnqueueSource>(11, _omitFieldNames ? '' : 'enqueueSource',
        subBuilder: EnqueueSource.create)
    ..aOM<RemoveSource>(12, _omitFieldNames ? '' : 'removeSource',
        subBuilder: RemoveSource.create)
    ..aOM<ClearQueue>(13, _omitFieldNames ? '' : 'clearQueue',
        subBuilder: ClearQueue.create)
    ..aOM<Resume>(14, _omitFieldNames ? '' : 'resume',
        subBuilder: Resume.create)
    ..aOM<Pause>(15, _omitFieldNames ? '' : 'pause', subBuilder: Pause.create)
    ..aOM<Stop>(16, _omitFieldNames ? '' : 'stop', subBuilder: Stop.create)
    ..aOM<SetVolume>(17, _omitFieldNames ? '' : 'setVolume',
        subBuilder: SetVolume.create)
    ..aOM<RequestSnapshot>(18, _omitFieldNames ? '' : 'requestSnapshot',
        subBuilder: RequestSnapshot.create)
    ..aOM<Seek>(22, _omitFieldNames ? '' : 'seek', subBuilder: Seek.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command copyWith(void Function(Command) updates) =>
      super.copyWith((message) => updates(message as Command)) as Command;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Command create() => Command._();
  @$core.override
  Command createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Command getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Command>(create);
  static Command? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(22)
  Command_Op whichOp() => _Command_OpByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(22)
  void clearOp() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(10)
  SetSource get setSource => $_getN(0);
  @$pb.TagNumber(10)
  set setSource(SetSource value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSetSource() => $_has(0);
  @$pb.TagNumber(10)
  void clearSetSource() => $_clearField(10);
  @$pb.TagNumber(10)
  SetSource ensureSetSource() => $_ensure(0);

  @$pb.TagNumber(11)
  EnqueueSource get enqueueSource => $_getN(1);
  @$pb.TagNumber(11)
  set enqueueSource(EnqueueSource value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasEnqueueSource() => $_has(1);
  @$pb.TagNumber(11)
  void clearEnqueueSource() => $_clearField(11);
  @$pb.TagNumber(11)
  EnqueueSource ensureEnqueueSource() => $_ensure(1);

  @$pb.TagNumber(12)
  RemoveSource get removeSource => $_getN(2);
  @$pb.TagNumber(12)
  set removeSource(RemoveSource value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasRemoveSource() => $_has(2);
  @$pb.TagNumber(12)
  void clearRemoveSource() => $_clearField(12);
  @$pb.TagNumber(12)
  RemoveSource ensureRemoveSource() => $_ensure(2);

  @$pb.TagNumber(13)
  ClearQueue get clearQueue => $_getN(3);
  @$pb.TagNumber(13)
  set clearQueue(ClearQueue value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasClearQueue() => $_has(3);
  @$pb.TagNumber(13)
  void clearClearQueue() => $_clearField(13);
  @$pb.TagNumber(13)
  ClearQueue ensureClearQueue() => $_ensure(3);

  @$pb.TagNumber(14)
  Resume get resume => $_getN(4);
  @$pb.TagNumber(14)
  set resume(Resume value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasResume() => $_has(4);
  @$pb.TagNumber(14)
  void clearResume() => $_clearField(14);
  @$pb.TagNumber(14)
  Resume ensureResume() => $_ensure(4);

  @$pb.TagNumber(15)
  Pause get pause => $_getN(5);
  @$pb.TagNumber(15)
  set pause(Pause value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasPause() => $_has(5);
  @$pb.TagNumber(15)
  void clearPause() => $_clearField(15);
  @$pb.TagNumber(15)
  Pause ensurePause() => $_ensure(5);

  @$pb.TagNumber(16)
  Stop get stop => $_getN(6);
  @$pb.TagNumber(16)
  set stop(Stop value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasStop() => $_has(6);
  @$pb.TagNumber(16)
  void clearStop() => $_clearField(16);
  @$pb.TagNumber(16)
  Stop ensureStop() => $_ensure(6);

  @$pb.TagNumber(17)
  SetVolume get setVolume => $_getN(7);
  @$pb.TagNumber(17)
  set setVolume(SetVolume value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasSetVolume() => $_has(7);
  @$pb.TagNumber(17)
  void clearSetVolume() => $_clearField(17);
  @$pb.TagNumber(17)
  SetVolume ensureSetVolume() => $_ensure(7);

  @$pb.TagNumber(18)
  RequestSnapshot get requestSnapshot => $_getN(8);
  @$pb.TagNumber(18)
  set requestSnapshot(RequestSnapshot value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasRequestSnapshot() => $_has(8);
  @$pb.TagNumber(18)
  void clearRequestSnapshot() => $_clearField(18);
  @$pb.TagNumber(18)
  RequestSnapshot ensureRequestSnapshot() => $_ensure(8);

  @$pb.TagNumber(22)
  Seek get seek => $_getN(9);
  @$pb.TagNumber(22)
  set seek(Seek value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasSeek() => $_has(9);
  @$pb.TagNumber(22)
  void clearSeek() => $_clearField(22);
  @$pb.TagNumber(22)
  Seek ensureSeek() => $_ensure(9);
}

/// Play this source now, replacing the queue. AudioPlayer::append() plus removal
/// of the previously-current and prefetched streams — the Core's _apply_play().
/// Playback starts on arrival: there is no separate start command.
class SetSource extends $pb.GeneratedMessage {
  factory SetSource({
    Source? source,
  }) {
    final result = create();
    if (source != null) result.source = source;
    return result;
  }

  SetSource._();

  factory SetSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetSource',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<Source>(1, _omitFieldNames ? '' : 'source', subBuilder: Source.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetSource copyWith(void Function(SetSource) updates) =>
      super.copyWith((message) => updates(message as SetSource)) as SetSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetSource create() => SetSource._();
  @$core.override
  SetSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetSource getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetSource>(create);
  static SetSource? _defaultInstance;

  @$pb.TagNumber(1)
  Source get source => $_getN(0);
  @$pb.TagNumber(1)
  set source(Source value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
  @$pb.TagNumber(1)
  Source ensureSource() => $_ensure(0);
}

/// Queue this source behind the current one for a gapless switch: append()
/// without removing anything — the Core's _apply_prefetch().
class EnqueueSource extends $pb.GeneratedMessage {
  factory EnqueueSource({
    Source? source,
  }) {
    final result = create();
    if (source != null) result.source = source;
    return result;
  }

  EnqueueSource._();

  factory EnqueueSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EnqueueSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnqueueSource',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<Source>(1, _omitFieldNames ? '' : 'source', subBuilder: Source.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnqueueSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnqueueSource copyWith(void Function(EnqueueSource) updates) =>
      super.copyWith((message) => updates(message as EnqueueSource))
          as EnqueueSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnqueueSource create() => EnqueueSource._();
  @$core.override
  EnqueueSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EnqueueSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EnqueueSource>(create);
  static EnqueueSource? _defaultInstance;

  @$pb.TagNumber(1)
  Source get source => $_getN(0);
  @$pb.TagNumber(1)
  set source(Source value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
  @$pb.TagNumber(1)
  Source ensureSource() => $_ensure(0);
}

/// AudioPlayer::remove(StreamId); the StreamId never leaves the renderer.
class RemoveSource extends $pb.GeneratedMessage {
  factory RemoveSource({
    $core.String? sourceToken,
  }) {
    final result = create();
    if (sourceToken != null) result.sourceToken = sourceToken;
    return result;
  }

  RemoveSource._();

  factory RemoveSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RemoveSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoveSource',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sourceToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveSource copyWith(void Function(RemoveSource) updates) =>
      super.copyWith((message) => updates(message as RemoveSource))
          as RemoveSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RemoveSource create() => RemoveSource._();
  @$core.override
  RemoveSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RemoveSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RemoveSource>(create);
  static RemoveSource? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sourceToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceToken() => $_clearField(1);
}

/// AudioPlayer::clearAll(): drop every source, keep the device open.
class ClearQueue extends $pb.GeneratedMessage {
  factory ClearQueue() => create();

  ClearQueue._();

  factory ClearQueue.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ClearQueue.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClearQueue',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClearQueue clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClearQueue copyWith(void Function(ClearQueue) updates) =>
      super.copyWith((message) => updates(message as ClearQueue)) as ClearQueue;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClearQueue create() => ClearQueue._();
  @$core.override
  ClearQueue createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ClearQueue getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClearQueue>(create);
  static ClearQueue? _defaultInstance;
}

/// AudioPlayer::pause() / resume(). Resume is the inverse of Pause and nothing
/// more — the player has no "start", so a renderer holding no source has nothing
/// to resume; playing something is SetSource.
class Pause extends $pb.GeneratedMessage {
  factory Pause() => create();

  Pause._();

  factory Pause.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Pause.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pause',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pause clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pause copyWith(void Function(Pause) updates) =>
      super.copyWith((message) => updates(message as Pause)) as Pause;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Pause create() => Pause._();
  @$core.override
  Pause createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Pause getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Pause>(create);
  static Pause? _defaultInstance;
}

class Resume extends $pb.GeneratedMessage {
  factory Resume() => create();

  Resume._();

  factory Resume.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resume.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resume',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resume clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resume copyWith(void Function(Resume) updates) =>
      super.copyWith((message) => updates(message as Resume)) as Resume;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resume create() => Resume._();
  @$core.override
  Resume createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resume getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Resume>(create);
  static Resume? _defaultInstance;
}

/// AudioPlayer::stop() — the device is closed.
class Stop extends $pb.GeneratedMessage {
  factory Stop() => create();

  Stop._();

  factory Stop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Stop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Stop',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Stop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Stop copyWith(void Function(Stop) updates) =>
      super.copyWith((message) => updates(message as Stop)) as Stop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Stop create() => Stop._();
  @$core.override
  Stop createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Stop getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Stop>(create);
  static Stop? _defaultInstance;
}

class SetVolume extends $pb.GeneratedMessage {
  factory SetVolume({
    $core.int? percent,
  }) {
    final result = create();
    if (percent != null) result.percent = percent;
    return result;
  }

  SetVolume._();

  factory SetVolume.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetVolume.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetVolume',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'percent', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetVolume clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetVolume copyWith(void Function(SetVolume) updates) =>
      super.copyWith((message) => updates(message as SetVolume)) as SetVolume;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetVolume create() => SetVolume._();
  @$core.override
  SetVolume createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetVolume getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetVolume>(create);
  static SetVolume? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get percent => $_getIZ(0);
  @$pb.TagNumber(1)
  set percent($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPercent() => $_has(0);
  @$pb.TagNumber(1)
  void clearPercent() => $_clearField(1);
}

class RequestSnapshot extends $pb.GeneratedMessage {
  factory RequestSnapshot() => create();

  RequestSnapshot._();

  factory RequestSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RequestSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RequestSnapshot',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RequestSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RequestSnapshot copyWith(void Function(RequestSnapshot) updates) =>
      super.copyWith((message) => updates(message as RequestSnapshot))
          as RequestSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RequestSnapshot create() => RequestSnapshot._();
  @$core.override
  RequestSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RequestSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RequestSnapshot>(create);
  static RequestSnapshot? _defaultInstance;
}

class Seek extends $pb.GeneratedMessage {
  factory Seek({
    $fixnum.Int64? positionMs,
  }) {
    final result = create();
    if (positionMs != null) result.positionMs = positionMs;
    return result;
  }

  Seek._();

  factory Seek.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Seek.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Seek',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'positionMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Seek clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Seek copyWith(void Function(Seek) updates) =>
      super.copyWith((message) => updates(message as Seek)) as Seek;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Seek create() => Seek._();
  @$core.override
  Seek createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Seek getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Seek>(create);
  static Seek? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get positionMs => $_getI64(0);
  @$pb.TagNumber(1)
  set positionMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPositionMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearPositionMs() => $_clearField(1);
}

/// The one thing a command can be answered with, and only when the renderer
/// refuses it outright: the session it named is not the one being run — never
/// opened, already closed, or another Core's. Nothing was attempted.
class CommandRejected extends $pb.GeneratedMessage {
  factory CommandRejected({
    $core.String? sessionId,
    ControlKind? command,
    $fixnum.Int64? atUnixMs,
    $core.String? detail,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (command != null) result.command = command;
    if (atUnixMs != null) result.atUnixMs = atUnixMs;
    if (detail != null) result.detail = detail;
    return result;
  }

  CommandRejected._();

  factory CommandRejected.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommandRejected.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandRejected',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aE<ControlKind>(2, _omitFieldNames ? '' : 'command',
        enumValues: ControlKind.values)
    ..aInt64(3, _omitFieldNames ? '' : 'atUnixMs')
    ..aOS(4, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandRejected clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandRejected copyWith(void Function(CommandRejected) updates) =>
      super.copyWith((message) => updates(message as CommandRejected))
          as CommandRejected;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommandRejected create() => CommandRejected._();
  @$core.override
  CommandRejected createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommandRejected getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommandRejected>(create);
  static CommandRejected? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  ControlKind get command => $_getN(1);
  @$pb.TagNumber(2)
  set command(ControlKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCommand() => $_has(1);
  @$pb.TagNumber(2)
  void clearCommand() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get atUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set atUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAtUnixMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get detail => $_getSZ(3);
  @$pb.TagNumber(4)
  set detail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDetail() => $_has(3);
  @$pb.TagNumber(4)
  void clearDetail() => $_clearField(4);
}

class PlaybackStateChanged extends $pb.GeneratedMessage {
  factory PlaybackStateChanged({
    PlaybackState? state,
    $fixnum.Int64? positionMs,
    $core.bool? positionValid,
    $core.String? sourceToken,
    $fixnum.Int64? atUnixMs,
    ErrorInfo? error,
    AudioFormat? format,
    DeviceInfo? deviceInfo,
    $fixnum.Int64? durationMs,
    $core.bool? interrupted,
    $core.bool? liveReady,
    $fixnum.Int64? liveSourceFrame,
    SignalPath? signalPath,
  }) {
    final result = create();
    if (state != null) result.state = state;
    if (positionMs != null) result.positionMs = positionMs;
    if (positionValid != null) result.positionValid = positionValid;
    if (sourceToken != null) result.sourceToken = sourceToken;
    if (atUnixMs != null) result.atUnixMs = atUnixMs;
    if (error != null) result.error = error;
    if (format != null) result.format = format;
    if (deviceInfo != null) result.deviceInfo = deviceInfo;
    if (durationMs != null) result.durationMs = durationMs;
    if (interrupted != null) result.interrupted = interrupted;
    if (liveReady != null) result.liveReady = liveReady;
    if (liveSourceFrame != null) result.liveSourceFrame = liveSourceFrame;
    if (signalPath != null) result.signalPath = signalPath;
    return result;
  }

  PlaybackStateChanged._();

  factory PlaybackStateChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlaybackStateChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlaybackStateChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aE<PlaybackState>(1, _omitFieldNames ? '' : 'state',
        enumValues: PlaybackState.values)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'positionMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(3, _omitFieldNames ? '' : 'positionValid')
    ..aOS(4, _omitFieldNames ? '' : 'sourceToken')
    ..aInt64(5, _omitFieldNames ? '' : 'atUnixMs')
    ..aOM<ErrorInfo>(6, _omitFieldNames ? '' : 'error',
        subBuilder: ErrorInfo.create)
    ..aOM<AudioFormat>(7, _omitFieldNames ? '' : 'format',
        subBuilder: AudioFormat.create)
    ..aOM<DeviceInfo>(8, _omitFieldNames ? '' : 'deviceInfo',
        subBuilder: DeviceInfo.create)
    ..a<$fixnum.Int64>(
        9, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(10, _omitFieldNames ? '' : 'interrupted')
    ..aOB(11, _omitFieldNames ? '' : 'liveReady')
    ..a<$fixnum.Int64>(
        12, _omitFieldNames ? '' : 'liveSourceFrame', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<SignalPath>(13, _omitFieldNames ? '' : 'signalPath',
        subBuilder: SignalPath.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackStateChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackStateChanged copyWith(void Function(PlaybackStateChanged) updates) =>
      super.copyWith((message) => updates(message as PlaybackStateChanged))
          as PlaybackStateChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlaybackStateChanged create() => PlaybackStateChanged._();
  @$core.override
  PlaybackStateChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlaybackStateChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlaybackStateChanged>(create);
  static PlaybackStateChanged? _defaultInstance;

  @$pb.TagNumber(1)
  PlaybackState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(PlaybackState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get positionMs => $_getI64(1);
  @$pb.TagNumber(2)
  set positionMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPositionMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearPositionMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get positionValid => $_getBF(2);
  @$pb.TagNumber(3)
  set positionValid($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPositionValid() => $_has(2);
  @$pb.TagNumber(3)
  void clearPositionValid() => $_clearField(3);

  /// The source this state refers to. Absent when the graph holds no current
  /// source, which is how "the track ended" differs from "the graph was torn
  /// down" — the distinction the Core infers today from current_stream_id.
  @$pb.TagNumber(4)
  $core.String get sourceToken => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceToken($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceToken() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get atUnixMs => $_getI64(4);
  @$pb.TagNumber(5)
  set atUnixMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAtUnixMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAtUnixMs() => $_clearField(5);

  @$pb.TagNumber(6)
  ErrorInfo get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(ErrorInfo value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  ErrorInfo ensureError() => $_ensure(5);

  /// What the renderer decoded out of the stream. Restated every time, so a
  /// Core replaces rather than merges: absent means nothing is decoded, never
  /// that the format is unchanged.
  @$pb.TagNumber(7)
  AudioFormat get format => $_getN(6);
  @$pb.TagNumber(7)
  set format(AudioFormat value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFormat() => $_has(6);
  @$pb.TagNumber(7)
  void clearFormat() => $_clearField(7);
  @$pb.TagNumber(7)
  AudioFormat ensureFormat() => $_ensure(6);

  /// The output side, against `format` above for what the decoder produced.
  /// Answering "is this bit-perfect" takes both of them and the volume state;
  /// no one of the three settles it. Absent when no device is open.
  @$pb.TagNumber(8)
  DeviceInfo get deviceInfo => $_getN(7);
  @$pb.TagNumber(8)
  set deviceInfo(DeviceInfo value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasDeviceInfo() => $_has(7);
  @$pb.TagNumber(8)
  void clearDeviceInfo() => $_clearField(8);
  @$pb.TagNumber(8)
  DeviceInfo ensureDeviceInfo() => $_ensure(7);

  /// How long the stream runs. On the state rather than in a format, so a
  /// renderer that can name neither format still reports it. Absent when
  /// unknown, which is not zero: unknown length is not a track that ended.
  @$pb.TagNumber(9)
  $fixnum.Int64 get durationMs => $_getI64(8);
  @$pb.TagNumber(9)
  set durationMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDurationMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearDurationMs() => $_clearField(9);

  /// Set only on a STOPPED without a source_token: a setting that rebuilt the
  /// audio graph stopped a source it was playing, preparing or paused on. The
  /// session carries on, so a Core may play the source again; if the new graph
  /// could not be built, that play tries once more and otherwise reports the
  /// output unavailable. A Core that ignores it sees the plain stop older
  /// renderers report.
  @$pb.TagNumber(10)
  $core.bool get interrupted => $_getBF(9);
  @$pb.TagNumber(10)
  set interrupted($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasInterrupted() => $_has(9);
  @$pb.TagNumber(10)
  void clearInterrupted() => $_clearField(10);

  /// Output format is configured and hardware settling has completed. Core
  /// may now choose a fresh PCM cursor for this source_token. Not a clock sync.
  @$pb.TagNumber(11)
  $core.bool get liveReady => $_getBF(10);
  @$pb.TagNumber(11)
  set liveReady($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLiveReady() => $_has(10);
  @$pb.TagNumber(11)
  void clearLiveReady() => $_clearField(11);

  /// Absolute PCM frame audible at report time, after live clock adaptation.
  @$pb.TagNumber(12)
  $fixnum.Int64 get liveSourceFrame => $_getI64(11);
  @$pb.TagNumber(12)
  set liveSourceFrame($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasLiveSourceFrame() => $_has(11);
  @$pb.TagNumber(12)
  void clearLiveSourceFrame() => $_clearField(12);

  /// What was done to the decoded samples on the way to `device_info`. Absent
  /// when they reach the device as decoded, the volume aside. Restated, as
  /// `format` is, whenever it changes.
  @$pb.TagNumber(13)
  SignalPath get signalPath => $_getN(12);
  @$pb.TagNumber(13)
  set signalPath(SignalPath value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasSignalPath() => $_has(12);
  @$pb.TagNumber(13)
  void clearSignalPath() => $_clearField(13);
  @$pb.TagNumber(13)
  SignalPath ensureSignalPath() => $_ensure(12);
}

/// Emitted on AudioGraphNodeState::SOURCE_CHANGED — the gapless crossover.
class SourceChanged extends $pb.GeneratedMessage {
  factory SourceChanged({
    $core.String? sourceToken,
    $core.String? previousSourceToken,
    $fixnum.Int64? atUnixMs,
  }) {
    final result = create();
    if (sourceToken != null) result.sourceToken = sourceToken;
    if (previousSourceToken != null)
      result.previousSourceToken = previousSourceToken;
    if (atUnixMs != null) result.atUnixMs = atUnixMs;
    return result;
  }

  SourceChanged._();

  factory SourceChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SourceChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourceChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sourceToken')
    ..aOS(2, _omitFieldNames ? '' : 'previousSourceToken')
    ..aInt64(3, _omitFieldNames ? '' : 'atUnixMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceChanged copyWith(void Function(SourceChanged) updates) =>
      super.copyWith((message) => updates(message as SourceChanged))
          as SourceChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SourceChanged create() => SourceChanged._();
  @$core.override
  SourceChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SourceChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourceChanged>(create);
  static SourceChanged? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sourceToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceToken() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get previousSourceToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set previousSourceToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPreviousSourceToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearPreviousSourceToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get atUnixMs => $_getI64(2);
  @$pb.TagNumber(3)
  set atUnixMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAtUnixMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAtUnixMs() => $_clearField(3);
}

class VolumeChanged extends $pb.GeneratedMessage {
  factory VolumeChanged({
    VolumeState? volume,
    $core.bool? external,
  }) {
    final result = create();
    if (volume != null) result.volume = volume;
    if (external != null) result.external = external;
    return result;
  }

  VolumeChanged._();

  factory VolumeChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VolumeChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VolumeChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<VolumeState>(1, _omitFieldNames ? '' : 'volume',
        subBuilder: VolumeState.create)
    ..aOB(2, _omitFieldNames ? '' : 'external')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VolumeChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VolumeChanged copyWith(void Function(VolumeChanged) updates) =>
      super.copyWith((message) => updates(message as VolumeChanged))
          as VolumeChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VolumeChanged create() => VolumeChanged._();
  @$core.override
  VolumeChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VolumeChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VolumeChanged>(create);
  static VolumeChanged? _defaultInstance;

  @$pb.TagNumber(1)
  VolumeState get volume => $_getN(0);
  @$pb.TagNumber(1)
  set volume(VolumeState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasVolume() => $_has(0);
  @$pb.TagNumber(1)
  void clearVolume() => $_clearField(1);
  @$pb.TagNumber(1)
  VolumeState ensureVolume() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get external => $_getBF(1);
  @$pb.TagNumber(2)
  set external($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExternal() => $_has(1);
  @$pb.TagNumber(2)
  void clearExternal() => $_clearField(2);
}

class PlaybackError extends $pb.GeneratedMessage {
  factory PlaybackError({
    ErrorInfo? error,
  }) {
    final result = create();
    if (error != null) result.error = error;
    return result;
  }

  PlaybackError._();

  factory PlaybackError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlaybackError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlaybackError',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOM<ErrorInfo>(1, _omitFieldNames ? '' : 'error',
        subBuilder: ErrorInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackError copyWith(void Function(PlaybackError) updates) =>
      super.copyWith((message) => updates(message as PlaybackError))
          as PlaybackError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlaybackError create() => PlaybackError._();
  @$core.override
  PlaybackError createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlaybackError getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlaybackError>(create);
  static PlaybackError? _defaultInstance;

  @$pb.TagNumber(1)
  ErrorInfo get error => $_getN(0);
  @$pb.TagNumber(1)
  set error(ErrorInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasError() => $_has(0);
  @$pb.TagNumber(1)
  void clearError() => $_clearField(1);
  @$pb.TagNumber(1)
  ErrorInfo ensureError() => $_ensure(0);
}

class DspProfile_Band extends $pb.GeneratedMessage {
  factory DspProfile_Band({
    DspProfile_Band_Type? type,
    $core.double? frequencyHz,
    $core.double? gainDb,
    $core.double? q,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (frequencyHz != null) result.frequencyHz = frequencyHz;
    if (gainDb != null) result.gainDb = gainDb;
    if (q != null) result.q = q;
    return result;
  }

  DspProfile_Band._();

  factory DspProfile_Band.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DspProfile_Band.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DspProfile.Band',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aE<DspProfile_Band_Type>(1, _omitFieldNames ? '' : 'type',
        enumValues: DspProfile_Band_Type.values)
    ..aD(2, _omitFieldNames ? '' : 'frequencyHz')
    ..aD(3, _omitFieldNames ? '' : 'gainDb')
    ..aD(4, _omitFieldNames ? '' : 'q')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DspProfile_Band clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DspProfile_Band copyWith(void Function(DspProfile_Band) updates) =>
      super.copyWith((message) => updates(message as DspProfile_Band))
          as DspProfile_Band;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DspProfile_Band create() => DspProfile_Band._();
  @$core.override
  DspProfile_Band createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DspProfile_Band getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DspProfile_Band>(create);
  static DspProfile_Band? _defaultInstance;

  @$pb.TagNumber(1)
  DspProfile_Band_Type get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(DspProfile_Band_Type value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get frequencyHz => $_getN(1);
  @$pb.TagNumber(2)
  set frequencyHz($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFrequencyHz() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrequencyHz() => $_clearField(2);

  /// Zero for a pass band.
  @$pb.TagNumber(3)
  $core.double get gainDb => $_getN(2);
  @$pb.TagNumber(3)
  set gainDb($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGainDb() => $_has(2);
  @$pb.TagNumber(3)
  void clearGainDb() => $_clearField(3);

  /// Zero for a first-order band.
  @$pb.TagNumber(4)
  $core.double get q => $_getN(3);
  @$pb.TagNumber(4)
  set q($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasQ() => $_has(3);
  @$pb.TagNumber(4)
  void clearQ() => $_clearField(4);
}

/// Version 1 carries either a shared correction or independent left/right EQ.
class DspProfile extends $pb.GeneratedMessage {
  factory DspProfile({
    $core.int? version,
    $core.String? name,
    $core.Iterable<DspProfile_Band>? shared,
    $core.Iterable<DspProfile_Band>? left,
    $core.Iterable<DspProfile_Band>? right,
  }) {
    final result = create();
    if (version != null) result.version = version;
    if (name != null) result.name = name;
    if (shared != null) result.shared.addAll(shared);
    if (left != null) result.left.addAll(left);
    if (right != null) result.right.addAll(right);
    return result;
  }

  DspProfile._();

  factory DspProfile.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DspProfile.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DspProfile',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..pPM<DspProfile_Band>(3, _omitFieldNames ? '' : 'shared',
        subBuilder: DspProfile_Band.create)
    ..pPM<DspProfile_Band>(4, _omitFieldNames ? '' : 'left',
        subBuilder: DspProfile_Band.create)
    ..pPM<DspProfile_Band>(5, _omitFieldNames ? '' : 'right',
        subBuilder: DspProfile_Band.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DspProfile clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DspProfile copyWith(void Function(DspProfile) updates) =>
      super.copyWith((message) => updates(message as DspProfile)) as DspProfile;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DspProfile create() => DspProfile._();
  @$core.override
  DspProfile createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DspProfile getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DspProfile>(create);
  static DspProfile? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<DspProfile_Band> get shared => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<DspProfile_Band> get left => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<DspProfile_Band> get right => $_getList(4);
}

/// A named convolution preset. Each WAV contains filter coefficients for one
/// distinct sample rate. Mono applies to both speakers, stereo is independent.
class FirProfile extends $pb.GeneratedMessage {
  factory FirProfile({
    $core.String? name,
    $core.Iterable<$core.List<$core.int>>? impulseWav,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (impulseWav != null) result.impulseWav.addAll(impulseWav);
    return result;
  }

  FirProfile._();

  factory FirProfile.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FirProfile.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FirProfile',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..p<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'impulseWav', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FirProfile clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FirProfile copyWith(void Function(FirProfile) updates) =>
      super.copyWith((message) => updates(message as FirProfile)) as FirProfile;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FirProfile create() => FirProfile._();
  @$core.override
  FirProfile createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FirProfile getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FirProfile>(create);
  static FirProfile? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.List<$core.int>> get impulseWav => $_getList(1);
}

class ConfigRequest extends $pb.GeneratedMessage {
  factory ConfigRequest() => create();

  ConfigRequest._();

  factory ConfigRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigRequest copyWith(void Function(ConfigRequest) updates) =>
      super.copyWith((message) => updates(message as ConfigRequest))
          as ConfigRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigRequest create() => ConfigRequest._();
  @$core.override
  ConfigRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigRequest>(create);
  static ConfigRequest? _defaultInstance;
}

class ConfigUpdate_Setting extends $pb.GeneratedMessage {
  factory ConfigUpdate_Setting({
    $core.String? path,
    $core.String? value,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (value != null) result.value = value;
    return result;
  }

  ConfigUpdate_Setting._();

  factory ConfigUpdate_Setting.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigUpdate_Setting.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigUpdate.Setting',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigUpdate_Setting clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigUpdate_Setting copyWith(void Function(ConfigUpdate_Setting) updates) =>
      super.copyWith((message) => updates(message as ConfigUpdate_Setting))
          as ConfigUpdate_Setting;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigUpdate_Setting create() => ConfigUpdate_Setting._();
  @$core.override
  ConfigUpdate_Setting createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigUpdate_Setting getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigUpdate_Setting>(create);
  static ConfigUpdate_Setting? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

class ConfigUpdate extends $pb.GeneratedMessage {
  factory ConfigUpdate({
    $core.Iterable<ConfigUpdate_Setting>? settings,
    $core.String? dspProfileUrl,
    $core.String? firProfileUrl,
  }) {
    final result = create();
    if (settings != null) result.settings.addAll(settings);
    if (dspProfileUrl != null) result.dspProfileUrl = dspProfileUrl;
    if (firProfileUrl != null) result.firProfileUrl = firProfileUrl;
    return result;
  }

  ConfigUpdate._();

  factory ConfigUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigUpdate',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..pPM<ConfigUpdate_Setting>(1, _omitFieldNames ? '' : 'settings',
        subBuilder: ConfigUpdate_Setting.create)
    ..aOS(2, _omitFieldNames ? '' : 'dspProfileUrl')
    ..aOS(3, _omitFieldNames ? '' : 'firProfileUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigUpdate copyWith(void Function(ConfigUpdate) updates) =>
      super.copyWith((message) => updates(message as ConfigUpdate))
          as ConfigUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigUpdate create() => ConfigUpdate._();
  @$core.override
  ConfigUpdate createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigUpdate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigUpdate>(create);
  static ConfigUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ConfigUpdate_Setting> get settings => $_getList(0);

  /// Where to fetch the SHA-256 selected by dsp.profile on a cache miss.
  @$pb.TagNumber(2)
  $core.String get dspProfileUrl => $_getSZ(1);
  @$pb.TagNumber(2)
  set dspProfileUrl($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDspProfileUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearDspProfileUrl() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get firProfileUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set firProfileUrl($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFirProfileUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearFirProfileUrl() => $_clearField(3);
}

/// Core -> renderer: install a published renderer release and restart into it.
///
/// Meaning fixed for every protocol version: a Core that has moved past this
/// renderer still sends it, and that is how such a renderer gets un-stranded.
/// The renderer only requests the upgrade — the install is done by root-side
/// units it cannot reach itself.
class Upgrade extends $pb.GeneratedMessage {
  factory Upgrade({
    $core.String? targetVersion,
  }) {
    final result = create();
    if (targetVersion != null) result.targetVersion = targetVersion;
    return result;
  }

  Upgrade._();

  factory Upgrade.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Upgrade.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Upgrade',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'targetVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Upgrade clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Upgrade copyWith(void Function(Upgrade) updates) =>
      super.copyWith((message) => updates(message as Upgrade)) as Upgrade;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Upgrade create() => Upgrade._();
  @$core.override
  Upgrade createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Upgrade getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Upgrade>(create);
  static Upgrade? _defaultInstance;

  /// Release to install, e.g. "0.4.0". Empty asks for the latest published.
  @$pb.TagNumber(1)
  $core.String get targetVersion => $_getSZ(0);
  @$pb.TagNumber(1)
  set targetVersion($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTargetVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetVersion() => $_clearField(1);
}

/// Whether the renderer took the request on. Success here means the install
/// was started, not that it finished: the renderer restarts into the new
/// version and re-registers, which is what actually reports the outcome.
class UpgradeResult extends $pb.GeneratedMessage {
  factory UpgradeResult({
    $core.bool? accepted,
    $core.String? detail,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (detail != null) result.detail = detail;
    return result;
  }

  UpgradeResult._();

  factory UpgradeResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpgradeResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpgradeResult',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpgradeResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpgradeResult copyWith(void Function(UpgradeResult) updates) =>
      super.copyWith((message) => updates(message as UpgradeResult))
          as UpgradeResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpgradeResult create() => UpgradeResult._();
  @$core.override
  UpgradeResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpgradeResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpgradeResult>(create);
  static UpgradeResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

class ConfigDecimalRange extends $pb.GeneratedMessage {
  factory ConfigDecimalRange({
    $core.double? min,
    $core.double? max,
    $core.double? step,
  }) {
    final result = create();
    if (min != null) result.min = min;
    if (max != null) result.max = max;
    if (step != null) result.step = step;
    return result;
  }

  ConfigDecimalRange._();

  factory ConfigDecimalRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigDecimalRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigDecimalRange',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'min')
    ..aD(2, _omitFieldNames ? '' : 'max')
    ..aD(3, _omitFieldNames ? '' : 'step')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigDecimalRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigDecimalRange copyWith(void Function(ConfigDecimalRange) updates) =>
      super.copyWith((message) => updates(message as ConfigDecimalRange))
          as ConfigDecimalRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigDecimalRange create() => ConfigDecimalRange._();
  @$core.override
  ConfigDecimalRange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigDecimalRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigDecimalRange>(create);
  static ConfigDecimalRange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get min => $_getN(0);
  @$pb.TagNumber(1)
  set min($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMin() => $_has(0);
  @$pb.TagNumber(1)
  void clearMin() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get max => $_getN(1);
  @$pb.TagNumber(2)
  set max($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMax() => $_has(1);
  @$pb.TagNumber(2)
  void clearMax() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get step => $_getN(2);
  @$pb.TagNumber(3)
  set step($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStep() => $_has(2);
  @$pb.TagNumber(3)
  void clearStep() => $_clearField(3);
}

/// What an INT field will accept.
class ConfigRange extends $pb.GeneratedMessage {
  factory ConfigRange({
    $fixnum.Int64? min,
    $fixnum.Int64? max,
    $fixnum.Int64? step,
  }) {
    final result = create();
    if (min != null) result.min = min;
    if (max != null) result.max = max;
    if (step != null) result.step = step;
    return result;
  }

  ConfigRange._();

  factory ConfigRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigRange',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'min')
    ..aInt64(2, _omitFieldNames ? '' : 'max')
    ..aInt64(3, _omitFieldNames ? '' : 'step')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigRange copyWith(void Function(ConfigRange) updates) =>
      super.copyWith((message) => updates(message as ConfigRange))
          as ConfigRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigRange create() => ConfigRange._();
  @$core.override
  ConfigRange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigRange>(create);
  static ConfigRange? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get min => $_getI64(0);
  @$pb.TagNumber(1)
  set min($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMin() => $_has(0);
  @$pb.TagNumber(1)
  void clearMin() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get max => $_getI64(1);
  @$pb.TagNumber(2)
  set max($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMax() => $_has(1);
  @$pb.TagNumber(2)
  void clearMax() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get step => $_getI64(2);
  @$pb.TagNumber(3)
  set step($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStep() => $_has(2);
  @$pb.TagNumber(3)
  void clearStep() => $_clearField(3);
}

/// One choice for an ENUM field. The device list is this: `value` is whatever
/// the renderer opens (an ALSA PCM name, a WASAPI endpoint id), opaque to the
/// Core, and `label` is what the user picks from.
class ConfigOption extends $pb.GeneratedMessage {
  factory ConfigOption({
    $core.String? value,
    $core.String? label,
    $core.String? description,
  }) {
    final result = create();
    if (value != null) result.value = value;
    if (label != null) result.label = label;
    if (description != null) result.description = description;
    return result;
  }

  ConfigOption._();

  factory ConfigOption.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigOption.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigOption',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'value')
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigOption clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigOption copyWith(void Function(ConfigOption) updates) =>
      super.copyWith((message) => updates(message as ConfigOption))
          as ConfigOption;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigOption create() => ConfigOption._();
  @$core.override
  ConfigOption createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigOption getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigOption>(create);
  static ConfigOption? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);
}

class ConfigField extends $pb.GeneratedMessage {
  factory ConfigField({
    $core.String? path,
    $core.String? title,
    $core.String? description,
    ConfigFieldType? type,
    $core.String? value,
    $core.String? defaultValue,
    $core.Iterable<ConfigOption>? options,
    ApplyCost? apply,
    $core.bool? readOnly,
    ConfigImportance? importance,
    ConfigRange? range,
    $core.String? unit,
    ConfigWidget? widget,
    $core.String? helpDetails,
    ConfigDecimalRange? decimalRange,
    $core.bool? supportsFirImport,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (title != null) result.title = title;
    if (description != null) result.description = description;
    if (type != null) result.type = type;
    if (value != null) result.value = value;
    if (defaultValue != null) result.defaultValue = defaultValue;
    if (options != null) result.options.addAll(options);
    if (apply != null) result.apply = apply;
    if (readOnly != null) result.readOnly = readOnly;
    if (importance != null) result.importance = importance;
    if (range != null) result.range = range;
    if (unit != null) result.unit = unit;
    if (widget != null) result.widget = widget;
    if (helpDetails != null) result.helpDetails = helpDetails;
    if (decimalRange != null) result.decimalRange = decimalRange;
    if (supportsFirImport != null) result.supportsFirImport = supportsFirImport;
    return result;
  }

  ConfigField._();

  factory ConfigField.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigField.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigField',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aE<ConfigFieldType>(4, _omitFieldNames ? '' : 'type',
        enumValues: ConfigFieldType.values)
    ..aOS(5, _omitFieldNames ? '' : 'value')
    ..aOS(6, _omitFieldNames ? '' : 'defaultValue')
    ..pPM<ConfigOption>(7, _omitFieldNames ? '' : 'options',
        subBuilder: ConfigOption.create)
    ..aE<ApplyCost>(8, _omitFieldNames ? '' : 'apply',
        enumValues: ApplyCost.values)
    ..aOB(9, _omitFieldNames ? '' : 'readOnly')
    ..aE<ConfigImportance>(10, _omitFieldNames ? '' : 'importance',
        enumValues: ConfigImportance.values)
    ..aOM<ConfigRange>(11, _omitFieldNames ? '' : 'range',
        subBuilder: ConfigRange.create)
    ..aOS(12, _omitFieldNames ? '' : 'unit')
    ..aE<ConfigWidget>(13, _omitFieldNames ? '' : 'widget',
        enumValues: ConfigWidget.values)
    ..aOS(14, _omitFieldNames ? '' : 'helpDetails')
    ..aOM<ConfigDecimalRange>(15, _omitFieldNames ? '' : 'decimalRange',
        subBuilder: ConfigDecimalRange.create)
    ..aOB(16, _omitFieldNames ? '' : 'supportsFirImport')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigField clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigField copyWith(void Function(ConfigField) updates) =>
      super.copyWith((message) => updates(message as ConfigField))
          as ConfigField;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigField create() => ConfigField._();
  @$core.override
  ConfigField createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigField getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigField>(create);
  static ConfigField? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);

  @$pb.TagNumber(4)
  ConfigFieldType get type => $_getN(3);
  @$pb.TagNumber(4)
  set type(ConfigFieldType value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasType() => $_has(3);
  @$pb.TagNumber(4)
  void clearType() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get value => $_getSZ(4);
  @$pb.TagNumber(5)
  set value($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasValue() => $_has(4);
  @$pb.TagNumber(5)
  void clearValue() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get defaultValue => $_getSZ(5);
  @$pb.TagNumber(6)
  set defaultValue($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDefaultValue() => $_has(5);
  @$pb.TagNumber(6)
  void clearDefaultValue() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<ConfigOption> get options => $_getList(6);

  @$pb.TagNumber(8)
  ApplyCost get apply => $_getN(7);
  @$pb.TagNumber(8)
  set apply(ApplyCost value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasApply() => $_has(7);
  @$pb.TagNumber(8)
  void clearApply() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get readOnly => $_getBF(8);
  @$pb.TagNumber(9)
  set readOnly($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasReadOnly() => $_has(8);
  @$pb.TagNumber(9)
  void clearReadOnly() => $_clearField(9);

  @$pb.TagNumber(10)
  ConfigImportance get importance => $_getN(9);
  @$pb.TagNumber(10)
  set importance(ConfigImportance value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasImportance() => $_has(9);
  @$pb.TagNumber(10)
  void clearImportance() => $_clearField(10);

  @$pb.TagNumber(11)
  ConfigRange get range => $_getN(10);
  @$pb.TagNumber(11)
  set range(ConfigRange value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasRange() => $_has(10);
  @$pb.TagNumber(11)
  void clearRange() => $_clearField(11);
  @$pb.TagNumber(11)
  ConfigRange ensureRange() => $_ensure(10);

  @$pb.TagNumber(12)
  $core.String get unit => $_getSZ(11);
  @$pb.TagNumber(12)
  set unit($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasUnit() => $_has(11);
  @$pb.TagNumber(12)
  void clearUnit() => $_clearField(12);

  @$pb.TagNumber(13)
  ConfigWidget get widget => $_getN(12);
  @$pb.TagNumber(13)
  set widget(ConfigWidget value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasWidget() => $_has(12);
  @$pb.TagNumber(13)
  void clearWidget() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get helpDetails => $_getSZ(13);
  @$pb.TagNumber(14)
  set helpDetails($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasHelpDetails() => $_has(13);
  @$pb.TagNumber(14)
  void clearHelpDetails() => $_clearField(14);

  @$pb.TagNumber(15)
  ConfigDecimalRange get decimalRange => $_getN(14);
  @$pb.TagNumber(15)
  set decimalRange(ConfigDecimalRange value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasDecimalRange() => $_has(14);
  @$pb.TagNumber(15)
  void clearDecimalRange() => $_clearField(15);
  @$pb.TagNumber(15)
  ConfigDecimalRange ensureDecimalRange() => $_ensure(14);

  @$pb.TagNumber(16)
  $core.bool get supportsFirImport => $_getBF(15);
  @$pb.TagNumber(16)
  set supportsFirImport($core.bool value) => $_setBool(15, value);
  @$pb.TagNumber(16)
  $core.bool hasSupportsFirImport() => $_has(15);
  @$pb.TagNumber(16)
  void clearSupportsFirImport() => $_clearField(16);
}

class ConfigSection extends $pb.GeneratedMessage {
  factory ConfigSection({
    $core.String? path,
    $core.String? title,
    $core.String? description,
    $core.Iterable<ConfigField>? fields,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (title != null) result.title = title;
    if (description != null) result.description = description;
    if (fields != null) result.fields.addAll(fields);
    return result;
  }

  ConfigSection._();

  factory ConfigSection.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigSection.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigSection',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..pPM<ConfigField>(4, _omitFieldNames ? '' : 'fields',
        subBuilder: ConfigField.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigSection clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigSection copyWith(void Function(ConfigSection) updates) =>
      super.copyWith((message) => updates(message as ConfigSection))
          as ConfigSection;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigSection create() => ConfigSection._();
  @$core.override
  ConfigSection createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigSection getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigSection>(create);
  static ConfigSection? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<ConfigField> get fields => $_getList(3);
}

/// Schema and values together: the Core renders settings from one round trip,
/// and the options are as fresh as the moment it asked.
class ConfigSnapshot extends $pb.GeneratedMessage {
  factory ConfigSnapshot({
    $core.String? configVersion,
    $core.Iterable<ConfigSection>? sections,
  }) {
    final result = create();
    if (configVersion != null) result.configVersion = configVersion;
    if (sections != null) result.sections.addAll(sections);
    return result;
  }

  ConfigSnapshot._();

  factory ConfigSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigSnapshot',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'configVersion')
    ..pPM<ConfigSection>(2, _omitFieldNames ? '' : 'sections',
        subBuilder: ConfigSection.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigSnapshot copyWith(void Function(ConfigSnapshot) updates) =>
      super.copyWith((message) => updates(message as ConfigSnapshot))
          as ConfigSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigSnapshot create() => ConfigSnapshot._();
  @$core.override
  ConfigSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigSnapshot>(create);
  static ConfigSnapshot? _defaultInstance;

  /// Changes whenever the shape or the options change — a device appearing, a
  /// driver switch revealing different fields. Not a write precondition; it
  /// tells a Core whether the page it is holding is still the right shape.
  @$pb.TagNumber(1)
  $core.String get configVersion => $_getSZ(0);
  @$pb.TagNumber(1)
  set configVersion($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfigVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfigVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ConfigSection> get sections => $_getList(1);
}

class ConfigResult_Outcome extends $pb.GeneratedMessage {
  factory ConfigResult_Outcome({
    $core.String? path,
    $core.bool? applied,
    $core.String? value,
    $core.String? error,
  }) {
    final result = create();
    if (path != null) result.path = path;
    if (applied != null) result.applied = applied;
    if (value != null) result.value = value;
    if (error != null) result.error = error;
    return result;
  }

  ConfigResult_Outcome._();

  factory ConfigResult_Outcome.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigResult_Outcome.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigResult.Outcome',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOB(2, _omitFieldNames ? '' : 'applied')
    ..aOS(3, _omitFieldNames ? '' : 'value')
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigResult_Outcome clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigResult_Outcome copyWith(void Function(ConfigResult_Outcome) updates) =>
      super.copyWith((message) => updates(message as ConfigResult_Outcome))
          as ConfigResult_Outcome;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigResult_Outcome create() => ConfigResult_Outcome._();
  @$core.override
  ConfigResult_Outcome createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigResult_Outcome getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigResult_Outcome>(create);
  static ConfigResult_Outcome? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get applied => $_getBF(1);
  @$pb.TagNumber(2)
  set applied($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasApplied() => $_has(1);
  @$pb.TagNumber(2)
  void clearApplied() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get value => $_getSZ(2);
  @$pb.TagNumber(3)
  set value($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearValue() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get error => $_getSZ(3);
  @$pb.TagNumber(4)
  set error($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
}

class ConfigResult extends $pb.GeneratedMessage {
  factory ConfigResult({
    $core.Iterable<ConfigResult_Outcome>? outcomes,
    ApplyCost? effect,
    $core.String? configVersion,
  }) {
    final result = create();
    if (outcomes != null) result.outcomes.addAll(outcomes);
    if (effect != null) result.effect = effect;
    if (configVersion != null) result.configVersion = configVersion;
    return result;
  }

  ConfigResult._();

  factory ConfigResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigResult',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..pPM<ConfigResult_Outcome>(1, _omitFieldNames ? '' : 'outcomes',
        subBuilder: ConfigResult_Outcome.create)
    ..aE<ApplyCost>(2, _omitFieldNames ? '' : 'effect',
        enumValues: ApplyCost.values)
    ..aOS(3, _omitFieldNames ? '' : 'configVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigResult copyWith(void Function(ConfigResult) updates) =>
      super.copyWith((message) => updates(message as ConfigResult))
          as ConfigResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigResult create() => ConfigResult._();
  @$core.override
  ConfigResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigResult>(create);
  static ConfigResult? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ConfigResult_Outcome> get outcomes => $_getList(0);

  /// The worst cost among the settings that were actually applied: what just
  /// happened, not what might.
  @$pb.TagNumber(2)
  ApplyCost get effect => $_getN(1);
  @$pb.TagNumber(2)
  set effect(ApplyCost value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEffect() => $_has(1);
  @$pb.TagNumber(2)
  void clearEffect() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get configVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set configVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfigVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfigVersion() => $_clearField(3);
}

class Goodbye extends $pb.GeneratedMessage {
  factory Goodbye({
    Goodbye_Reason? reason,
    $core.String? detail,
  }) {
    final result = create();
    if (reason != null) result.reason = reason;
    if (detail != null) result.detail = detail;
    return result;
  }

  Goodbye._();

  factory Goodbye.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Goodbye.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Goodbye',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'kalinka.renderer.v1'),
      createEmptyInstance: create)
    ..aE<Goodbye_Reason>(1, _omitFieldNames ? '' : 'reason',
        enumValues: Goodbye_Reason.values)
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Goodbye clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Goodbye copyWith(void Function(Goodbye) updates) =>
      super.copyWith((message) => updates(message as Goodbye)) as Goodbye;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Goodbye create() => Goodbye._();
  @$core.override
  Goodbye createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Goodbye getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Goodbye>(create);
  static Goodbye? _defaultInstance;

  @$pb.TagNumber(1)
  Goodbye_Reason get reason => $_getN(0);
  @$pb.TagNumber(1)
  set reason(Goodbye_Reason value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
