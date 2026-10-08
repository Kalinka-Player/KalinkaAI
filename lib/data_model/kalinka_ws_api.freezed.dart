// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kalinka_ws_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
DeviceCommand _$DeviceCommandFromJson(
  Map<String, dynamic> json
) {
        switch (json['command']) {
                  case 'power_on':
          return PowerOnCommand.fromJson(
            json
          );
                case 'power_off':
          return PowerOffCommand.fromJson(
            json
          );
                case 'set_volume':
          return SetVolumeCommand.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'command',
  'DeviceCommand',
  'Invalid union type "${json['command']}"!'
);
        }
      
}

/// @nodoc
mixin _$DeviceCommand {



  /// Serializes this DeviceCommand to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeviceCommand()';
}


}

/// @nodoc
class $DeviceCommandCopyWith<$Res>  {
$DeviceCommandCopyWith(DeviceCommand _, $Res Function(DeviceCommand) __);
}


/// Adds pattern-matching-related methods to [DeviceCommand].
extension DeviceCommandPatterns on DeviceCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PowerOnCommand value)?  powerOn,TResult Function( PowerOffCommand value)?  powerOff,TResult Function( SetVolumeCommand value)?  setVolume,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PowerOnCommand() when powerOn != null:
return powerOn(_that);case PowerOffCommand() when powerOff != null:
return powerOff(_that);case SetVolumeCommand() when setVolume != null:
return setVolume(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PowerOnCommand value)  powerOn,required TResult Function( PowerOffCommand value)  powerOff,required TResult Function( SetVolumeCommand value)  setVolume,}){
final _that = this;
switch (_that) {
case PowerOnCommand():
return powerOn(_that);case PowerOffCommand():
return powerOff(_that);case SetVolumeCommand():
return setVolume(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PowerOnCommand value)?  powerOn,TResult? Function( PowerOffCommand value)?  powerOff,TResult? Function( SetVolumeCommand value)?  setVolume,}){
final _that = this;
switch (_that) {
case PowerOnCommand() when powerOn != null:
return powerOn(_that);case PowerOffCommand() when powerOff != null:
return powerOff(_that);case SetVolumeCommand() when setVolume != null:
return setVolume(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  powerOn,TResult Function()?  powerOff,TResult Function( int volume)?  setVolume,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PowerOnCommand() when powerOn != null:
return powerOn();case PowerOffCommand() when powerOff != null:
return powerOff();case SetVolumeCommand() when setVolume != null:
return setVolume(_that.volume);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  powerOn,required TResult Function()  powerOff,required TResult Function( int volume)  setVolume,}) {final _that = this;
switch (_that) {
case PowerOnCommand():
return powerOn();case PowerOffCommand():
return powerOff();case SetVolumeCommand():
return setVolume(_that.volume);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  powerOn,TResult? Function()?  powerOff,TResult? Function( int volume)?  setVolume,}) {final _that = this;
switch (_that) {
case PowerOnCommand() when powerOn != null:
return powerOn();case PowerOffCommand() when powerOff != null:
return powerOff();case SetVolumeCommand() when setVolume != null:
return setVolume(_that.volume);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class PowerOnCommand implements DeviceCommand {
  const PowerOnCommand({ String? $type}): $type = $type ?? 'power_on';
  factory PowerOnCommand.fromJson(Map<String, dynamic> json) => _$PowerOnCommandFromJson(json);



@JsonKey(name: 'command')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$PowerOnCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PowerOnCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeviceCommand.powerOn()';
}


}




/// @nodoc
@JsonSerializable()

class PowerOffCommand implements DeviceCommand {
  const PowerOffCommand({ String? $type}): $type = $type ?? 'power_off';
  factory PowerOffCommand.fromJson(Map<String, dynamic> json) => _$PowerOffCommandFromJson(json);



@JsonKey(name: 'command')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$PowerOffCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PowerOffCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeviceCommand.powerOff()';
}


}




/// @nodoc
@JsonSerializable()

class SetVolumeCommand implements DeviceCommand {
  const SetVolumeCommand({required this.volume,  String? $type}): assert(volume >= 0, 'Volume must be non-negative'),$type = $type ?? 'set_volume';
  factory SetVolumeCommand.fromJson(Map<String, dynamic> json) => _$SetVolumeCommandFromJson(json);

 final  int volume;

@JsonKey(name: 'command')
final String $type;


/// Create a copy of DeviceCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetVolumeCommandCopyWith<SetVolumeCommand> get copyWith => _$SetVolumeCommandCopyWithImpl<SetVolumeCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SetVolumeCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SetVolumeCommand&&(identical(other.volume, volume) || other.volume == volume));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,volume);
}

@override
String toString() {
    return 'DeviceCommand.setVolume(volume: $volume)';
}


}

