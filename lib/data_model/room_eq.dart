import 'dart:math' as math;

import '../generated/kalinka/renderer/v1/renderer.pb.dart' as wire;

enum FilterShape {
  peak('Peak', 'PK'),
  lowShelf('Low shelf', 'LSQ'),
  highShelf('High shelf', 'HSQ'),
  lowPass('Low pass · 12 dB/oct', 'LPQ', slope: 12),
  highPass('High pass · 12 dB/oct', 'HPQ', slope: 12),
  firstOrderLowPass('Low pass · 6 dB/oct', 'LP1', slope: 6),
  firstOrderHighPass('High pass · 6 dB/oct', 'HP1', slope: 6);

  final String label, rew;
  final int? slope;
  const FilterShape(this.label, this.rew, {this.slope});
  bool get hasGain => slope == null;
  bool get hasQ => slope != 6;
  bool get isLowPass => this == lowPass || this == firstOrderLowPass;
}

class EqBand {
  final FilterShape shape;
  final double hz;
  final double? _gain, _q;
  double get gain => shape.hasGain ? (_gain ?? 3) : 0;
  double get q => shape.hasQ ? (_q ?? (shape.hasGain ? 1 : math.sqrt1_2)) : 0;
  bool get active => !shape.hasGain || gain != 0;

  /// Gain at the band's characteristic frequency, in dB.
  double get handleGain => switch (shape) {
    FilterShape.peak => gain,
    FilterShape.lowShelf || FilterShape.highShelf => gain / 2,
    FilterShape.lowPass || FilterShape.highPass => 20 * math.log(q) / math.ln10,
    _ => -10 * math.ln2 / math.ln10,
  };
  const EqBand({
    this.shape = FilterShape.peak,
    this.hz = 1000,
    this._gain,
    this._q,
  });

  EqBand change({FilterShape? shape, double? hz, double? gain, double? q}) =>
      EqBand(
        shape: shape ?? this.shape,
        hz: hz ?? this.hz,
        gain: gain ?? this.gain,
        q: q ?? (this.shape.hasQ ? this.q : null),
      );

  factory EqBand.decode(wire.DspProfile_Band band) {
    final shape = switch (band.type) {
      wire.DspProfile_Band_Type.PEAK => FilterShape.peak,
      wire.DspProfile_Band_Type.LOW_SHELF => FilterShape.lowShelf,
      wire.DspProfile_Band_Type.HIGH_SHELF => FilterShape.highShelf,
      wire.DspProfile_Band_Type.LOW_PASS => FilterShape.lowPass,
      wire.DspProfile_Band_Type.HIGH_PASS => FilterShape.highPass,
      wire.DspProfile_Band_Type.FIRST_ORDER_LOW_PASS =>
        FilterShape.firstOrderLowPass,
      wire.DspProfile_Band_Type.FIRST_ORDER_HIGH_PASS =>
        FilterShape.firstOrderHighPass,
      _ => throw const FormatException('Unsupported filter type'),
    };
    if (!band.frequencyHz.isFinite ||
        band.frequencyHz <= 0 ||
        band.frequencyHz > 384000 ||
        !band.gainDb.isFinite ||
        (shape.hasGain ? band.gainDb.abs() > 30 : band.gainDb != 0) ||
        !band.q.isFinite ||
        (shape.hasQ ? band.q < 0.01 || band.q > 1000 : band.q != 0)) {
      throw const FormatException(
        'Invalid frequency, gain or Q in the room preset.',
      );
    }
    return EqBand(
      shape: shape,
      hz: band.frequencyHz,
      gain: band.gainDb,
      q: band.q,
    );
  }

