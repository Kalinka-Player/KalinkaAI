import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';

// Bit-perfection is claimed from two messages that arrive apart: the device
// path with the playback state, the volume with the device it is applied by.

const _exclusive = OutputInfo(
  sampleRate: 44100,
  bitsPerSample: 16,
  channels: 2,
  access: DeviceAccess.exclusive,
  losslessPath: true,
);

const _shared = OutputInfo(
  sampleRate: 44100,
  bitsPerSample: 16,
  channels: 2,
  access: DeviceAccess.shared,
);

DeviceVolume _volume(VolumeBackend backend, {int current = 100}) =>
    DeviceVolume(
      currentVolume: current,
      maxVolume: 100,
      volumeGain: 0,
      supported: true,
      backend: backend,
    );

void main() {
  group('isBitPerfect', () {
    test('an unaltered path with the volume out of the way', () {
      expect(isBitPerfect(_exclusive, _volume(VolumeBackend.hardware)), isTrue);
      expect(isBitPerfect(_exclusive, _volume(VolumeBackend.none)), isTrue);
    });

    test('software volume is only harmless at unity', () {
      expect(isBitPerfect(_exclusive, _volume(VolumeBackend.software)), isTrue);
      expect(
        isBitPerfect(_exclusive, _volume(VolumeBackend.software, current: 99)),
        isFalse,
      );
    });

    test('hardware attenuation leaves the samples alone', () {
      expect(
        isBitPerfect(_exclusive, _volume(VolumeBackend.hardware, current: 40)),
        isTrue,
      );
    });

    test('a backend nobody has named is not taken on trust', () {
      expect(isBitPerfect(_exclusive, _volume(VolumeBackend.unknown)), isFalse);
    });

    test('an altered path is not rescued by the volume', () {
      expect(isBitPerfect(_shared, _volume(VolumeBackend.hardware)), isFalse);
    });

    test('a renderer that reports a signal path altered the samples', () {
      const processed = OutputInfo(
        access: DeviceAccess.exclusive,
        losslessPath: true,
        signalPath: SignalPath(steps: [SignalStep(kind: 'dither')]),
      );
      expect(isBitPerfect(processed, _volume(VolumeBackend.hardware)), isFalse);
    });

    test('a path whose every step keeps the bits is still bit-perfect', () {
      const padded = OutputInfo(
        access: DeviceAccess.exclusive,
        losslessPath: true,
        signalPath: SignalPath(
          steps: [
            SignalStep(kind: 'float', bitPerfect: true),
            SignalStep(kind: 'integer', bitPerfect: true),
          ],
        ),
      );
      expect(isBitPerfect(padded, _volume(VolumeBackend.hardware)), isTrue);
    });

    test('one step that alters the samples is enough', () {
      const altered = OutputInfo(
        access: DeviceAccess.exclusive,
        losslessPath: true,
        signalPath: SignalPath(
          steps: [
            SignalStep(kind: 'zero_padding', bitPerfect: true),
            SignalStep(kind: 'peq'),
          ],
        ),
      );
      expect(isBitPerfect(altered, _volume(VolumeBackend.hardware)), isFalse);
    });

    test('a renderer that reports no device claims nothing', () {
      expect(isBitPerfect(null, _volume(VolumeBackend.hardware)), isFalse);
    });
  });

  group('the wire', () {
    test('a server that reports no output is not a server reporting false', () {
      final info = AudioInfo.fromJson({
        "sample_rate": 44100,
        "bits_per_sample": 16,
        "channels": 2,
        "duration_ms": 1000,
      });

      expect(info.output, isNull);
      expect(
        isBitPerfect(info.output, _volume(VolumeBackend.hardware)),
        isFalse,
      );
    });

    test('the output side survives the round trip', () {
      final info = AudioInfo.fromJson({
        "sample_rate": 44100,
        "bits_per_sample": 16,
        "channels": 2,
        "duration_ms": 1000,
        "output": {
          "sample_rate": 44100,
          "bits_per_sample": 16,
          "channels": 2,
          "access": "exclusive",
          "lossless_path": true,
        },
      });

      expect(info.output!.access, DeviceAccess.exclusive);
      expect(info.output!.losslessPath, isTrue);
      expect(info.output!.sampleRate, 44100);
    });

    test('a volume without a named backend reads as unknown', () {
      final volume = DeviceVolume.fromJson({
        "current_volume": 100,
        "max_volume": 100,
        "volume_gain": 0,
        "supported": true,
      });

      expect(volume.backend, VolumeBackend.unknown);
    });

    test('an unrecognised backend is unknown, not the last one that fit', () {
      final volume = DeviceVolume.fromJson({
        "current_volume": 100,
        "max_volume": 100,
        "volume_gain": 0,
        "supported": true,
        "backend": "something-newer",
      });

      expect(volume.backend, VolumeBackend.unknown);
    });
  });
}