/// @nodoc
abstract mixin class $SetVolumeCommandCopyWith<$Res> implements $DeviceCommandCopyWith<$Res> {
  factory $SetVolumeCommandCopyWith(SetVolumeCommand value, $Res Function(SetVolumeCommand) _then) = _$SetVolumeCommandCopyWithImpl;
@useResult
$Res call({
 int volume
});




}
/// @nodoc
class _$SetVolumeCommandCopyWithImpl<$Res>
    implements $SetVolumeCommandCopyWith<$Res> {
  _$SetVolumeCommandCopyWithImpl(this._self, this._then);

  final SetVolumeCommand _self;
  final $Res Function(SetVolumeCommand) _then;

/// Create a copy of DeviceCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? volume = null,}) {
  return _then(SetVolumeCommand(
volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

QueueCommand _$QueueCommandFromJson(
  Map<String, dynamic> json
) {
        switch (json['command']) {
                  case 'play':
          return PlayCommand.fromJson(
            json
          );
                case 'pause':
          return PauseCommand.fromJson(
            json
          );
                case 'next':
          return NextCommand.fromJson(
            json
          );
                case 'prev':
          return PrevCommand.fromJson(
            json
          );
                case 'stop':
          return StopCommand.fromJson(
            json
          );
                case 'seek':
          return SeekCommand.fromJson(
            json
          );
                case 'set_playback_mode':
          return SetPlaybackModeCommand.fromJson(
            json
          );
                case 'move':
          return MoveCommand.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'command',
  'QueueCommand',
  'Invalid union type "${json['command']}"!'
);
        }
      
}

/// @nodoc
mixin _$QueueCommand {



  /// Serializes this QueueCommand to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QueueCommand()';
}


}

/// @nodoc
class $QueueCommandCopyWith<$Res>  {
$QueueCommandCopyWith(QueueCommand _, $Res Function(QueueCommand) __);
}


/// Adds pattern-matching-related methods to [QueueCommand].
extension QueueCommandPatterns on QueueCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlayCommand value)?  play,TResult Function( PauseCommand value)?  pause,TResult Function( NextCommand value)?  next,TResult Function( PrevCommand value)?  prev,TResult Function( StopCommand value)?  stop,TResult Function( SeekCommand value)?  seek,TResult Function( SetPlaybackModeCommand value)?  setPlaybackMode,TResult Function( MoveCommand value)?  move,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlayCommand() when play != null:
return play(_that);case PauseCommand() when pause != null:
return pause(_that);case NextCommand() when next != null:
return next(_that);case PrevCommand() when prev != null:
return prev(_that);case StopCommand() when stop != null:
return stop(_that);case SeekCommand() when seek != null:
return seek(_that);case SetPlaybackModeCommand() when setPlaybackMode != null:
return setPlaybackMode(_that);case MoveCommand() when move != null:
return move(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlayCommand value)  play,required TResult Function( PauseCommand value)  pause,required TResult Function( NextCommand value)  next,required TResult Function( PrevCommand value)  prev,required TResult Function( StopCommand value)  stop,required TResult Function( SeekCommand value)  seek,required TResult Function( SetPlaybackModeCommand value)  setPlaybackMode,required TResult Function( MoveCommand value)  move,}){
final _that = this;
switch (_that) {
case PlayCommand():
return play(_that);case PauseCommand():
return pause(_that);case NextCommand():
return next(_that);case PrevCommand():
return prev(_that);case StopCommand():
return stop(_that);case SeekCommand():
return seek(_that);case SetPlaybackModeCommand():
return setPlaybackMode(_that);case MoveCommand():
return move(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlayCommand value)?  play,TResult? Function( PauseCommand value)?  pause,TResult? Function( NextCommand value)?  next,TResult? Function( PrevCommand value)?  prev,TResult? Function( StopCommand value)?  stop,TResult? Function( SeekCommand value)?  seek,TResult? Function( SetPlaybackModeCommand value)?  setPlaybackMode,TResult? Function( MoveCommand value)?  move,}){
final _that = this;
switch (_that) {
case PlayCommand() when play != null:
return play(_that);case PauseCommand() when pause != null:
return pause(_that);case NextCommand() when next != null:
return next(_that);case PrevCommand() when prev != null:
return prev(_that);case StopCommand() when stop != null:
return stop(_that);case SeekCommand() when seek != null:
return seek(_that);case SetPlaybackModeCommand() when setPlaybackMode != null:
return setPlaybackMode(_that);case MoveCommand() when move != null:
return move(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int? index)?  play,TResult Function( bool paused)?  pause,TResult Function()?  next,TResult Function()?  prev,TResult Function()?  stop,TResult Function( int positionMs)?  seek,TResult Function( bool? shuffle,  bool? repeatSingle,  bool? repeatAll)?  setPlaybackMode,TResult Function( int fromIndex,  int toIndex)?  move,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlayCommand() when play != null:
return play(_that.index);case PauseCommand() when pause != null:
return pause(_that.paused);case NextCommand() when next != null:
return next();case PrevCommand() when prev != null:
return prev();case StopCommand() when stop != null:
return stop();case SeekCommand() when seek != null:
return seek(_that.positionMs);case SetPlaybackModeCommand() when setPlaybackMode != null:
return setPlaybackMode(_that.shuffle,_that.repeatSingle,_that.repeatAll);case MoveCommand() when move != null:
return move(_that.fromIndex,_that.toIndex);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int? index)  play,required TResult Function( bool paused)  pause,required TResult Function()  next,required TResult Function()  prev,required TResult Function()  stop,required TResult Function( int positionMs)  seek,required TResult Function( bool? shuffle,  bool? repeatSingle,  bool? repeatAll)  setPlaybackMode,required TResult Function( int fromIndex,  int toIndex)  move,}) {final _that = this;
switch (_that) {
case PlayCommand():
return play(_that.index);case PauseCommand():
return pause(_that.paused);case NextCommand():
return next();case PrevCommand():
return prev();case StopCommand():
return stop();case SeekCommand():
return seek(_that.positionMs);case SetPlaybackModeCommand():
return setPlaybackMode(_that.shuffle,_that.repeatSingle,_that.repeatAll);case MoveCommand():
return move(_that.fromIndex,_that.toIndex);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int? index)?  play,TResult? Function( bool paused)?  pause,TResult? Function()?  next,TResult? Function()?  prev,TResult? Function()?  stop,TResult? Function( int positionMs)?  seek,TResult? Function( bool? shuffle,  bool? repeatSingle,  bool? repeatAll)?  setPlaybackMode,TResult? Function( int fromIndex,  int toIndex)?  move,}) {final _that = this;
switch (_that) {
case PlayCommand() when play != null:
return play(_that.index);case PauseCommand() when pause != null:
return pause(_that.paused);case NextCommand() when next != null:
return next();case PrevCommand() when prev != null:
return prev();case StopCommand() when stop != null:
return stop();case SeekCommand() when seek != null:
return seek(_that.positionMs);case SetPlaybackModeCommand() when setPlaybackMode != null:
return setPlaybackMode(_that.shuffle,_that.repeatSingle,_that.repeatAll);case MoveCommand() when move != null:
return move(_that.fromIndex,_that.toIndex);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class PlayCommand extends QueueCommand {
  const PlayCommand({this.index,  String? $type}): $type = $type ?? 'play',super._();
  factory PlayCommand.fromJson(Map<String, dynamic> json) => _$PlayCommandFromJson(json);

 final  int? index;

@JsonKey(name: 'command')
final String $type;


/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayCommandCopyWith<PlayCommand> get copyWith => _$PlayCommandCopyWithImpl<PlayCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlayCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayCommand&&(identical(other.index, index) || other.index == index));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,index);
}

