import 'package:flutter/material.dart';

import '../data_model/data_model.dart';
import '../theme/app_theme.dart';

/// One figure of the DSP read-out; [alarm] marks one that says the signal
/// was damaged.
typedef DspReading = ({String label, String value, bool alarm});

/// The renderer's processing as figures: the latency its signal path adds,
/// and the samples its DSP clipped, once [playbackEvents] (the latest details
/// of each kind in the play) report clipping.
List<DspReading> dspReadings(
  SignalPath? path,
  Map<String, Map<String, Object?>> playbackEvents,
) => [
  if (path != null && path.latencyMs > 0)
    (label: 'DSP latency', value: '${_trim(path.latencyMs)} ms', alarm: false),
  if (playbackEvents['clipping']?['clipped_samples'] case final num clipped
      when clipped > 0)
    (label: 'Clipped', value: '${clipped.toInt()}', alarm: true),
];

String _trim(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

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
