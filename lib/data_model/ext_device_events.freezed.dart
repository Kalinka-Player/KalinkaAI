// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ext_device_events.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExtDeviceEvent {

 int get seq;
/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtDeviceEventCopyWith<ExtDeviceEvent> get copyWith => _$ExtDeviceEventCopyWithImpl<ExtDeviceEvent>(this as ExtDeviceEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ExtDeviceEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtDeviceEvent&&(identical(other.seq, _this.seq) || other.seq == _this.seq));
}


@override
int get hashCode {
  final _this = this as ExtDeviceEvent;
  return Object.hash(runtimeType,_this.seq);
}

@override
String toString() {
  final _this = this as ExtDeviceEvent;
  return 'ExtDeviceEvent(seq: ${_this.seq})';
}


}

/// @nodoc
abstract mixin class $ExtDeviceEventCopyWith<$Res>  {
  factory $ExtDeviceEventCopyWith(ExtDeviceEvent value, $Res Function(ExtDeviceEvent) _then) = _$ExtDeviceEventCopyWithImpl;
@useResult
$Res call({
 int seq
});




}
/// @nodoc
class _$ExtDeviceEventCopyWithImpl<$Res>
    implements $ExtDeviceEventCopyWith<$Res> {
  _$ExtDeviceEventCopyWithImpl(this._self, this._then);

  final ExtDeviceEvent _self;
  final $Res Function(ExtDeviceEvent) _then;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? seq = null,}) {
  return _then(_self.copyWith(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ExtDeviceEvent].
extension ExtDeviceEventPatterns on ExtDeviceEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DevicePowerStateChangedEvent value)?  devicePowerStateChanged,TResult Function( VolumeChangedEvent value)?  volumeChanged,TResult Function( ExtDeviceReplayEvent value)?  replayEvent,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DevicePowerStateChangedEvent() when devicePowerStateChanged != null:
return devicePowerStateChanged(_that);case VolumeChangedEvent() when volumeChanged != null:
return volumeChanged(_that);case ExtDeviceReplayEvent() when replayEvent != null:
return replayEvent(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DevicePowerStateChangedEvent value)  devicePowerStateChanged,required TResult Function( VolumeChangedEvent value)  volumeChanged,required TResult Function( ExtDeviceReplayEvent value)  replayEvent,}){
final _that = this;
switch (_that) {
case DevicePowerStateChangedEvent():
return devicePowerStateChanged(_that);case VolumeChangedEvent():
return volumeChanged(_that);case ExtDeviceReplayEvent():
return replayEvent(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DevicePowerStateChangedEvent value)?  devicePowerStateChanged,TResult? Function( VolumeChangedEvent value)?  volumeChanged,TResult? Function( ExtDeviceReplayEvent value)?  replayEvent,}){
final _that = this;
switch (_that) {
case DevicePowerStateChangedEvent() when devicePowerStateChanged != null:
return devicePowerStateChanged(_that);case VolumeChangedEvent() when volumeChanged != null:
return volumeChanged(_that);case ExtDeviceReplayEvent() when replayEvent != null:
return replayEvent(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool powerOn,  int seq)?  devicePowerStateChanged,TResult Function( DeviceVolume volume,  int seq)?  volumeChanged,TResult Function( ExtDeviceState state,  int serverTimeNs,  int seq)?  replayEvent,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DevicePowerStateChangedEvent() when devicePowerStateChanged != null:
return devicePowerStateChanged(_that.powerOn,_that.seq);case VolumeChangedEvent() when volumeChanged != null:
return volumeChanged(_that.volume,_that.seq);case ExtDeviceReplayEvent() when replayEvent != null:
return replayEvent(_that.state,_that.serverTimeNs,_that.seq);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool powerOn,  int seq)  devicePowerStateChanged,required TResult Function( DeviceVolume volume,  int seq)  volumeChanged,required TResult Function( ExtDeviceState state,  int serverTimeNs,  int seq)  replayEvent,}) {final _that = this;
switch (_that) {
case DevicePowerStateChangedEvent():
return devicePowerStateChanged(_that.powerOn,_that.seq);case VolumeChangedEvent():
return volumeChanged(_that.volume,_that.seq);case ExtDeviceReplayEvent():
return replayEvent(_that.state,_that.serverTimeNs,_that.seq);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool powerOn,  int seq)?  devicePowerStateChanged,TResult? Function( DeviceVolume volume,  int seq)?  volumeChanged,TResult? Function( ExtDeviceState state,  int serverTimeNs,  int seq)?  replayEvent,}) {final _that = this;
switch (_that) {
case DevicePowerStateChangedEvent() when devicePowerStateChanged != null:
return devicePowerStateChanged(_that.powerOn,_that.seq);case VolumeChangedEvent() when volumeChanged != null:
return volumeChanged(_that.volume,_that.seq);case ExtDeviceReplayEvent() when replayEvent != null:
return replayEvent(_that.state,_that.serverTimeNs,_that.seq);case _:
  return null;

}
}

}

