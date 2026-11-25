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

import 'package:protobuf/protobuf.dart' as $pb;

class RendererKind extends $pb.ProtobufEnum {
  static const RendererKind RENDERER_KIND_UNSPECIFIED =
      RendererKind._(0, _omitEnumNames ? '' : 'RENDERER_KIND_UNSPECIFIED');
  static const RendererKind RENDERER_KIND_NATIVE =
      RendererKind._(1, _omitEnumNames ? '' : 'RENDERER_KIND_NATIVE');
  static const RendererKind RENDERER_KIND_WEB =
      RendererKind._(2, _omitEnumNames ? '' : 'RENDERER_KIND_WEB');

  static const $core.List<RendererKind> values = <RendererKind>[
    RENDERER_KIND_UNSPECIFIED,
    RENDERER_KIND_NATIVE,
    RENDERER_KIND_WEB,
  ];

  static final $core.List<RendererKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static RendererKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RendererKind._(super.value, super.name);
}

/// Ordinals are protocol constants and never mirror the native enums — native
/// AudioGraphNodeState::ERROR is -1, which proto3 cannot express anyway.
class PlaybackState extends $pb.ProtobufEnum {
  static const PlaybackState PLAYBACK_STATE_UNSPECIFIED =
      PlaybackState._(0, _omitEnumNames ? '' : 'PLAYBACK_STATE_UNSPECIFIED');
  static const PlaybackState PLAYBACK_STATE_STOPPED =
      PlaybackState._(1, _omitEnumNames ? '' : 'PLAYBACK_STATE_STOPPED');
  static const PlaybackState PLAYBACK_STATE_PREPARING =
      PlaybackState._(2, _omitEnumNames ? '' : 'PLAYBACK_STATE_PREPARING');
  static const PlaybackState PLAYBACK_STATE_PLAYING =
      PlaybackState._(3, _omitEnumNames ? '' : 'PLAYBACK_STATE_PLAYING');
  static const PlaybackState PLAYBACK_STATE_PAUSED =
      PlaybackState._(4, _omitEnumNames ? '' : 'PLAYBACK_STATE_PAUSED');
  static const PlaybackState PLAYBACK_STATE_FINISHED =
      PlaybackState._(5, _omitEnumNames ? '' : 'PLAYBACK_STATE_FINISHED');
  static const PlaybackState PLAYBACK_STATE_ERROR =
      PlaybackState._(6, _omitEnumNames ? '' : 'PLAYBACK_STATE_ERROR');

  static const $core.List<PlaybackState> values = <PlaybackState>[
    PLAYBACK_STATE_UNSPECIFIED,
    PLAYBACK_STATE_STOPPED,
    PLAYBACK_STATE_PREPARING,
    PLAYBACK_STATE_PLAYING,
    PLAYBACK_STATE_PAUSED,
    PLAYBACK_STATE_FINISHED,
    PLAYBACK_STATE_ERROR,
  ];

  static final $core.List<PlaybackState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static PlaybackState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PlaybackState._(super.value, super.name);
}

class ErrorSource extends $pb.ProtobufEnum {
  static const ErrorSource ERROR_SOURCE_UNSPECIFIED =
      ErrorSource._(0, _omitEnumNames ? '' : 'ERROR_SOURCE_UNSPECIFIED');
  static const ErrorSource ERROR_SOURCE_NONE =
      ErrorSource._(1, _omitEnumNames ? '' : 'ERROR_SOURCE_NONE');
  static const ErrorSource ERROR_SOURCE_HTTP_STREAM =
      ErrorSource._(2, _omitEnumNames ? '' : 'ERROR_SOURCE_HTTP_STREAM');
  static const ErrorSource ERROR_SOURCE_AUDIO_OUTPUT =
      ErrorSource._(3, _omitEnumNames ? '' : 'ERROR_SOURCE_AUDIO_OUTPUT');
  static const ErrorSource ERROR_SOURCE_DECODER =
      ErrorSource._(4, _omitEnumNames ? '' : 'ERROR_SOURCE_DECODER');
  static const ErrorSource ERROR_SOURCE_RENDERER_INTERNAL =
      ErrorSource._(5, _omitEnumNames ? '' : 'ERROR_SOURCE_RENDERER_INTERNAL');

