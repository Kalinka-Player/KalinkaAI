import 'package:flutter/material.dart';

import '../data_model/data_model.dart';
import '../theme/app_theme.dart';
import '../utils/playback_utils.dart';

typedef SignalStage = ({String label, String detail, IconData icon});

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
  'stereo_expansion',
  'peq',
  'preamp',
  'dsd_gain',
  'dither',
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
      (label: 'Source', detail: origin, icon: Icons.library_music_outlined),
    if (decoded.isNotEmpty)
      (label: 'Decoded stream', detail: decoded, icon: Icons.graphic_eq),
    if (steps != null)
      for (final step in steps)
        (
          label: step.name.isNotEmpty ? step.name : step.kind,
          detail: step.summary,
          icon: Icons.tune,
        ),
    if (native)
      (label: 'Native DSD', detail: outputFormat, icon: Icons.swap_horiz),
    if (out != null && dop)
      (
        label: 'DSD over PCM',
        detail: _details([
          if (out.sampleRate > 0) '${_rate(out.sampleRate, 1000)} kHz carrier',
          out.sampleFormat,
        ]),
        icon: Icons.swap_horiz,
      ),
    if (steps == null && out != null && dsd && pcmOutput)
      (
        label: 'DSD to PCM',
        detail: _pcm(out.sampleRate, out.bitsPerSample, out.channels),
        icon: Icons.tune,
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
        label: 'Sample rate change',
        detail:
            '${_rate(audio.sampleRate, 1000)} → ${_rate(out.sampleRate, 1000)} kHz',
        icon: Icons.tune,
      ),
    if (out != null &&
        volume.backend == VolumeBackend.software &&
        volume.maxVolume > 0 &&
        volume.currentVolume < volume.maxVolume)
      (
        label: 'Software volume',
        detail: '${volume.currentVolume} / ${volume.maxVolume}',
        icon: Icons.volume_down_outlined,
      ),
    if (out != null)
      (
        label: 'Output',
        detail: destination.isEmpty ? 'Format unavailable' : destination,
        icon: Icons.speaker_outlined,
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
                        Text(
                          stages[i].label,
                          style: KalinkaTextStyles.trayRowLabel,
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