/// @nodoc


class DevicePowerStateChangedEvent implements ExtDeviceEvent {
  const DevicePowerStateChangedEvent({required this.powerOn, required this.seq});
  

 final  bool powerOn;
@override final  int seq;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DevicePowerStateChangedEventCopyWith<DevicePowerStateChangedEvent> get copyWith => _$DevicePowerStateChangedEventCopyWithImpl<DevicePowerStateChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DevicePowerStateChangedEvent&&(identical(other.powerOn, powerOn) || other.powerOn == powerOn)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode {
    return Object.hash(runtimeType,powerOn,seq);
}

@override
String toString() {
    return 'ExtDeviceEvent.devicePowerStateChanged(powerOn: $powerOn, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $DevicePowerStateChangedEventCopyWith<$Res> implements $ExtDeviceEventCopyWith<$Res> {
  factory $DevicePowerStateChangedEventCopyWith(DevicePowerStateChangedEvent value, $Res Function(DevicePowerStateChangedEvent) _then) = _$DevicePowerStateChangedEventCopyWithImpl;
@override @useResult
$Res call({
 bool powerOn, int seq
});




}
/// @nodoc
class _$DevicePowerStateChangedEventCopyWithImpl<$Res>
    implements $DevicePowerStateChangedEventCopyWith<$Res> {
  _$DevicePowerStateChangedEventCopyWithImpl(this._self, this._then);

  final DevicePowerStateChangedEvent _self;
  final $Res Function(DevicePowerStateChangedEvent) _then;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? powerOn = null,Object? seq = null,}) {
  return _then(DevicePowerStateChangedEvent(
powerOn: null == powerOn ? _self.powerOn : powerOn // ignore: cast_nullable_to_non_nullable
as bool,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class VolumeChangedEvent implements ExtDeviceEvent {
  const VolumeChangedEvent({required this.volume, required this.seq});
  

 final  DeviceVolume volume;
@override final  int seq;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VolumeChangedEventCopyWith<VolumeChangedEvent> get copyWith => _$VolumeChangedEventCopyWithImpl<VolumeChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VolumeChangedEvent&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode {
    return Object.hash(runtimeType,volume,seq);
}

@override
String toString() {
    return 'ExtDeviceEvent.volumeChanged(volume: $volume, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $VolumeChangedEventCopyWith<$Res> implements $ExtDeviceEventCopyWith<$Res> {
  factory $VolumeChangedEventCopyWith(VolumeChangedEvent value, $Res Function(VolumeChangedEvent) _then) = _$VolumeChangedEventCopyWithImpl;
@override @useResult
$Res call({
 DeviceVolume volume, int seq
});




}
/// @nodoc
class _$VolumeChangedEventCopyWithImpl<$Res>
    implements $VolumeChangedEventCopyWith<$Res> {
  _$VolumeChangedEventCopyWithImpl(this._self, this._then);

  final VolumeChangedEvent _self;
  final $Res Function(VolumeChangedEvent) _then;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? volume = null,Object? seq = null,}) {
  return _then(VolumeChangedEvent(
volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as DeviceVolume,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ExtDeviceReplayEvent implements ExtDeviceEvent {
  const ExtDeviceReplayEvent({required this.state, required this.serverTimeNs, required this.seq});
  

 final  ExtDeviceState state;
 final  int serverTimeNs;
@override final  int seq;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtDeviceReplayEventCopyWith<ExtDeviceReplayEvent> get copyWith => _$ExtDeviceReplayEventCopyWithImpl<ExtDeviceReplayEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtDeviceReplayEvent&&(identical(other.state, state) || other.state == state)&&(identical(other.serverTimeNs, serverTimeNs) || other.serverTimeNs == serverTimeNs)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,serverTimeNs,seq);
}

@override
String toString() {
    return 'ExtDeviceEvent.replayEvent(state: $state, serverTimeNs: $serverTimeNs, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $ExtDeviceReplayEventCopyWith<$Res> implements $ExtDeviceEventCopyWith<$Res> {
  factory $ExtDeviceReplayEventCopyWith(ExtDeviceReplayEvent value, $Res Function(ExtDeviceReplayEvent) _then) = _$ExtDeviceReplayEventCopyWithImpl;
@override @useResult
$Res call({
 ExtDeviceState state, int serverTimeNs, int seq
});




}
/// @nodoc
class _$ExtDeviceReplayEventCopyWithImpl<$Res>
    implements $ExtDeviceReplayEventCopyWith<$Res> {
  _$ExtDeviceReplayEventCopyWithImpl(this._self, this._then);

  final ExtDeviceReplayEvent _self;
  final $Res Function(ExtDeviceReplayEvent) _then;

/// Create a copy of ExtDeviceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? serverTimeNs = null,Object? seq = null,}) {
  return _then(ExtDeviceReplayEvent(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ExtDeviceState,serverTimeNs: null == serverTimeNs ? _self.serverTimeNs : serverTimeNs // ignore: cast_nullable_to_non_nullable
as int,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