  static const $core.List<ErrorSource> values = <ErrorSource>[
    ERROR_SOURCE_UNSPECIFIED,
    ERROR_SOURCE_NONE,
    ERROR_SOURCE_HTTP_STREAM,
    ERROR_SOURCE_AUDIO_OUTPUT,
    ERROR_SOURCE_DECODER,
    ERROR_SOURCE_RENDERER_INTERNAL,
  ];

  static final $core.List<ErrorSource?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ErrorSource? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ErrorSource._(super.value, super.name);
}

/// How the renderer holds the output device. A renderer can only say what it
/// opened: SHARED is not proof that anything alters the samples, only that
/// nothing rules it out.
class DeviceAccess extends $pb.ProtobufEnum {
  static const DeviceAccess DEVICE_ACCESS_UNSPECIFIED =
      DeviceAccess._(0, _omitEnumNames ? '' : 'DEVICE_ACCESS_UNSPECIFIED');
  static const DeviceAccess DEVICE_ACCESS_EXCLUSIVE =
      DeviceAccess._(1, _omitEnumNames ? '' : 'DEVICE_ACCESS_EXCLUSIVE');
  static const DeviceAccess DEVICE_ACCESS_SHARED =
      DeviceAccess._(2, _omitEnumNames ? '' : 'DEVICE_ACCESS_SHARED');

  static const $core.List<DeviceAccess> values = <DeviceAccess>[
    DEVICE_ACCESS_UNSPECIFIED,
    DEVICE_ACCESS_EXCLUSIVE,
    DEVICE_ACCESS_SHARED,
  ];

  static final $core.List<DeviceAccess?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static DeviceAccess? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DeviceAccess._(super.value, super.name);
}

class VolumeBackend extends $pb.ProtobufEnum {
  static const VolumeBackend VOLUME_BACKEND_UNSPECIFIED =
      VolumeBackend._(0, _omitEnumNames ? '' : 'VOLUME_BACKEND_UNSPECIFIED');
  static const VolumeBackend VOLUME_BACKEND_NONE =
      VolumeBackend._(1, _omitEnumNames ? '' : 'VOLUME_BACKEND_NONE');
  static const VolumeBackend VOLUME_BACKEND_HARDWARE =
      VolumeBackend._(2, _omitEnumNames ? '' : 'VOLUME_BACKEND_HARDWARE');
  static const VolumeBackend VOLUME_BACKEND_SOFTWARE =
      VolumeBackend._(3, _omitEnumNames ? '' : 'VOLUME_BACKEND_SOFTWARE');

  static const $core.List<VolumeBackend> values = <VolumeBackend>[
    VOLUME_BACKEND_UNSPECIFIED,
    VOLUME_BACKEND_NONE,
    VOLUME_BACKEND_HARDWARE,
    VOLUME_BACKEND_SOFTWARE,
  ];

  static final $core.List<VolumeBackend?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static VolumeBackend? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VolumeBackend._(super.value, super.name);
}

/// Names a command without carrying it; used by CommandRejected.
class ControlKind extends $pb.ProtobufEnum {
  static const ControlKind CONTROL_KIND_UNSPECIFIED =
      ControlKind._(0, _omitEnumNames ? '' : 'CONTROL_KIND_UNSPECIFIED');
  static const ControlKind CONTROL_KIND_SET_SOURCE =
      ControlKind._(1, _omitEnumNames ? '' : 'CONTROL_KIND_SET_SOURCE');
  static const ControlKind CONTROL_KIND_ENQUEUE_SOURCE =
      ControlKind._(2, _omitEnumNames ? '' : 'CONTROL_KIND_ENQUEUE_SOURCE');
  static const ControlKind CONTROL_KIND_REMOVE_SOURCE =
      ControlKind._(3, _omitEnumNames ? '' : 'CONTROL_KIND_REMOVE_SOURCE');
  static const ControlKind CONTROL_KIND_CLEAR_QUEUE =
      ControlKind._(4, _omitEnumNames ? '' : 'CONTROL_KIND_CLEAR_QUEUE');
  static const ControlKind CONTROL_KIND_RESUME =
      ControlKind._(5, _omitEnumNames ? '' : 'CONTROL_KIND_RESUME');
  static const ControlKind CONTROL_KIND_PAUSE =
      ControlKind._(6, _omitEnumNames ? '' : 'CONTROL_KIND_PAUSE');
  static const ControlKind CONTROL_KIND_STOP =
      ControlKind._(7, _omitEnumNames ? '' : 'CONTROL_KIND_STOP');
  static const ControlKind CONTROL_KIND_SET_VOLUME =
      ControlKind._(8, _omitEnumNames ? '' : 'CONTROL_KIND_SET_VOLUME');
  static const ControlKind CONTROL_KIND_REQUEST_SNAPSHOT =
      ControlKind._(9, _omitEnumNames ? '' : 'CONTROL_KIND_REQUEST_SNAPSHOT');

