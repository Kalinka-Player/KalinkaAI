// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playqueue_events.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlayQueueEvent {

 int get seq;
/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayQueueEventCopyWith<PlayQueueEvent> get copyWith => _$PlayQueueEventCopyWithImpl<PlayQueueEvent>(this as PlayQueueEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayQueueEvent&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,seq);

@override
String toString() {
  return 'PlayQueueEvent(seq: $seq)';
}


}

/// @nodoc
abstract mixin class $PlayQueueEventCopyWith<$Res>  {
  factory $PlayQueueEventCopyWith(PlayQueueEvent value, $Res Function(PlayQueueEvent) _then) = _$PlayQueueEventCopyWithImpl;
@useResult
$Res call({
 int seq
});




}
/// @nodoc
class _$PlayQueueEventCopyWithImpl<$Res>
    implements $PlayQueueEventCopyWith<$Res> {
  _$PlayQueueEventCopyWithImpl(this._self, this._then);

  final PlayQueueEvent _self;
  final $Res Function(PlayQueueEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? seq = null,}) {
  return _then(_self.copyWith(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PlayQueueEvent].
extension PlayQueueEventPatterns on PlayQueueEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlaybackStateChangedEvent value)?  playbackStateChanged,TResult Function( RequestMoreTracksEvent value)?  requestMoreTracks,TResult Function( TracksAddedEvent value)?  tracksAdded,TResult Function( TracksRemovedEvent value)?  tracksRemoved,TResult Function( TrackMovedEvent value)?  trackMoved,TResult Function( TrackUnavailableEvent value)?  trackUnavailable,TResult Function( PlaybackErrorEvent value)?  playbackError,TResult Function( PlaybackModeChangedEvent value)?  playbackModeChanged,TResult Function( ReplayPlayQueueEvent value)?  replayEvent,TResult Function( RenderersChangedEvent value)?  renderersChanged,TResult Function( CurrentRendererChangedEvent value)?  currentRendererChanged,TResult Function( PlaybackControlChangedEvent value)?  playbackControlChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlaybackStateChangedEvent() when playbackStateChanged != null:
return playbackStateChanged(_that);case RequestMoreTracksEvent() when requestMoreTracks != null:
return requestMoreTracks(_that);case TracksAddedEvent() when tracksAdded != null:
return tracksAdded(_that);case TracksRemovedEvent() when tracksRemoved != null:
return tracksRemoved(_that);case TrackMovedEvent() when trackMoved != null:
return trackMoved(_that);case TrackUnavailableEvent() when trackUnavailable != null:
return trackUnavailable(_that);case PlaybackErrorEvent() when playbackError != null:
return playbackError(_that);case PlaybackModeChangedEvent() when playbackModeChanged != null:
return playbackModeChanged(_that);case ReplayPlayQueueEvent() when replayEvent != null:
return replayEvent(_that);case RenderersChangedEvent() when renderersChanged != null:
return renderersChanged(_that);case CurrentRendererChangedEvent() when currentRendererChanged != null:
return currentRendererChanged(_that);case PlaybackControlChangedEvent() when playbackControlChanged != null:
return playbackControlChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlaybackStateChangedEvent value)  playbackStateChanged,required TResult Function( RequestMoreTracksEvent value)  requestMoreTracks,required TResult Function( TracksAddedEvent value)  tracksAdded,required TResult Function( TracksRemovedEvent value)  tracksRemoved,required TResult Function( TrackMovedEvent value)  trackMoved,required TResult Function( TrackUnavailableEvent value)  trackUnavailable,required TResult Function( PlaybackErrorEvent value)  playbackError,required TResult Function( PlaybackModeChangedEvent value)  playbackModeChanged,required TResult Function( ReplayPlayQueueEvent value)  replayEvent,required TResult Function( RenderersChangedEvent value)  renderersChanged,required TResult Function( CurrentRendererChangedEvent value)  currentRendererChanged,required TResult Function( PlaybackControlChangedEvent value)  playbackControlChanged,}){
final _that = this;
switch (_that) {
case PlaybackStateChangedEvent():
return playbackStateChanged(_that);case RequestMoreTracksEvent():
return requestMoreTracks(_that);case TracksAddedEvent():
return tracksAdded(_that);case TracksRemovedEvent():
return tracksRemoved(_that);case TrackMovedEvent():
return trackMoved(_that);case TrackUnavailableEvent():
return trackUnavailable(_that);case PlaybackErrorEvent():
return playbackError(_that);case PlaybackModeChangedEvent():
return playbackModeChanged(_that);case ReplayPlayQueueEvent():
return replayEvent(_that);case RenderersChangedEvent():
return renderersChanged(_that);case CurrentRendererChangedEvent():
return currentRendererChanged(_that);case PlaybackControlChangedEvent():
return playbackControlChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlaybackStateChangedEvent value)?  playbackStateChanged,TResult? Function( RequestMoreTracksEvent value)?  requestMoreTracks,TResult? Function( TracksAddedEvent value)?  tracksAdded,TResult? Function( TracksRemovedEvent value)?  tracksRemoved,TResult? Function( TrackMovedEvent value)?  trackMoved,TResult? Function( TrackUnavailableEvent value)?  trackUnavailable,TResult? Function( PlaybackErrorEvent value)?  playbackError,TResult? Function( PlaybackModeChangedEvent value)?  playbackModeChanged,TResult? Function( ReplayPlayQueueEvent value)?  replayEvent,TResult? Function( RenderersChangedEvent value)?  renderersChanged,TResult? Function( CurrentRendererChangedEvent value)?  currentRendererChanged,TResult? Function( PlaybackControlChangedEvent value)?  playbackControlChanged,}){
final _that = this;
switch (_that) {
case PlaybackStateChangedEvent() when playbackStateChanged != null:
return playbackStateChanged(_that);case RequestMoreTracksEvent() when requestMoreTracks != null:
return requestMoreTracks(_that);case TracksAddedEvent() when tracksAdded != null:
return tracksAdded(_that);case TracksRemovedEvent() when tracksRemoved != null:
return tracksRemoved(_that);case TrackMovedEvent() when trackMoved != null:
return trackMoved(_that);case TrackUnavailableEvent() when trackUnavailable != null:
return trackUnavailable(_that);case PlaybackErrorEvent() when playbackError != null:
return playbackError(_that);case PlaybackModeChangedEvent() when playbackModeChanged != null:
return playbackModeChanged(_that);case ReplayPlayQueueEvent() when replayEvent != null:
return replayEvent(_that);case RenderersChangedEvent() when renderersChanged != null:
return renderersChanged(_that);case CurrentRendererChangedEvent() when currentRendererChanged != null:
return currentRendererChanged(_that);case PlaybackControlChangedEvent() when playbackControlChanged != null:
return playbackControlChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlaybackState state,  int seq)?  playbackStateChanged,TResult Function( int seq)?  requestMoreTracks,TResult Function( List<Track> tracks,  int seq,  int? index)?  tracksAdded,TResult Function( List<int> indices,  int seq)?  tracksRemoved,TResult Function( int fromIndex,  int toIndex,  int seq)?  trackMoved,TResult Function( int index,  bool unavailable,  int seq,  String? reason)?  trackUnavailable,TResult Function( String message,  int seq)?  playbackError,TResult Function( PlaybackMode mode,  int seq)?  playbackModeChanged,TResult Function( PlayQueueState state,  int serverTimeNs,  int seq)?  replayEvent,TResult Function( List<RendererInfo> renderers,  int seq)?  renderersChanged,TResult Function( String? rendererId,  String? selectedRendererId,  int seq)?  currentRendererChanged,TResult Function( PlaybackControl control,  int seq)?  playbackControlChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlaybackStateChangedEvent() when playbackStateChanged != null:
return playbackStateChanged(_that.state,_that.seq);case RequestMoreTracksEvent() when requestMoreTracks != null:
return requestMoreTracks(_that.seq);case TracksAddedEvent() when tracksAdded != null:
return tracksAdded(_that.tracks,_that.seq,_that.index);case TracksRemovedEvent() when tracksRemoved != null:
return tracksRemoved(_that.indices,_that.seq);case TrackMovedEvent() when trackMoved != null:
return trackMoved(_that.fromIndex,_that.toIndex,_that.seq);case TrackUnavailableEvent() when trackUnavailable != null:
return trackUnavailable(_that.index,_that.unavailable,_that.seq,_that.reason);case PlaybackErrorEvent() when playbackError != null:
return playbackError(_that.message,_that.seq);case PlaybackModeChangedEvent() when playbackModeChanged != null:
return playbackModeChanged(_that.mode,_that.seq);case ReplayPlayQueueEvent() when replayEvent != null:
return replayEvent(_that.state,_that.serverTimeNs,_that.seq);case RenderersChangedEvent() when renderersChanged != null:
return renderersChanged(_that.renderers,_that.seq);case CurrentRendererChangedEvent() when currentRendererChanged != null:
return currentRendererChanged(_that.rendererId,_that.selectedRendererId,_that.seq);case PlaybackControlChangedEvent() when playbackControlChanged != null:
return playbackControlChanged(_that.control,_that.seq);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlaybackState state,  int seq)  playbackStateChanged,required TResult Function( int seq)  requestMoreTracks,required TResult Function( List<Track> tracks,  int seq,  int? index)  tracksAdded,required TResult Function( List<int> indices,  int seq)  tracksRemoved,required TResult Function( int fromIndex,  int toIndex,  int seq)  trackMoved,required TResult Function( int index,  bool unavailable,  int seq,  String? reason)  trackUnavailable,required TResult Function( String message,  int seq)  playbackError,required TResult Function( PlaybackMode mode,  int seq)  playbackModeChanged,required TResult Function( PlayQueueState state,  int serverTimeNs,  int seq)  replayEvent,required TResult Function( List<RendererInfo> renderers,  int seq)  renderersChanged,required TResult Function( String? rendererId,  String? selectedRendererId,  int seq)  currentRendererChanged,required TResult Function( PlaybackControl control,  int seq)  playbackControlChanged,}) {final _that = this;
switch (_that) {
case PlaybackStateChangedEvent():
return playbackStateChanged(_that.state,_that.seq);case RequestMoreTracksEvent():
return requestMoreTracks(_that.seq);case TracksAddedEvent():
return tracksAdded(_that.tracks,_that.seq,_that.index);case TracksRemovedEvent():
return tracksRemoved(_that.indices,_that.seq);case TrackMovedEvent():
return trackMoved(_that.fromIndex,_that.toIndex,_that.seq);case TrackUnavailableEvent():
return trackUnavailable(_that.index,_that.unavailable,_that.seq,_that.reason);case PlaybackErrorEvent():
return playbackError(_that.message,_that.seq);case PlaybackModeChangedEvent():
return playbackModeChanged(_that.mode,_that.seq);case ReplayPlayQueueEvent():
return replayEvent(_that.state,_that.serverTimeNs,_that.seq);case RenderersChangedEvent():
return renderersChanged(_that.renderers,_that.seq);case CurrentRendererChangedEvent():
return currentRendererChanged(_that.rendererId,_that.selectedRendererId,_that.seq);case PlaybackControlChangedEvent():
return playbackControlChanged(_that.control,_that.seq);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlaybackState state,  int seq)?  playbackStateChanged,TResult? Function( int seq)?  requestMoreTracks,TResult? Function( List<Track> tracks,  int seq,  int? index)?  tracksAdded,TResult? Function( List<int> indices,  int seq)?  tracksRemoved,TResult? Function( int fromIndex,  int toIndex,  int seq)?  trackMoved,TResult? Function( int index,  bool unavailable,  int seq,  String? reason)?  trackUnavailable,TResult? Function( String message,  int seq)?  playbackError,TResult? Function( PlaybackMode mode,  int seq)?  playbackModeChanged,TResult? Function( PlayQueueState state,  int serverTimeNs,  int seq)?  replayEvent,TResult? Function( List<RendererInfo> renderers,  int seq)?  renderersChanged,TResult? Function( String? rendererId,  String? selectedRendererId,  int seq)?  currentRendererChanged,TResult? Function( PlaybackControl control,  int seq)?  playbackControlChanged,}) {final _that = this;
switch (_that) {
case PlaybackStateChangedEvent() when playbackStateChanged != null:
return playbackStateChanged(_that.state,_that.seq);case RequestMoreTracksEvent() when requestMoreTracks != null:
return requestMoreTracks(_that.seq);case TracksAddedEvent() when tracksAdded != null:
return tracksAdded(_that.tracks,_that.seq,_that.index);case TracksRemovedEvent() when tracksRemoved != null:
return tracksRemoved(_that.indices,_that.seq);case TrackMovedEvent() when trackMoved != null:
return trackMoved(_that.fromIndex,_that.toIndex,_that.seq);case TrackUnavailableEvent() when trackUnavailable != null:
return trackUnavailable(_that.index,_that.unavailable,_that.seq,_that.reason);case PlaybackErrorEvent() when playbackError != null:
return playbackError(_that.message,_that.seq);case PlaybackModeChangedEvent() when playbackModeChanged != null:
return playbackModeChanged(_that.mode,_that.seq);case ReplayPlayQueueEvent() when replayEvent != null:
return replayEvent(_that.state,_that.serverTimeNs,_that.seq);case RenderersChangedEvent() when renderersChanged != null:
return renderersChanged(_that.renderers,_that.seq);case CurrentRendererChangedEvent() when currentRendererChanged != null:
return currentRendererChanged(_that.rendererId,_that.selectedRendererId,_that.seq);case PlaybackControlChangedEvent() when playbackControlChanged != null:
return playbackControlChanged(_that.control,_that.seq);case _:
  return null;

}
}

}

