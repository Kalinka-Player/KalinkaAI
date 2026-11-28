import 'package:flutter/material.dart';

import '../data_model/data_model.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';

/// One row of the path. [bitPerfect] marks a step 1:1 when it keeps every
/// bit and Altered when it does not; null for the rows that are no step:
/// the source, the decoded stream and the output.
typedef SignalStage = ({
  String kind,
  String label,
  String detail,
  IconData icon,
  bool? bitPerfect,
});

String _rate(int hz, int unit) {
  final precision = unit == 1000000 ? 6 : 3;
  return (hz / unit)
      .toStringAsFixed(precision)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}

String _dsdRate(int hz) {
  if (hz <= 0) return 'DSD';
  final multiple = hz % 44100 == 0 ? 'DSD${hz ~/ 44100}' : 'DSD';
  return '$multiple · ${_rate(hz, 1000000)} MHz';
}

String _details(List<String> parts) =>
    parts.where((part) => part.isNotEmpty).join(' · ');

String _channels(int n) => switch (n) {
  1 => 'Mono',
  2 => 'Stereo',
  > 2 => '$n channels',
  _ => '',
};

String _pcm(int hz, int bits, int channels) => _details([
  if (hz > 0) '${_rate(hz, 1000)} kHz',
  if (bits > 0) '$bits-bit',
  _channels(channels),
]);

/// Signal step kinds that leave the sample rate as it was: with only these, a
/// rate change between the decoded stream and the output happened past the
/// renderer's DSP, in ALSA or a sound server.
const _rateKeepingSteps = {
  'channels',
  'float',
  'fir',
  'peq',
  'preamp',
  'dsd_gain',
  'volume',
  'dither',
  'integer',
  'zero_padding',
  'repack',
};

// Accept only identified PCM formats. A PCM-width carrier may contain DoP.
bool _isPcm(String name) =>
    name.startsWith('PCM') ||
    name.startsWith('FLOAT') ||
    RegExp(r'^[SF](16|24|32|64)(_|$)').hasMatch(name);