  /// The same biquads as the renderer, evaluated on the unit circle.
  double Function(double radians) response(double rate) {
    final w = 2 * math.pi * hz / rate;
    final c = math.cos(w);
    final alpha = shape.hasQ ? math.sin(w) / (2 * q) : 0.0;
    final a = math.pow(10, gain / 40).toDouble();
    final (double, double, double, double, double, double) coefficients;
    if (!shape.hasQ) {
      final k = math.tan(w / 2);
      final b = shape.isLowPass ? k : 1.0;
      coefficients = (b, shape.isLowPass ? b : -b, 0, 1 + k, k - 1, 0);
    } else if (!shape.hasGain) {
      final sign = shape.isLowPass ? 1 : -1;
      final b = (1 - sign * c) / 2;
      coefficients = (b, sign * 2 * b, b, 1 + alpha, -2 * c, 1 - alpha);
    } else if (shape == FilterShape.peak) {
      coefficients = (
        1 + alpha * a,
        -2 * c,
        1 - alpha * a,
        1 + alpha / a,
        -2 * c,
        1 - alpha / a,
      );
    } else {
      final sign = shape == FilterShape.lowShelf ? 1 : -1;
      final p = a + 1, m = a - 1, b = 2 * math.sqrt(a) * alpha;
      final num = p - sign * m * c, den = p + sign * m * c;
      coefficients = (
        a * (num + b),
        2 * a * (sign * m - p * c),
        a * (num - b),
        den + b,
        -2 * (sign * m + p * c),
        den - b,
      );
    }
    final (b0, b1, b2, a0, a1, a2) = coefficients;
    return (omega) {
      final cos = math.cos(omega), sin = math.sin(omega);
      double power(double x, double y, double z) {
        final real = (x + z) * cos + y, imag = (x - z) * sin;
        return real * real + imag * imag;
      }

      return 10 / math.ln10 * math.log(power(b0, b1, b2) / power(a0, a1, a2));
    };
  }
}

/// REW Generic accepts plain decimal numbers. Dart switches to exponent
/// notation for very small values, including valid near-unity gains.
String _rewNumber(double value) {
  final text = value.toString();
  final exponentAt = text.indexOf('e');
  if (exponentAt < 0) return text;
  final mantissa = text.substring(0, exponentAt).replaceFirst('-', '');
  final digits = mantissa.replaceAll('.', '');
  final place = 1 + int.parse(text.substring(exponentAt + 1));
  final sign = value.isNegative ? '-' : '';
  if (place <= 0) return '${sign}0.${'0' * (-place)}$digits';
  if (place >= digits.length) {
    return '$sign$digits${'0' * (place - digits.length)}';
  }
  return '$sign${digits.substring(0, place)}.${digits.substring(place)}';
}

enum EqChannel { shared, left, right }

class EqCurve {
  final String name;
  final Map<EqChannel, List<EqBand>> channels;
  EqCurve(this.name, Map<EqChannel, List<EqBand>> channels)
    : channels = Map.unmodifiable(
        channels.map((k, v) => MapEntry(k, List<EqBand>.unmodifiable(v))),
      );
  factory EqCurve.empty() => EqCurve('', {EqChannel.shared: []});

  factory EqCurve.fromBytes(List<int> bytes) {
    final profile = wire.DspProfile.fromBuffer(bytes);
    if (profile.version != 1) {
      throw const FormatException('Unsupported room profile version');
    }
    if (profile.shared.isNotEmpty &&
            (profile.left.isNotEmpty || profile.right.isNotEmpty) ||
        [
          profile.shared,
          profile.left,
          profile.right,
        ].any((list) => list.length > 20)) {
      throw const FormatException('Unsupported room preset channel layout.');
    }
    List<EqBand> bands(List<wire.DspProfile_Band> values) =>
        values.map(EqBand.decode).toList();
    return EqCurve(
      profile.name,
      profile.shared.isNotEmpty
          ? {EqChannel.shared: bands(profile.shared)}
          : {
              EqChannel.left: bands(profile.left),
              EqChannel.right: bands(profile.right),
            },
    );
  }

  EqCurve withBands(EqChannel channel, List<EqBand> bands) =>
      EqCurve(name, {...channels, channel: bands});

  Map<String, String> toRew(String title) => {
    'name': title,
    for (final entry in channels.entries)
      entry.key.name: [
        'Equaliser: Generic',
        if (entry.value.isEmpty) 'Filter 1: OFF None',
        for (final (i, b) in entry.value.indexed)
          [
            'Filter ${i + 1}: ON ${b.shape.rew} Fc ${_rewNumber(b.hz)} Hz',
            if (b.shape.hasGain) 'Gain ${_rewNumber(b.gain)} dB',
            if (b.shape.hasQ) 'Q ${_rewNumber(b.q)}',
          ].join(' '),
      ].join('\n'),
  };
}