@override
String toString() {
    return 'QueueCommand.play(index: $index)';
}


}

/// @nodoc
abstract mixin class $PlayCommandCopyWith<$Res> implements $QueueCommandCopyWith<$Res> {
  factory $PlayCommandCopyWith(PlayCommand value, $Res Function(PlayCommand) _then) = _$PlayCommandCopyWithImpl;
@useResult
$Res call({
 int? index
});




}
/// @nodoc
class _$PlayCommandCopyWithImpl<$Res>
    implements $PlayCommandCopyWith<$Res> {
  _$PlayCommandCopyWithImpl(this._self, this._then);

  final PlayCommand _self;
  final $Res Function(PlayCommand) _then;

/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? index = freezed,}) {
  return _then(PlayCommand(
index: freezed == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class PauseCommand extends QueueCommand {
  const PauseCommand({this.paused = true,  String? $type}): $type = $type ?? 'pause',super._();
  factory PauseCommand.fromJson(Map<String, dynamic> json) => _$PauseCommandFromJson(json);

@JsonKey() final  bool paused;

@JsonKey(name: 'command')
final String $type;


/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PauseCommandCopyWith<PauseCommand> get copyWith => _$PauseCommandCopyWithImpl<PauseCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PauseCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PauseCommand&&(identical(other.paused, paused) || other.paused == paused));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,paused);
}

@override
String toString() {
    return 'QueueCommand.pause(paused: $paused)';
}


}