/// @nodoc


class PlaybackStateChangedEvent implements PlayQueueEvent {
  const PlaybackStateChangedEvent({required this.state, required this.seq});
  

 final  PlaybackState state;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackStateChangedEventCopyWith<PlaybackStateChangedEvent> get copyWith => _$PlaybackStateChangedEventCopyWithImpl<PlaybackStateChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackStateChangedEvent&&(identical(other.state, state) || other.state == state)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,state,seq);

@override
String toString() {
  return 'PlayQueueEvent.playbackStateChanged(state: $state, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $PlaybackStateChangedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $PlaybackStateChangedEventCopyWith(PlaybackStateChangedEvent value, $Res Function(PlaybackStateChangedEvent) _then) = _$PlaybackStateChangedEventCopyWithImpl;
@override @useResult
$Res call({
 PlaybackState state, int seq
});




}
/// @nodoc
class _$PlaybackStateChangedEventCopyWithImpl<$Res>
    implements $PlaybackStateChangedEventCopyWith<$Res> {
  _$PlaybackStateChangedEventCopyWithImpl(this._self, this._then);

  final PlaybackStateChangedEvent _self;
  final $Res Function(PlaybackStateChangedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? seq = null,}) {
  return _then(PlaybackStateChangedEvent(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PlaybackState,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RequestMoreTracksEvent implements PlayQueueEvent {
  const RequestMoreTracksEvent({required this.seq});
  

@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RequestMoreTracksEventCopyWith<RequestMoreTracksEvent> get copyWith => _$RequestMoreTracksEventCopyWithImpl<RequestMoreTracksEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestMoreTracksEvent&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,seq);

@override
String toString() {
  return 'PlayQueueEvent.requestMoreTracks(seq: $seq)';
}


}

/// @nodoc
abstract mixin class $RequestMoreTracksEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $RequestMoreTracksEventCopyWith(RequestMoreTracksEvent value, $Res Function(RequestMoreTracksEvent) _then) = _$RequestMoreTracksEventCopyWithImpl;
@override @useResult
$Res call({
 int seq
});




}
/// @nodoc
class _$RequestMoreTracksEventCopyWithImpl<$Res>
    implements $RequestMoreTracksEventCopyWith<$Res> {
  _$RequestMoreTracksEventCopyWithImpl(this._self, this._then);

  final RequestMoreTracksEvent _self;
  final $Res Function(RequestMoreTracksEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? seq = null,}) {
  return _then(RequestMoreTracksEvent(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TracksAddedEvent implements PlayQueueEvent {
  const TracksAddedEvent({required final  List<Track> tracks, required this.seq, this.index}): _tracks = tracks;
  

 final  List<Track> _tracks;
 List<Track> get tracks {
  if (_tracks is EqualUnmodifiableListView) return _tracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tracks);
}

@override final  int seq;
 final  int? index;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TracksAddedEventCopyWith<TracksAddedEvent> get copyWith => _$TracksAddedEventCopyWithImpl<TracksAddedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TracksAddedEvent&&const DeepCollectionEquality().equals(other._tracks, _tracks)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.index, index) || other.index == index));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_tracks),seq,index);

