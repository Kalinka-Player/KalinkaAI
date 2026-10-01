import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/kalinka_ws_api_provider.dart';

/// Sends the appropriate play/pause command based on the current player state.
///
/// [exclusive] is playback a plugin drives outside the queue: pause and resume
/// go to it, and nothing starts the queue, which would take the output back.
void sendPlayPauseCommand(
  WidgetRef ref,
  PlayerStateType? playerState, {
  bool exclusive = false,
}) {
  final api = ref.read(kalinkaWsApiProvider);
  if (isPlayPauseDisabled(playerState, exclusive: exclusive)) return;

  // A failed track is stopped as far as the transport is concerned, so play
  // means "try it again" — the only retry the app offers.
  if (playerState == PlayerStateType.stopped ||
      playerState == PlayerStateType.error) {
    api.sendQueueCommand(const QueueCommand.play());
  } else if (playerState == PlayerStateType.paused) {
    api.sendQueueCommand(const QueueCommand.pause(paused: false));
  } else if (playerState == PlayerStateType.playing) {
    api.sendQueueCommand(const QueueCommand.pause(paused: true));
  }
}

/// Returns the appropriate icon for the current player state.
IconData playPauseIcon(PlayerStateType? playerState, {double? size}) {
  if (playerState == PlayerStateType.playing) {
    return Icons.pause;
  } else if (playerState == PlayerStateType.buffering) {
    return Icons.hourglass_bottom;
  }
  return Icons.play_arrow;
}

/// Returns the appropriate filled icon for the current player state.
IconData playPauseFilledIcon(PlayerStateType? playerState) {
  if (playerState == PlayerStateType.playing) {
    return Icons.pause_circle_filled;
  } else if (playerState == PlayerStateType.buffering) {
    return Icons.hourglass_bottom;
  }
  return Icons.play_circle_filled;
}

/// Whether the play/pause button should be disabled: while buffering, and for
/// [exclusive] playback that is not playing or paused, which only its own app
/// starts.
bool isPlayPauseDisabled(
  PlayerStateType? playerState, {
  bool exclusive = false,
}) {
  if (exclusive) {
    return playerState != PlayerStateType.playing &&
        playerState != PlayerStateType.paused;
  }
  return playerState == PlayerStateType.buffering;
}

/// The playback clock as the app writes it everywhere: `m:ss`, and never a
/// negative one — a position before the start reads as the start.
String formatClock(Duration position) {
  final seconds = position.isNegative ? 0 : position.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Short codec name for a stream's MIME type — `FLAC`, `MP3` — or empty.
String mimeTypeLabel(String? mimeType) {
  if (mimeType == null) return '';
  if (mimeType.contains('flac')) return 'FLAC';
  if (mimeType.contains('wav')) return 'WAV';
  if (mimeType.contains('mp3') || mimeType.contains('mpeg')) return 'MP3';
  if (mimeType.contains('aac')) return 'AAC';
  if (mimeType.contains('ogg')) return 'OGG';
  if (mimeType.contains('opus')) return 'OPUS';
  return mimeType.split('/').last.toUpperCase();
}

/// Resolution of a stream — `24-bit • 96 kHz` — or empty when unknown.
String audioQualityLabel(AudioInfo? audioInfo, {String separator = ' • '}) {
  if (audioInfo == null) return '';
  final parts = <String>[];
  if (audioInfo.bitsPerSample > 0) {
    parts.add('${audioInfo.bitsPerSample}-bit');
  }
  final sampleRate = audioInfo.sampleRate;
  if (sampleRate > 0) {
    final khz = sampleRate / 1000;
    parts.add(
      '${sampleRate % 1000 == 0 ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1)} kHz',
    );
  }
  return parts.join(separator);
}
