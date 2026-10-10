import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/bit_perfect_provider.dart';
import '../providers/playback_time_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// One labelled line of the stream-info read-out.
typedef StreamInfoField = ({String label, String value});

/// What the server reports about the stream that is playing, as the dialog
/// lists it. Empty when nothing is loaded.
///
/// A debug read-out, so values are shown as the server sends them and a field
/// it says nothing about is left out rather than shown blank. The two the
/// state cannot answer are passed in: [positionMs], which is extrapolated
/// because the state carries only the last sample, and [bitPerfect], which
/// also needs the volume.
List<StreamInfoField> streamInfoFields(
  PlaybackState state, {
  required int positionMs,
  required int queueLength,
  required bool bitPerfect,
  bool exclusive = false,
}) {
  // currentTrack is sticky by design — it survives Clear All so the transport
  // has something to show. An empty queue has no loaded local stream, but an
  // external source can play independently of the saved queue.
  final track = state.currentTrack;
  if (track == null || (queueLength == 0 && !exclusive)) return const [];

  final audio = state.audioInfo;
  final output = audio?.output;
  final durationMs = (audio?.durationMs ?? 0) > 0
      ? audio!.durationMs
      : track.duration * 1000;
  final decoded = audio == null
      ? ''
      : _stream(audio.bitsPerSample, audio.sampleRate, audio.channels);

  return [
    (label: 'Title', value: track.title),
    if (track.album != null) (label: 'Album', value: _album(track.album!)),
    (label: 'ID', value: track.id),
    if (state.state != null) (label: 'State', value: state.state!.toValue()),
    if (state.index != null && !exclusive)
      (label: 'Index', value: '${state.index} / $queueLength'),
    (label: 'Position', value: formatClock(Duration(milliseconds: positionMs))),
    if (durationMs > 0)
      (
        label: 'Duration',
        value: formatClock(Duration(milliseconds: durationMs)),
      ),
    if (state.mimeType != null) (label: 'Format', value: state.mimeType!),
    if (decoded.isNotEmpty) (label: 'Decoded', value: decoded),
    if (output != null)
      (
        label: 'Output',
        value:
            '${_stream(output.bitsPerSample, output.sampleRate, output.channels)}'
            ' · ${output.access.name}',
      ),
    // Never "no": the badge's absence means nothing established it, which is
    // not the same as knowing the samples were altered.
    if (output != null)
      (label: 'Path', value: bitPerfect ? 'Bit-perfect' : 'Not established'),
    if (state.streamUrl != null) (label: 'URL', value: state.streamUrl!),
  ];
}

String _album(Album album) =>
    album.year != null ? '${album.title} · ${album.year}' : album.title;

String _stream(int bitsPerSample, int sampleRate, int channels) {
  final khz = sampleRate % 1000 == 0
      ? (sampleRate / 1000).toStringAsFixed(0)
      : (sampleRate / 1000).toStringAsFixed(1);
  return [
    if (bitsPerSample > 0) '$bitsPerSample-bit',
    if (sampleRate > 0) '$khz kHz',
    if (channels > 0) '$channels ch',
  ].join(' · ');
}

/// Technical read-out of the stream now playing, for when what comes out of
/// the speakers needs explaining. Show via [showKalinkaDialog].
class StreamInfoDialog extends ConsumerWidget {
  const StreamInfoDialog({super.key});

  /// Past this the fields scroll rather than growing the card.
  static const double _maxFieldsHeight = 300;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = streamInfoFields(
      ref.watch(playerStateProvider),
      positionMs: ref.watch(playbackTimeMsProvider),
      queueLength: ref.watch(
        playQueueStateStoreProvider.select((s) => s.trackList.length),
      ),
      bitPerfect: ref.watch(bitPerfectProvider),
      exclusive: ref.watch(
        playbackControlProvider.select((c) => c.isExclusive),
      ),
    );

    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      // Greyscale, not accent — this reports, it isn't a CTA.
      icon: Icons.info_outline,
      iconColor: KalinkaColors.textMuted,
      title: 'Stream info',
      message: fields.isEmpty ? 'Nothing is playing.' : null,
      content: fields.isEmpty ? null : _buildFields(context, fields),
      actions: [
        if (fields.isNotEmpty)
          KalinkaButton(
            label: 'Copy',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            onTap: () {
              // Captured before the pop: the dialog's ref goes with it.
              final toast = ref.read(toastProvider.notifier);
              Clipboard.setData(
                ClipboardData(
                  text: fields.map((f) => '${f.label}: ${f.value}').join('\n'),
                ),
              );
              Navigator.pop(context);
              toast.show('Stream info copied', inPanel: true);
            },
          ),
        KalinkaButton(
          label: 'Close',
          fullWidth: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildFields(BuildContext context, List<StreamInfoField> fields) {
    // A share of the window as well as a fixed cap, or a phone held landscape
    // has no room left for the title and the actions.
    final height = MediaQuery.sizeOf(context).height * 0.4;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: height < _maxFieldsHeight ? height : _maxFieldsHeight,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final field in fields) _FieldRow(field)],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final StreamInfoField field;

  const _FieldRow(this.field);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              field.label.toUpperCase(),
              style: KalinkaTextStyles.streamInfoLabel,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              field.value,
              style: KalinkaTextStyles.streamInfoValue,
              // Long enough for a CDN URL, short enough that one field cannot
              // push the rest out of view.
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