/// @nodoc
abstract mixin class $PauseCommandCopyWith<$Res> implements $QueueCommandCopyWith<$Res> {
  factory $PauseCommandCopyWith(PauseCommand value, $Res Function(PauseCommand) _then) = _$PauseCommandCopyWithImpl;
@useResult
$Res call({
 bool paused
});




}
/// @nodoc
class _$PauseCommandCopyWithImpl<$Res>
    implements $PauseCommandCopyWith<$Res> {
  _$PauseCommandCopyWithImpl(this._self, this._then);

  final PauseCommand _self;
  final $Res Function(PauseCommand) _then;

/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? paused = null,}) {
  return _then(PauseCommand(
paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
@JsonSerializable()

class NextCommand extends QueueCommand {
  const NextCommand({ String? $type}): $type = $type ?? 'next',super._();
  factory NextCommand.fromJson(Map<String, dynamic> json) => _$NextCommandFromJson(json);



@JsonKey(name: 'command')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$NextCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NextCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QueueCommand.next()';
}


}




/// @nodoc
@JsonSerializable()

class PrevCommand extends QueueCommand {
  const PrevCommand({ String? $type}): $type = $type ?? 'prev',super._();
  factory PrevCommand.fromJson(Map<String, dynamic> json) => _$PrevCommandFromJson(json);



@JsonKey(name: 'command')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$PrevCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PrevCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QueueCommand.prev()';
}


}




/// @nodoc
@JsonSerializable()

class StopCommand extends QueueCommand {
  const StopCommand({ String? $type}): $type = $type ?? 'stop',super._();
  factory StopCommand.fromJson(Map<String, dynamic> json) => _$StopCommandFromJson(json);



@JsonKey(name: 'command')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$StopCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StopCommand);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QueueCommand.stop()';
}


}




/// @nodoc
@JsonSerializable()

class SeekCommand extends QueueCommand {
  const SeekCommand({required this.positionMs,  String? $type}): $type = $type ?? 'seek',super._();
  factory SeekCommand.fromJson(Map<String, dynamic> json) => _$SeekCommandFromJson(json);

 final  int positionMs;

@JsonKey(name: 'command')
final String $type;


/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeekCommandCopyWith<SeekCommand> get copyWith => _$SeekCommandCopyWithImpl<SeekCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeekCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SeekCommand&&(identical(other.positionMs, positionMs) || other.positionMs == positionMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,positionMs);
}

@override
String toString() {
    return 'QueueCommand.seek(positionMs: $positionMs)';
}


}

