import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

/// Slider control for bounded numeric ranges.
///
/// Accent track fill, a value readout that floats above the thumb, and range
/// labels beneath.
///
/// The readout updates live while dragging, but [onChanged] only fires on
/// release — so staging (and the "apply" banner) reflects committed values,
/// not every intermediate drag tick.
///
/// Values land on [step] boundaries, but the Material slider underneath is
/// always continuous: its discrete mode animates the thumb toward each stop
/// over a fixed 75 ms, which reads as the thumb lagging behind the finger for
/// the whole drag. Snapping here keeps the thumb glued to the touch and still
/// only ever reports a value the backend accepts.
class SettingsSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;

  /// Distance between the values this slider may report. Null or 0 leaves the
  /// range continuous.
  final double? step;
  final String? minLabel;
  final String? maxLabel;

  /// Formats a value for the live readout. Falls back to a plain numeric
  /// string when omitted.
  final String Function(num)? formatValue;

  /// Fired on release (drag end / tap), not on every intermediate value.
  final ValueChanged<double> onChanged;

  /// Tightens padding and gaps for dense contexts (e.g. the expert/about:config
  /// rows, which already supply their own label and outer padding).
  final bool dense;

  const SettingsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step,
    this.minLabel,
    this.maxLabel,
    this.formatValue,
    required this.onChanged,
    this.dense = false,
  });

  @override
  State<SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  // Track inset the Material slider reserves on each side for the overlay —
  // matches RoundSliderOverlayShape(14) below, so the floating readout lines up
  // with the thumb across the full range.
  static const double _trackInset = 14.0;

  double _lastHapticPosition = double.negativeInfinity;

  /// Live value while a drag is in progress; null when settled (the committed
  /// [widget.value] is shown). Kept local so dragging doesn't stage changes.
  double? _dragValue;

  @override
  void didUpdateWidget(covariant SettingsSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop the held drag value once the parent commits, avoiding a snap-back.
    if (_dragValue != null && widget.value != oldWidget.value) {
      _dragValue = null;
    }
  }

  String _format(num n) =>
      widget.formatValue?.call(n) ??
      n.toStringAsFixed(n == n.roundToDouble() ? 0 : 1);

  /// The nearest value on the step grid, measured from [SettingsSlider.min] so
  /// a range that doesn't start at zero still lands on its own stops.
  double _snap(double value) {
    final step = widget.step;
    if (step == null || step <= 0) return value;
    final snapped = widget.min + ((value - widget.min) / step).round() * step;
    return snapped.clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final dense = widget.dense;
    final hasLabel = widget.label.isNotEmpty;
    final liveValue = (_dragValue ?? widget.value)
        .clamp(widget.min, widget.max)
        .toDouble();
    final range = widget.max - widget.min;
    final fraction = range > 0 ? (liveValue - widget.min) / range : 0.0;

    final valueText = Text(
      _format(liveValue),
      maxLines: 1,
      softWrap: false,
      style: KalinkaTextStyles.trayRowLabel.copyWith(
        fontSize: KalinkaTypography.baseSize + 1,
        fontWeight: FontWeight.w500,
        color: KalinkaColors.accent,
      ),
    );

    final sliderControl = SliderTheme(
      data: SliderThemeData(
        activeTrackColor: KalinkaColors.accent,
        inactiveTrackColor: KalinkaColors.surfaceElevated,
        thumbColor: Colors.white,
        overlayColor: KalinkaColors.accent.withValues(alpha: 0.15),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        value: liveValue,
        min: widget.min,
        max: widget.max,
        onChangeStart: (value) => _lastHapticPosition = _snap(value),
        onChanged: (value) {
          final snapped = _snap(value);
          final tickSize = (widget.max - widget.min) * 0.10;
          if ((snapped - _lastHapticPosition).abs() >= tickSize) {
            KalinkaHaptics.selectionClick();
            _lastHapticPosition = snapped;
          }
          if (snapped == _dragValue) return;
          setState(() => _dragValue = snapped);
        },
        onChangeEnd: (value) {
          // Hold until the parent commits (cleared in didUpdateWidget).
          _dragValue = _snap(value);
          widget.onChanged(_dragValue!);
        },
      ),
    );

    return Padding(
      padding: dense
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasLabel) ...[
            Text(
              widget.label,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                fontSize: KalinkaTypography.baseSize + 2,
              ),
            ),
            SizedBox(height: dense ? 2 : 6),
          ],
          // Value readout floating above the thumb. minHeight + invisible
          // sizer so it grows with text scaling instead of clipping.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth - 2 * _trackInset;
                final thumbX = _trackInset + fraction * trackWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Sizes the row to the text height.
                    Opacity(opacity: 0, child: valueText),
                    Positioned(
                      left: thumbX,
                      bottom: 0,
                      // Center the label horizontally on the thumb.
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: valueText,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Compact row in dense mode; OverflowBox keeps a 48dp touch target.
          SizedBox(
            height: dense ? 28 : null,
            child: dense
                ? OverflowBox(
                    minHeight: 48,
                    maxHeight: 48,
                    child: sliderControl,
                  )
                : sliderControl,
          ),
          // Range labels.
          if (widget.minLabel != null || widget.maxLabel != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.minLabel ?? widget.min.toString(),
                    style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                      letterSpacing: 0,
                    ),
                  ),
                  Text(
                    widget.maxLabel ?? widget.max.toString(),
                    style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