  /// 10 / 11 held for refresh_devices / select_output_device, now configuration;
  /// 12 for release_control, part of the superseded ownership lease.
  static const ControlKind CONTROL_KIND_SEEK =
      ControlKind._(13, _omitEnumNames ? '' : 'CONTROL_KIND_SEEK');

  static const $core.List<ControlKind> values = <ControlKind>[
    CONTROL_KIND_UNSPECIFIED,
    CONTROL_KIND_SET_SOURCE,
    CONTROL_KIND_ENQUEUE_SOURCE,
    CONTROL_KIND_REMOVE_SOURCE,
    CONTROL_KIND_CLEAR_QUEUE,
    CONTROL_KIND_RESUME,
    CONTROL_KIND_PAUSE,
    CONTROL_KIND_STOP,
    CONTROL_KIND_SET_VOLUME,
    CONTROL_KIND_REQUEST_SNAPSHOT,
    CONTROL_KIND_SEEK,
  ];

  static final $core.List<ControlKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 13);
  static ControlKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ControlKind._(super.value, super.name);
}

class ConfigFieldType extends $pb.ProtobufEnum {
  static const ConfigFieldType CONFIG_FIELD_TYPE_UNSPECIFIED =
      ConfigFieldType._(
          0, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_UNSPECIFIED');
  static const ConfigFieldType CONFIG_FIELD_TYPE_STRING =
      ConfigFieldType._(1, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_STRING');
  static const ConfigFieldType CONFIG_FIELD_TYPE_INT =
      ConfigFieldType._(2, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_INT');
  static const ConfigFieldType CONFIG_FIELD_TYPE_BOOL =
      ConfigFieldType._(3, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_BOOL');
  static const ConfigFieldType CONFIG_FIELD_TYPE_ENUM =
      ConfigFieldType._(4, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_ENUM');
  static const ConfigFieldType CONFIG_FIELD_TYPE_TRIGGER =
      ConfigFieldType._(5, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_TRIGGER');
  static const ConfigFieldType CONFIG_FIELD_TYPE_DECIMAL =
      ConfigFieldType._(6, _omitEnumNames ? '' : 'CONFIG_FIELD_TYPE_DECIMAL');

  static const $core.List<ConfigFieldType> values = <ConfigFieldType>[
    CONFIG_FIELD_TYPE_UNSPECIFIED,
    CONFIG_FIELD_TYPE_STRING,
    CONFIG_FIELD_TYPE_INT,
    CONFIG_FIELD_TYPE_BOOL,
    CONFIG_FIELD_TYPE_ENUM,
    CONFIG_FIELD_TYPE_TRIGGER,
    CONFIG_FIELD_TYPE_DECIMAL,
  ];

  static final $core.List<ConfigFieldType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static ConfigFieldType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConfigFieldType._(super.value, super.name);
}

/// What it costs to apply a field, so the UI can warn before the user commits.
class ApplyCost extends $pb.ProtobufEnum {
  static const ApplyCost APPLY_COST_UNSPECIFIED =
      ApplyCost._(0, _omitEnumNames ? '' : 'APPLY_COST_UNSPECIFIED');
  static const ApplyCost APPLY_COST_INSTANT =
      ApplyCost._(1, _omitEnumNames ? '' : 'APPLY_COST_INSTANT');
  static const ApplyCost APPLY_COST_INTERRUPTS_PLAYBACK =
      ApplyCost._(2, _omitEnumNames ? '' : 'APPLY_COST_INTERRUPTS_PLAYBACK');
  static const ApplyCost APPLY_COST_RESTART_REQUIRED =
      ApplyCost._(3, _omitEnumNames ? '' : 'APPLY_COST_RESTART_REQUIRED');

  static const $core.List<ApplyCost> values = <ApplyCost>[
    APPLY_COST_UNSPECIFIED,
    APPLY_COST_INSTANT,
    APPLY_COST_INTERRUPTS_PLAYBACK,
    APPLY_COST_RESTART_REQUIRED,
  ];

  static final $core.List<ApplyCost?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ApplyCost? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ApplyCost._(super.value, super.name);
}

/// Which page a field belongs on. The renderer decides: it is the one that
/// knows which of its settings a user is meant to reach for and which are there
/// for a card that misbehaves. A renderer from before the tier says nothing,
/// and what it declares stays where it has always been shown.
class ConfigImportance extends $pb.ProtobufEnum {
  static const ConfigImportance CONFIG_IMPORTANCE_UNSPECIFIED =
      ConfigImportance._(
          0, _omitEnumNames ? '' : 'CONFIG_IMPORTANCE_UNSPECIFIED');
  static const ConfigImportance CONFIG_IMPORTANCE_SIMPLE =
      ConfigImportance._(1, _omitEnumNames ? '' : 'CONFIG_IMPORTANCE_SIMPLE');
  static const ConfigImportance CONFIG_IMPORTANCE_EXPERT =
      ConfigImportance._(2, _omitEnumNames ? '' : 'CONFIG_IMPORTANCE_EXPERT');

  static const $core.List<ConfigImportance> values = <ConfigImportance>[
    CONFIG_IMPORTANCE_UNSPECIFIED,
    CONFIG_IMPORTANCE_SIMPLE,
    CONFIG_IMPORTANCE_EXPERT,
  ];

  static final $core.List<ConfigImportance?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ConfigImportance? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConfigImportance._(super.value, super.name);
}

/// How an INT field is best edited. The renderer decides: bounds alone do not
/// say, since a byte count spans orders of magnitude and is typed, while a
/// latency in milliseconds is dragged.
class ConfigWidget extends $pb.ProtobufEnum {
  static const ConfigWidget CONFIG_WIDGET_UNSPECIFIED =
      ConfigWidget._(0, _omitEnumNames ? '' : 'CONFIG_WIDGET_UNSPECIFIED');
  static const ConfigWidget CONFIG_WIDGET_SLIDER =
      ConfigWidget._(1, _omitEnumNames ? '' : 'CONFIG_WIDGET_SLIDER');
  static const ConfigWidget CONFIG_WIDGET_NUMBER =
      ConfigWidget._(2, _omitEnumNames ? '' : 'CONFIG_WIDGET_NUMBER');

  static const $core.List<ConfigWidget> values = <ConfigWidget>[
    CONFIG_WIDGET_UNSPECIFIED,
    CONFIG_WIDGET_SLIDER,
    CONFIG_WIDGET_NUMBER,
  ];

  static final $core.List<ConfigWidget?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ConfigWidget? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConfigWidget._(super.value, super.name);
}

class SessionOpenResult_Error extends $pb.ProtobufEnum {
  static const SessionOpenResult_Error ERROR_UNSPECIFIED =
      SessionOpenResult_Error._(0, _omitEnumNames ? '' : 'ERROR_UNSPECIFIED');
  static const SessionOpenResult_Error ERROR_BUSY =
      SessionOpenResult_Error._(1, _omitEnumNames ? '' : 'ERROR_BUSY');
  static const SessionOpenResult_Error ERROR_INTERNAL =
      SessionOpenResult_Error._(2, _omitEnumNames ? '' : 'ERROR_INTERNAL');

  static const $core.List<SessionOpenResult_Error> values =
      <SessionOpenResult_Error>[
    ERROR_UNSPECIFIED,
    ERROR_BUSY,
    ERROR_INTERNAL,
  ];

  static final $core.List<SessionOpenResult_Error?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static SessionOpenResult_Error? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SessionOpenResult_Error._(super.value, super.name);
}

class SessionClose_Reason extends $pb.ProtobufEnum {
  static const SessionClose_Reason REASON_UNSPECIFIED =
      SessionClose_Reason._(0, _omitEnumNames ? '' : 'REASON_UNSPECIFIED');
  static const SessionClose_Reason REASON_CLOSED_BY_SERVER =
      SessionClose_Reason._(1, _omitEnumNames ? '' : 'REASON_CLOSED_BY_SERVER');
  static const SessionClose_Reason REASON_STALE =
      SessionClose_Reason._(2, _omitEnumNames ? '' : 'REASON_STALE');

  static const $core.List<SessionClose_Reason> values = <SessionClose_Reason>[
    REASON_UNSPECIFIED,
    REASON_CLOSED_BY_SERVER,
    REASON_STALE,
  ];

  static final $core.List<SessionClose_Reason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static SessionClose_Reason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SessionClose_Reason._(super.value, super.name);
}

class SessionClosed_Reason extends $pb.ProtobufEnum {
  static const SessionClosed_Reason REASON_UNSPECIFIED =
      SessionClosed_Reason._(0, _omitEnumNames ? '' : 'REASON_UNSPECIFIED');
  static const SessionClosed_Reason REASON_ACK =
      SessionClosed_Reason._(1, _omitEnumNames ? '' : 'REASON_ACK');
  static const SessionClosed_Reason REASON_RENDERER_ERROR =
      SessionClosed_Reason._(2, _omitEnumNames ? '' : 'REASON_RENDERER_ERROR');

  static const $core.List<SessionClosed_Reason> values = <SessionClosed_Reason>[
    REASON_UNSPECIFIED,
    REASON_ACK,
    REASON_RENDERER_ERROR,
  ];

  static final $core.List<SessionClosed_Reason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static SessionClosed_Reason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SessionClosed_Reason._(super.value, super.name);
}

class DspProfile_Band_Type extends $pb.ProtobufEnum {
  static const DspProfile_Band_Type UNSPECIFIED =
      DspProfile_Band_Type._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const DspProfile_Band_Type PEAK =
      DspProfile_Band_Type._(1, _omitEnumNames ? '' : 'PEAK');
  static const DspProfile_Band_Type LOW_SHELF =
      DspProfile_Band_Type._(2, _omitEnumNames ? '' : 'LOW_SHELF');
  static const DspProfile_Band_Type HIGH_SHELF =
      DspProfile_Band_Type._(3, _omitEnumNames ? '' : 'HIGH_SHELF');

  /// Second order, 12 dB per octave, shaped by frequency and Q alone.
  static const DspProfile_Band_Type HIGH_PASS =
      DspProfile_Band_Type._(4, _omitEnumNames ? '' : 'HIGH_PASS');
  static const DspProfile_Band_Type LOW_PASS =
      DspProfile_Band_Type._(5, _omitEnumNames ? '' : 'LOW_PASS');

  /// 6 dB per octave, shaped by frequency alone.
  static const DspProfile_Band_Type FIRST_ORDER_HIGH_PASS =
      DspProfile_Band_Type._(6, _omitEnumNames ? '' : 'FIRST_ORDER_HIGH_PASS');
  static const DspProfile_Band_Type FIRST_ORDER_LOW_PASS =
      DspProfile_Band_Type._(7, _omitEnumNames ? '' : 'FIRST_ORDER_LOW_PASS');

  static const $core.List<DspProfile_Band_Type> values = <DspProfile_Band_Type>[
    UNSPECIFIED,
    PEAK,
    LOW_SHELF,
    HIGH_SHELF,
    HIGH_PASS,
    LOW_PASS,
    FIRST_ORDER_HIGH_PASS,
    FIRST_ORDER_LOW_PASS,
  ];

  static final $core.List<DspProfile_Band_Type?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static DspProfile_Band_Type? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DspProfile_Band_Type._(super.value, super.name);
}

class Goodbye_Reason extends $pb.ProtobufEnum {
  static const Goodbye_Reason REASON_UNSPECIFIED =
      Goodbye_Reason._(0, _omitEnumNames ? '' : 'REASON_UNSPECIFIED');
  static const Goodbye_Reason REASON_SHUTDOWN =
      Goodbye_Reason._(1, _omitEnumNames ? '' : 'REASON_SHUTDOWN');
  static const Goodbye_Reason REASON_VERSION_UNSUPPORTED =
      Goodbye_Reason._(2, _omitEnumNames ? '' : 'REASON_VERSION_UNSUPPORTED');
  static const Goodbye_Reason REASON_MALFORMED =
      Goodbye_Reason._(3, _omitEnumNames ? '' : 'REASON_MALFORMED');
  static const Goodbye_Reason REASON_REPLACED =
      Goodbye_Reason._(4, _omitEnumNames ? '' : 'REASON_REPLACED');
  static const Goodbye_Reason REASON_REJECTED =
      Goodbye_Reason._(5, _omitEnumNames ? '' : 'REASON_REJECTED');

  static const $core.List<Goodbye_Reason> values = <Goodbye_Reason>[
    REASON_UNSPECIFIED,
    REASON_SHUTDOWN,
    REASON_VERSION_UNSUPPORTED,
    REASON_MALFORMED,
    REASON_REPLACED,
    REASON_REJECTED,
  ];

  static final $core.List<Goodbye_Reason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static Goodbye_Reason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Goodbye_Reason._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
