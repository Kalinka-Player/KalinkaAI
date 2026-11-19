import 'package:flutter/material.dart';

import '../data_model/data_model.dart';
import '../theme/app_theme.dart';

/// One figure of the DSP read-out; [alarm] marks one that says the signal
/// was damaged.
typedef DspReading = ({String label, String value, bool alarm});

/// The renderer's processing as figures: the latency its signal path adds,
/// and what it measured of the track while [meters] are live.
List<DspReading> dspReadings(SignalPath? path, DspMeters? meters) => [
  if (path != null && path.latencyMs > 0)
    (label: 'DSP latency', value: '${_trim(path.latencyMs)} ms', alarm: false),
  if (meters != null) ...[
    (
      label: 'Clipped',
      value: '${meters.clippedSamples}',
      alarm: meters.clippedSamples > 0,
    ),
    (label: 'True peak', value: _peak(meters.truePeakDbfs), alarm: false),
    (
      label: 'DSP load',
      value: '${(meters.load * 100).toStringAsFixed(1)}%',
      alarm: false,
    ),
  ],
];

String _trim(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String _peak(double dbfs) {
  if (dbfs <= DspMeters.silence) return '—';
  return '${dbfs > 0 ? '+' : ''}${dbfs.toStringAsFixed(1)} dBFS';
}

/// [DspReading]s laid out as labelled figures, wrapping onto more rows when
/// the width runs out.
class DspReadout extends StatelessWidget {
  final List<DspReading> readings;

  const DspReadout(this.readings, {super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 8,
    children: [
      for (final reading in readings)
        MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reading.label.toUpperCase(),
                style: KalinkaTextStyles.streamInfoLabel,
              ),
              Text(
                reading.value,
                style: reading.alarm
                    ? KalinkaTextStyles.streamInfoValue.copyWith(
                        color: KalinkaColors.statusError,
                      )
                    : KalinkaTextStyles.streamInfoValue,
              ),
            ],
          ),
        ),
    ],
  );
}