/// @nodoc
abstract mixin class $SeekCommandCopyWith<$Res> implements $QueueCommandCopyWith<$Res> {
  factory $SeekCommandCopyWith(SeekCommand value, $Res Function(SeekCommand) _then) = _$SeekCommandCopyWithImpl;
@useResult
$Res call({
 int positionMs
});




}
/// @nodoc
class _$SeekCommandCopyWithImpl<$Res>
    implements $SeekCommandCopyWith<$Res> {
  _$SeekCommandCopyWithImpl(this._self, this._then);

  final SeekCommand _self;
  final $Res Function(SeekCommand) _then;

/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? positionMs = null,}) {
  return _then(SeekCommand(
positionMs: null == positionMs ? _self.positionMs : positionMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class SetPlaybackModeCommand extends QueueCommand {
  const SetPlaybackModeCommand({this.shuffle, this.repeatSingle, this.repeatAll,  String? $type}): $type = $type ?? 'set_playback_mode',super._();
  factory SetPlaybackModeCommand.fromJson(Map<String, dynamic> json) => _$SetPlaybackModeCommandFromJson(json);

 final  bool? shuffle;
 final  bool? repeatSingle;
 final  bool? repeatAll;

@JsonKey(name: 'command')
final String $type;


/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetPlaybackModeCommandCopyWith<SetPlaybackModeCommand> get copyWith => _$SetPlaybackModeCommandCopyWithImpl<SetPlaybackModeCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SetPlaybackModeCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SetPlaybackModeCommand&&(identical(other.shuffle, shuffle) || other.shuffle == shuffle)&&(identical(other.repeatSingle, repeatSingle) || other.repeatSingle == repeatSingle)&&(identical(other.repeatAll, repeatAll) || other.repeatAll == repeatAll));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,shuffle,repeatSingle,repeatAll);
}

@override
String toString() {
    return 'QueueCommand.setPlaybackMode(shuffle: $shuffle, repeatSingle: $repeatSingle, repeatAll: $repeatAll)';
}


}

/// @nodoc
abstract mixin class $SetPlaybackModeCommandCopyWith<$Res> implements $QueueCommandCopyWith<$Res> {
  factory $SetPlaybackModeCommandCopyWith(SetPlaybackModeCommand value, $Res Function(SetPlaybackModeCommand) _then) = _$SetPlaybackModeCommandCopyWithImpl;
@useResult
$Res call({
 bool? shuffle, bool? repeatSingle, bool? repeatAll
});




}
/// @nodoc
class _$SetPlaybackModeCommandCopyWithImpl<$Res>
    implements $SetPlaybackModeCommandCopyWith<$Res> {
  _$SetPlaybackModeCommandCopyWithImpl(this._self, this._then);

  final SetPlaybackModeCommand _self;
  final $Res Function(SetPlaybackModeCommand) _then;

/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? shuffle = freezed,Object? repeatSingle = freezed,Object? repeatAll = freezed,}) {
  return _then(SetPlaybackModeCommand(
shuffle: freezed == shuffle ? _self.shuffle : shuffle // ignore: cast_nullable_to_non_nullable
as bool?,repeatSingle: freezed == repeatSingle ? _self.repeatSingle : repeatSingle // ignore: cast_nullable_to_non_nullable
as bool?,repeatAll: freezed == repeatAll ? _self.repeatAll : repeatAll // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class MoveCommand extends QueueCommand {
  const MoveCommand({required this.fromIndex, required this.toIndex,  String? $type}): $type = $type ?? 'move',super._();
  factory MoveCommand.fromJson(Map<String, dynamic> json) => _$MoveCommandFromJson(json);

 final  int fromIndex;
 final  int toIndex;

@JsonKey(name: 'command')
final String $type;


/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MoveCommandCopyWith<MoveCommand> get copyWith => _$MoveCommandCopyWithImpl<MoveCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MoveCommandToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MoveCommand&&(identical(other.fromIndex, fromIndex) || other.fromIndex == fromIndex)&&(identical(other.toIndex, toIndex) || other.toIndex == toIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,fromIndex,toIndex);
}

@override
String toString() {
    return 'QueueCommand.move(fromIndex: $fromIndex, toIndex: $toIndex)';
}


}

/// @nodoc
abstract mixin class $MoveCommandCopyWith<$Res> implements $QueueCommandCopyWith<$Res> {
  factory $MoveCommandCopyWith(MoveCommand value, $Res Function(MoveCommand) _then) = _$MoveCommandCopyWithImpl;
@useResult
$Res call({
 int fromIndex, int toIndex
});




}
/// @nodoc
class _$MoveCommandCopyWithImpl<$Res>
    implements $MoveCommandCopyWith<$Res> {
  _$MoveCommandCopyWithImpl(this._self, this._then);

  final MoveCommand _self;
  final $Res Function(MoveCommand) _then;

/// Create a copy of QueueCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fromIndex = null,Object? toIndex = null,}) {
  return _then(MoveCommand(
fromIndex: null == fromIndex ? _self.fromIndex : fromIndex // ignore: cast_nullable_to_non_nullable
as int,toIndex: null == toIndex ? _self.toIndex : toIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