@override
String toString() {
  return 'PlayQueueEvent.tracksAdded(tracks: $tracks, seq: $seq, index: $index)';
}


}

/// @nodoc
abstract mixin class $TracksAddedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $TracksAddedEventCopyWith(TracksAddedEvent value, $Res Function(TracksAddedEvent) _then) = _$TracksAddedEventCopyWithImpl;
@override @useResult
$Res call({
 List<Track> tracks, int seq, int? index
});




}
/// @nodoc
class _$TracksAddedEventCopyWithImpl<$Res>
    implements $TracksAddedEventCopyWith<$Res> {
  _$TracksAddedEventCopyWithImpl(this._self, this._then);

  final TracksAddedEvent _self;
  final $Res Function(TracksAddedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tracks = null,Object? seq = null,Object? index = freezed,}) {
  return _then(TracksAddedEvent(
tracks: null == tracks ? _self._tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<Track>,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,index: freezed == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class TracksRemovedEvent implements PlayQueueEvent {
  const TracksRemovedEvent({required final  List<int> indices, required this.seq}): _indices = indices;
  

 final  List<int> _indices;
 List<int> get indices {
  if (_indices is EqualUnmodifiableListView) return _indices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_indices);
}

@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TracksRemovedEventCopyWith<TracksRemovedEvent> get copyWith => _$TracksRemovedEventCopyWithImpl<TracksRemovedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TracksRemovedEvent&&const DeepCollectionEquality().equals(other._indices, _indices)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_indices),seq);

@override
String toString() {
  return 'PlayQueueEvent.tracksRemoved(indices: $indices, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $TracksRemovedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $TracksRemovedEventCopyWith(TracksRemovedEvent value, $Res Function(TracksRemovedEvent) _then) = _$TracksRemovedEventCopyWithImpl;
@override @useResult
$Res call({
 List<int> indices, int seq
});




}
/// @nodoc
class _$TracksRemovedEventCopyWithImpl<$Res>
    implements $TracksRemovedEventCopyWith<$Res> {
  _$TracksRemovedEventCopyWithImpl(this._self, this._then);

  final TracksRemovedEvent _self;
  final $Res Function(TracksRemovedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? indices = null,Object? seq = null,}) {
  return _then(TracksRemovedEvent(
indices: null == indices ? _self._indices : indices // ignore: cast_nullable_to_non_nullable
as List<int>,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TrackMovedEvent implements PlayQueueEvent {
  const TrackMovedEvent({required this.fromIndex, required this.toIndex, required this.seq});
  

 final  int fromIndex;
 final  int toIndex;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrackMovedEventCopyWith<TrackMovedEvent> get copyWith => _$TrackMovedEventCopyWithImpl<TrackMovedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrackMovedEvent&&(identical(other.fromIndex, fromIndex) || other.fromIndex == fromIndex)&&(identical(other.toIndex, toIndex) || other.toIndex == toIndex)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,fromIndex,toIndex,seq);

@override
String toString() {
  return 'PlayQueueEvent.trackMoved(fromIndex: $fromIndex, toIndex: $toIndex, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $TrackMovedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $TrackMovedEventCopyWith(TrackMovedEvent value, $Res Function(TrackMovedEvent) _then) = _$TrackMovedEventCopyWithImpl;
@override @useResult
$Res call({
 int fromIndex, int toIndex, int seq
});




}
/// @nodoc
class _$TrackMovedEventCopyWithImpl<$Res>
    implements $TrackMovedEventCopyWith<$Res> {
  _$TrackMovedEventCopyWithImpl(this._self, this._then);

  final TrackMovedEvent _self;
  final $Res Function(TrackMovedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fromIndex = null,Object? toIndex = null,Object? seq = null,}) {
  return _then(TrackMovedEvent(
fromIndex: null == fromIndex ? _self.fromIndex : fromIndex // ignore: cast_nullable_to_non_nullable
as int,toIndex: null == toIndex ? _self.toIndex : toIndex // ignore: cast_nullable_to_non_nullable
as int,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TrackUnavailableEvent implements PlayQueueEvent {
  const TrackUnavailableEvent({required this.index, required this.unavailable, required this.seq, this.reason});
  

 final  int index;
 final  bool unavailable;
@override final  int seq;
 final  String? reason;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrackUnavailableEventCopyWith<TrackUnavailableEvent> get copyWith => _$TrackUnavailableEventCopyWithImpl<TrackUnavailableEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrackUnavailableEvent&&(identical(other.index, index) || other.index == index)&&(identical(other.unavailable, unavailable) || other.unavailable == unavailable)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,index,unavailable,seq,reason);

@override
String toString() {
  return 'PlayQueueEvent.trackUnavailable(index: $index, unavailable: $unavailable, seq: $seq, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TrackUnavailableEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $TrackUnavailableEventCopyWith(TrackUnavailableEvent value, $Res Function(TrackUnavailableEvent) _then) = _$TrackUnavailableEventCopyWithImpl;
@override @useResult
$Res call({
 int index, bool unavailable, int seq, String? reason
});




}
/// @nodoc
class _$TrackUnavailableEventCopyWithImpl<$Res>
    implements $TrackUnavailableEventCopyWith<$Res> {
  _$TrackUnavailableEventCopyWithImpl(this._self, this._then);

  final TrackUnavailableEvent _self;
  final $Res Function(TrackUnavailableEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? unavailable = null,Object? seq = null,Object? reason = freezed,}) {
  return _then(TrackUnavailableEvent(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,unavailable: null == unavailable ? _self.unavailable : unavailable // ignore: cast_nullable_to_non_nullable
as bool,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class PlaybackErrorEvent implements PlayQueueEvent {
  const PlaybackErrorEvent({required this.message, required this.seq});
  

 final  String message;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackErrorEventCopyWith<PlaybackErrorEvent> get copyWith => _$PlaybackErrorEventCopyWithImpl<PlaybackErrorEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackErrorEvent&&(identical(other.message, message) || other.message == message)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,message,seq);

@override
String toString() {
  return 'PlayQueueEvent.playbackError(message: $message, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $PlaybackErrorEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $PlaybackErrorEventCopyWith(PlaybackErrorEvent value, $Res Function(PlaybackErrorEvent) _then) = _$PlaybackErrorEventCopyWithImpl;
@override @useResult
$Res call({
 String message, int seq
});




}
/// @nodoc
class _$PlaybackErrorEventCopyWithImpl<$Res>
    implements $PlaybackErrorEventCopyWith<$Res> {
  _$PlaybackErrorEventCopyWithImpl(this._self, this._then);

  final PlaybackErrorEvent _self;
  final $Res Function(PlaybackErrorEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? seq = null,}) {
  return _then(PlaybackErrorEvent(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class PlaybackModeChangedEvent implements PlayQueueEvent {
  const PlaybackModeChangedEvent({required this.mode, required this.seq});
  

 final  PlaybackMode mode;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackModeChangedEventCopyWith<PlaybackModeChangedEvent> get copyWith => _$PlaybackModeChangedEventCopyWithImpl<PlaybackModeChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackModeChangedEvent&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,mode,seq);

@override
String toString() {
  return 'PlayQueueEvent.playbackModeChanged(mode: $mode, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $PlaybackModeChangedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $PlaybackModeChangedEventCopyWith(PlaybackModeChangedEvent value, $Res Function(PlaybackModeChangedEvent) _then) = _$PlaybackModeChangedEventCopyWithImpl;
@override @useResult
$Res call({
 PlaybackMode mode, int seq
});




}
/// @nodoc
class _$PlaybackModeChangedEventCopyWithImpl<$Res>
    implements $PlaybackModeChangedEventCopyWith<$Res> {
  _$PlaybackModeChangedEventCopyWithImpl(this._self, this._then);

  final PlaybackModeChangedEvent _self;
  final $Res Function(PlaybackModeChangedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? seq = null,}) {
  return _then(PlaybackModeChangedEvent(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as PlaybackMode,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ReplayPlayQueueEvent implements PlayQueueEvent {
  const ReplayPlayQueueEvent({required this.state, required this.serverTimeNs, required this.seq});
  

 final  PlayQueueState state;
 final  int serverTimeNs;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplayPlayQueueEventCopyWith<ReplayPlayQueueEvent> get copyWith => _$ReplayPlayQueueEventCopyWithImpl<ReplayPlayQueueEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplayPlayQueueEvent&&(identical(other.state, state) || other.state == state)&&(identical(other.serverTimeNs, serverTimeNs) || other.serverTimeNs == serverTimeNs)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,state,serverTimeNs,seq);

@override
String toString() {
  return 'PlayQueueEvent.replayEvent(state: $state, serverTimeNs: $serverTimeNs, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $ReplayPlayQueueEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $ReplayPlayQueueEventCopyWith(ReplayPlayQueueEvent value, $Res Function(ReplayPlayQueueEvent) _then) = _$ReplayPlayQueueEventCopyWithImpl;
@override @useResult
$Res call({
 PlayQueueState state, int serverTimeNs, int seq
});




}
/// @nodoc
class _$ReplayPlayQueueEventCopyWithImpl<$Res>
    implements $ReplayPlayQueueEventCopyWith<$Res> {
  _$ReplayPlayQueueEventCopyWithImpl(this._self, this._then);

  final ReplayPlayQueueEvent _self;
  final $Res Function(ReplayPlayQueueEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? serverTimeNs = null,Object? seq = null,}) {
  return _then(ReplayPlayQueueEvent(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PlayQueueState,serverTimeNs: null == serverTimeNs ? _self.serverTimeNs : serverTimeNs // ignore: cast_nullable_to_non_nullable
as int,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RenderersChangedEvent implements PlayQueueEvent {
  const RenderersChangedEvent({required final  List<RendererInfo> renderers, required this.seq}): _renderers = renderers;
  

 final  List<RendererInfo> _renderers;
 List<RendererInfo> get renderers {
  if (_renderers is EqualUnmodifiableListView) return _renderers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_renderers);
}

@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RenderersChangedEventCopyWith<RenderersChangedEvent> get copyWith => _$RenderersChangedEventCopyWithImpl<RenderersChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RenderersChangedEvent&&const DeepCollectionEquality().equals(other._renderers, _renderers)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_renderers),seq);

@override
String toString() {
  return 'PlayQueueEvent.renderersChanged(renderers: $renderers, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $RenderersChangedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $RenderersChangedEventCopyWith(RenderersChangedEvent value, $Res Function(RenderersChangedEvent) _then) = _$RenderersChangedEventCopyWithImpl;
@override @useResult
$Res call({
 List<RendererInfo> renderers, int seq
});




}
/// @nodoc
class _$RenderersChangedEventCopyWithImpl<$Res>
    implements $RenderersChangedEventCopyWith<$Res> {
  _$RenderersChangedEventCopyWithImpl(this._self, this._then);

  final RenderersChangedEvent _self;
  final $Res Function(RenderersChangedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? renderers = null,Object? seq = null,}) {
  return _then(RenderersChangedEvent(
renderers: null == renderers ? _self._renderers : renderers // ignore: cast_nullable_to_non_nullable
as List<RendererInfo>,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CurrentRendererChangedEvent implements PlayQueueEvent {
  const CurrentRendererChangedEvent({this.rendererId, this.selectedRendererId, required this.seq});
  

 final  String? rendererId;
 final  String? selectedRendererId;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CurrentRendererChangedEventCopyWith<CurrentRendererChangedEvent> get copyWith => _$CurrentRendererChangedEventCopyWithImpl<CurrentRendererChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CurrentRendererChangedEvent&&(identical(other.rendererId, rendererId) || other.rendererId == rendererId)&&(identical(other.selectedRendererId, selectedRendererId) || other.selectedRendererId == selectedRendererId)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,rendererId,selectedRendererId,seq);

@override
String toString() {
  return 'PlayQueueEvent.currentRendererChanged(rendererId: $rendererId, selectedRendererId: $selectedRendererId, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $CurrentRendererChangedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $CurrentRendererChangedEventCopyWith(CurrentRendererChangedEvent value, $Res Function(CurrentRendererChangedEvent) _then) = _$CurrentRendererChangedEventCopyWithImpl;
@override @useResult
$Res call({
 String? rendererId, String? selectedRendererId, int seq
});




}
/// @nodoc
class _$CurrentRendererChangedEventCopyWithImpl<$Res>
    implements $CurrentRendererChangedEventCopyWith<$Res> {
  _$CurrentRendererChangedEventCopyWithImpl(this._self, this._then);

  final CurrentRendererChangedEvent _self;
  final $Res Function(CurrentRendererChangedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rendererId = freezed,Object? selectedRendererId = freezed,Object? seq = null,}) {
  return _then(CurrentRendererChangedEvent(
rendererId: freezed == rendererId ? _self.rendererId : rendererId // ignore: cast_nullable_to_non_nullable
as String?,selectedRendererId: freezed == selectedRendererId ? _self.selectedRendererId : selectedRendererId // ignore: cast_nullable_to_non_nullable
as String?,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class PlaybackControlChangedEvent implements PlayQueueEvent {
  const PlaybackControlChangedEvent({required this.control, required this.seq});
  

 final  PlaybackControl control;
@override final  int seq;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackControlChangedEventCopyWith<PlaybackControlChangedEvent> get copyWith => _$PlaybackControlChangedEventCopyWithImpl<PlaybackControlChangedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackControlChangedEvent&&(identical(other.control, control) || other.control == control)&&(identical(other.seq, seq) || other.seq == seq));
}


@override
int get hashCode => Object.hash(runtimeType,control,seq);

@override
String toString() {
  return 'PlayQueueEvent.playbackControlChanged(control: $control, seq: $seq)';
}


}

/// @nodoc
abstract mixin class $PlaybackControlChangedEventCopyWith<$Res> implements $PlayQueueEventCopyWith<$Res> {
  factory $PlaybackControlChangedEventCopyWith(PlaybackControlChangedEvent value, $Res Function(PlaybackControlChangedEvent) _then) = _$PlaybackControlChangedEventCopyWithImpl;
@override @useResult
$Res call({
 PlaybackControl control, int seq
});




}
/// @nodoc
class _$PlaybackControlChangedEventCopyWithImpl<$Res>
    implements $PlaybackControlChangedEventCopyWith<$Res> {
  _$PlaybackControlChangedEventCopyWithImpl(this._self, this._then);

  final PlaybackControlChangedEvent _self;
  final $Res Function(PlaybackControlChangedEvent) _then;

/// Create a copy of PlayQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? control = null,Object? seq = null,}) {
  return _then(PlaybackControlChangedEvent(
control: null == control ? _self.control : control // ignore: cast_nullable_to_non_nullable
as PlaybackControl,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
