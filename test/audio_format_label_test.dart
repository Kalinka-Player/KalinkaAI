import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/utils/playback_utils.dart';

void main() {
  test('codec takes precedence over a container or manifest MIME type', () {
    for (final (mime, codec, label) in [
      ('application/dash+xml', 'flac', 'FLAC'),
      ('application/dash+xml', 'aac', 'AAC'),
      ('audio/mp4', 'FLAC', 'FLAC'),
      ('audio/mp4', 'mp4a.40.2', 'AAC'),
      ('audio/mp4', 'mp4a.40.5', 'AAC'),
      ('audio/mp4', 'mp4a.40.29', 'AAC'),
      ('audio/mp4', 'mp4a.40.999', 'MP4A.40.999'),
      ('audio/mp4', 'alac', 'ALAC'),
      ('audio/ogg', 'opus', 'OPUS'),
      ('audio/ogg', 'vorbis', 'VORBIS'),
      ('application/dash+xml', '  fLaC  ', 'FLAC'),
      ('application/dash+xml', 'ec-3', 'EC-3'),
      ('application/vnd.kalinka.pcm', 'pcm', 'PCM'),
      (null, 'aac', 'AAC'),
    ]) {
      expect(audioFormatLabel(mime, audioCodec: codec), label);
    }
  });

  test(
    'legacy sources keep their labels, with no guess at an unknown codec',
    () {
      for (final (mime, label) in [
        ('audio/flac', 'FLAC'),
        ('audio/mpeg', 'MP3'),
        ('audio/mp4', 'MP4'),
        ('application/dash+xml', 'DASH+XML'),
        ('application/vnd.kalinka.pcm', 'PCM'),
        (null, ''),
      ]) {
        for (final codec in [null, '', '  ']) {
          expect(audioFormatLabel(mime, audioCodec: codec), label);
        }
      }
    },
  );

  test('codec survives JSON and local state copies', () {
    final state = PlaybackState.fromJson({
      'state': 'PLAYING',
      'mime_type': 'application/dash+xml',
      'audio_codec': 'flac',
    });
    expect(state.mimeType, 'application/dash+xml');
    expect(state.audioCodec, 'flac');
    expect(PlaybackState.fromJson(state.toJson()).audioCodec, 'flac');
    expect(state.copyWithFields(position: 1000).audioCodec, 'flac');
    expect(state.withoutTrack().audioCodec, 'flac');
    expect(
      PlaybackState.fromJson({'mime_type': 'audio/mpeg'}).audioCodec,
      isNull,
    );
  });
}