/// Ordered observations from this playback session. The output format is
/// authoritative for the transport; a rate difference alone cannot identify it.
/// A renderer that reports its signal path is authoritative for what it did,
/// so its steps stand in for the conversions inferred from the formats.
List<SignalStage> signalStages(
  PlaybackState state,
  DeviceVolume volume, {
  String? source,
  String? renderer,
  bool bitPerfect = false,
}) {
  if (state.currentTrack == null ||
      state.state == PlayerStateType.stopped ||
      state.state == PlayerStateType.error) {
    return const [];
  }
  final audio = state.audioInfo;
  final out = audio?.output;
  final codec = audioFormatLabel(state.mimeType, audioCodec: state.audioCodec);
  final dsd = audio?.sampleFormat == 'DSD';
  final outputFormat = out?.sampleFormat ?? '';
  final native = outputFormat.startsWith('DSD_');
  final dop = outputFormat.startsWith('DoP_');
  final pcmOutput = _isPcm(outputFormat);
  final steps = out?.signalPath?.steps;
  final software = volume.backend == VolumeBackend.software;
  final level = software && volume.maxVolume > 0
      ? '${volume.currentVolume} / ${volume.maxVolume}'
      : '';
  // A step of any other kind may resample, and the renderer then says so.
  final stepsMayResample =
      steps != null &&
      steps.any((step) => !_rateKeepingSteps.contains(step.kind));
  final decoded = audio == null
      ? ''
      : dsd
      ? _details([_dsdRate(audio.sampleRate), _channels(audio.channels)])
      : _pcm(audio.sampleRate, audio.bitsPerSample, audio.channels);
  final access = switch (out?.access) {
    DeviceAccess.exclusive => 'Exclusive access',
    DeviceAccess.shared => 'Shared access',
    _ => '',
  };
  final destination = _details([
    ?renderer,
    if (out != null && !native && !dop)
      _pcm(out.sampleRate, out.bitsPerSample, out.channels),
    access,
    if (bitPerfect) 'Bit-perfect',
  ]);
  final origin = _details([?source, codec]);
  return [
    if (origin.isNotEmpty)
      (
        kind: 'source',
        label: 'Source',
        detail: origin,
        icon: Icons.library_music_outlined,
        bitPerfect: null,
      ),
    if (decoded.isNotEmpty)
      (
        kind: 'decoded',
        label: 'Decoded stream',
        detail: decoded,
        icon: Icons.graphic_eq,
        bitPerfect: null,
      ),
    if (steps != null)
      for (final step in steps)
        (
          kind: step.kind,
          label: switch ((step.kind, step.name)) {
            ('preamp', 'Preamp' || '') => 'Headroom',
            (_, '') => step.kind,
            _ => step.name,
          },
          detail: step.kind == 'volume' && level.isNotEmpty
              ? level
              : step.summary,
          icon: switch (step.kind) {
            'fir' => Icons.waves_rounded,
            'peq' => Icons.equalizer_rounded,
            'preamp' => Icons.volume_up_outlined,
            'volume' => Icons.volume_down_outlined,
            'dither' => Icons.grain_rounded,
            'channels' => Icons.call_split_rounded,
            'float' ||
            'integer' ||
            'zero_padding' ||
            'repack' => Icons.swap_horiz,
            _ => Icons.tune,
          },
          // The slider moves ahead of the restated path.
          bitPerfect: step.kind == 'volume' && software
              ? volume.currentVolume >= volume.maxVolume
              : step.bitPerfect,
        ),
    if (native)
      (
        kind: 'dsd_native',
        label: 'Native DSD',
        detail: outputFormat,
        icon: Icons.swap_horiz,
        bitPerfect: true,
      ),
    if (out != null && dop)
      (
        kind: 'dop',
        label: 'DSD over PCM',
        detail: _details([
          if (out.sampleRate > 0) '${_rate(out.sampleRate, 1000)} kHz carrier',
          out.sampleFormat,
        ]),
        icon: Icons.swap_horiz,
        bitPerfect: true,
      ),
    if (steps == null && out != null && dsd && pcmOutput)
      (
        kind: 'dsd_to_pcm',
        label: 'DSD to PCM',
        detail: _pcm(out.sampleRate, out.bitsPerSample, out.channels),
        icon: Icons.tune,
        bitPerfect: false,
      ),
    if (!stepsMayResample &&
        audio != null &&
        _isPcm(audio.sampleFormat) &&
        out != null &&
        pcmOutput &&
        audio.sampleRate > 0 &&
        out.sampleRate > 0 &&
        audio.sampleRate != out.sampleRate)
      (
        kind: 'sample_rate_change',
        label: 'Sample rate change',
        detail:
            '${_rate(audio.sampleRate, 1000)} → ${_rate(out.sampleRate, 1000)} kHz',
        icon: Icons.tune,
        bitPerfect: false,
      ),
    // A renderer older than the trace leaves its software volume to the app.
    if (out != null &&
        software &&
        !(steps?.any((step) => step.kind == 'volume') ?? false) &&
        volume.maxVolume > 0 &&
        volume.currentVolume < volume.maxVolume)
      (
        kind: 'software_volume',
        label: 'Software volume',
        detail: level,
        icon: Icons.volume_down_outlined,
        bitPerfect: false,
      ),
    if (out != null)
      (
        kind: 'output',
        label: 'Output',
        detail: destination.isEmpty ? 'Format unavailable' : destination,
        icon: Icons.speaker_outlined,
        bitPerfect: null,
      ),
  ];
}

class AudioSignalPath extends StatelessWidget {
  final List<SignalStage> stages;

  const AudioSignalPath(this.stages, {super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < stages.length; i++)
        MergeSemantics(
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Icon(
                        stages[i].icon,
                        size: 19,
                        color: KalinkaColors.textSecondary,
                      ),
                      if (i + 1 < stages.length)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: KalinkaColors.borderDefault,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i + 1 < stages.length ? 14 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                stages[i].label,
                                style: KalinkaTextStyles.trayRowLabel,
                              ),
                            ),
                            if (stages[i].bitPerfect case final kept?)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: StepMark(bitPerfect: kept),
                              ),
                          ],
                        ),
                        if (stages[i].detail.isNotEmpty)
                          Text(
                            stages[i].detail,
                            style: KalinkaTextStyles.trayRowSublabel,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// What a screen reader says for a step's mark.
String stepMarkLabel(bool bitPerfect) =>
    bitPerfect ? 'Keeps every bit' : 'Alters the samples';

/// 1:1 for a step that keeps every bit; ≈ Altered for one that changes the
/// samples, which is often a choice and so reads as information, not a fault.
class StepMark extends StatelessWidget {
  final bool bitPerfect;

  const StepMark({super.key, required this.bitPerfect});

  @override
  Widget build(BuildContext context) => Semantics(
    label: stepMarkLabel(bitPerfect),
    excludeSemantics: true,
    child: Text(
      bitPerfect ? '1:1' : '≈ Altered',
      style: KalinkaTextStyles.bitPerfectBadge.copyWith(
        color: bitPerfect
            ? KalinkaColors.textSecondary
            : KalinkaColors.signalAltered,
      ),
    ),
  );
}
