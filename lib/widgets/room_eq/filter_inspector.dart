import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../data_model/room_eq.dart';
import '../../theme/app_theme.dart';
import '../scroll_edge_fade.dart';
import '../keyboard/app_keyboard_navigation.dart';
import '../keyboard/ink_focus_outline.dart';
import 'band_editor_header.dart';
import 'editor_dialogs.dart';
import 'eq_card.dart';
import 'filter_shape_icon.dart';

String formatEqNumber(double n) => n == n.roundToDouble()
    ? n.toInt().toString()
    : double.parse(n.toStringAsPrecision(6)).toString();

class FilterInspector extends StatelessWidget {
  const FilterInspector({
    super.key,
    required this.band,
    required this.number,
    required this.editable,
    required this.vertical,
    required this.onPreview,
    required this.onChange,
    required this.onRemove,
    this.preview,
  });
  final EqBand band;
  final EqBand? preview;
  final int number;
  final bool editable;
  final bool vertical;
  final ValueChanged<EqBand?> onPreview;
  final ValueChanged<EqBand> onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final sliders = [
      EqValueControl(
        outlined: !vertical,
        label: 'Frequency',
        unit: 'Hz',
        value: band.hz,
        preview: preview?.hz,
        step: 1,
        min: 0,
        positiveOnly: true,
        max: 384000,
        sliderRange: const RangeValues(20, 20000),
        logarithmic: true,
        onPreview: (v) => onPreview(v == null ? null : band.change(hz: v)),
        onChanged: editable ? (v) => onChange(band.change(hz: v)) : null,
      ),
      if (band.shape.hasGain)
        EqValueControl(
          outlined: !vertical,
          label: 'Gain',
          unit: 'dB',
          value: band.gain,
          preview: preview?.gain,
          step: .1,
          min: -30,
          max: 30,
          sliderRange: const RangeValues(-30, 30),
          onPreview: (v) => onPreview(v == null ? null : band.change(gain: v)),
          onChanged: editable ? (v) => onChange(band.change(gain: v)) : null,
        ),
      if (band.shape.hasQ)
        EqValueControl(
          outlined: !vertical,
          label: 'Q',
          unit: '',
          value: band.q,
          preview: preview?.q,
          step: .01,
          min: .01,
          max: 1000,
          sliderRange: const RangeValues(.1, 20),
          logarithmic: true,
          onPreview: (v) => onPreview(v == null ? null : band.change(q: v)),
          onChanged: editable ? (v) => onChange(band.change(q: v)) : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BandEditorHeader(
          number: number,
          shape: band.shape,
          onShapeChanged: editable
              ? (type) => onChange(band.change(shape: type))
              : null,
          onRemove: editable ? onRemove : null,
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) {
            final minWidth =
                98 *
                math.max(1, MediaQuery.textScalerOf(context).scale(16) / 16);
            if (vertical ||
                box.maxWidth <
                    minWidth * sliders.length + 8 * (sliders.length - 1)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: sliders,
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [for (final slider in sliders) Expanded(child: slider)],
            );
          },
        ),
      ],
    );
  }
}

class EqValueControl extends StatelessWidget {
  const EqValueControl({
    super.key,
    required this.step,
    this.positiveOnly = false,
    this.sliderRange,
    this.preview,
    this.onPreview,
    this.logarithmic = false,
    this.outlined = true,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final bool outlined;
  final bool positiveOnly, logarithmic;
  final RangeValues? sliderRange;
  final double? preview;
  final ValueChanged<double?>? onPreview;
  final String label, unit;
  final double value, min, max, step;
  final ValueChanged<double>? onChanged;

  Future<void> edit(BuildContext context) async {
    final text = await editEqValue(
      context,
      title: 'Adjust $label',
      label: unit.isEmpty ? label : '$label ($unit)',
      initial: value.toString(),
      numeric: true,
      validate: (s) {
        final n = double.tryParse(s);
        return n != null &&
                n.isFinite &&
                (positiveOnly ? n > min : n >= min) &&
                n <= max
            ? null
            : positiveOnly
            ? 'Enter a positive frequency up to ${formatEqNumber(max)} Hz.'
            : 'Enter ${formatEqNumber(min)} to ${formatEqNumber(max)}.';
      },
    );
    if (text != null && context.mounted) onChanged?.call(double.parse(text));
  }

  Widget nudge(bool increase) {
    final next = double.parse(
      (value + (increase ? step : -step))
          .clamp(min, max)
          .toStringAsPrecision(12),
    );
    final allowed = next != value && (!positiveOnly || next > min);
    return IconButton(
      tooltip: '${increase ? "Increase" : "Decrease"} $label',
      onPressed: allowed && onChanged != null ? () => onChanged!(next) : null,
      icon: Icon(increase ? Icons.add_rounded : Icons.remove_rounded, size: 17),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
      padding: EdgeInsets.zero,
    );
  }

  Widget _sliderCard(BuildContext context, RangeValues range) {
    // Preserve imported and precisely entered values outside the usual editing range.
    final low = math.min(range.start, value), high = math.max(range.end, value);
    double fraction(double v) => logarithmic
        ? (math.log(v) - math.log(low)) / (math.log(high) - math.log(low))
        : (v - low) / (high - low);
    double parameter(double fractionValue) {
      if (fractionValue == fraction(value)) return value;
      final raw = logarithmic
          ? math.exp(
              math.log(low) + fractionValue * (math.log(high) - math.log(low)),
            )
          : low + fractionValue * (high - low);
      final grid = (raw / step).round() * step;
      return double.parse(grid.clamp(low, high).toStringAsPrecision(12));
    }

    final shown = preview ?? value;
    final suffix = unit.isEmpty ? '' : ' $unit';
    String bound(double v) => unit == 'Hz' && v >= 1000
        ? '${formatEqNumber(v / 1000)}k'
        : formatEqNumber(v);
    return Material(
      color: KalinkaColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: outlined
            ? const BorderSide(color: KalinkaColors.borderDefault)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onChanged == null ? null : () => edit(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 6, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KalinkaTextStyles.trayRowSublabel),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${formatEqNumber(shown)}$suffix',
                          style: KalinkaTextStyles.textFieldInput,
                        ),
                        const Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: KalinkaColors.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _ParameterSlider(
              label: label,
              value: fraction(shown).clamp(0, 1),
              format: (f) => '${formatEqNumber(parameter(f))}$suffix',
              onPreview: onChanged == null
                  ? null
                  : (f) => onPreview!(parameter(f)),
              onCommit: (f) => onChanged?.call(parameter(f)),
              onCancel: () => onPreview?.call(null),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bound(low), style: KalinkaTextStyles.trayRowSublabel),
                  Text(bound(high), style: KalinkaTextStyles.trayRowSublabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => sliderRange != null
      ? _sliderCard(context, sliderRange!)
      : Material(
          color: KalinkaColors.surfaceInput,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: KalinkaColors.borderDefault),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onChanged == null ? null : () => edit(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: KalinkaTextStyles.trayRowSublabel),
                          Text(
                            '${formatEqNumber(value)}${unit.isEmpty ? "" : " $unit"}',
                            style: KalinkaFonts.mono(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: KalinkaColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              nudge(false),
              nudge(true),
            ],
          ),
        );
}

/// Material also ends a slider interaction when a pointer is cancelled or loses
/// to the scrolling gesture. Only a released pointer (or keyboard/semantics
/// action) should send an edit to the renderer.
class _ParameterSlider extends StatefulWidget {
  const _ParameterSlider({
    required this.label,
    required this.value,
    required this.format,
    required this.onPreview,
    required this.onCommit,
    required this.onCancel,
  });
  final String label;
  final double value;
  final String Function(double) format;
  final ValueChanged<double>? onPreview;
  final ValueChanged<double> onCommit;
  final VoidCallback onCancel;

  @override
  State<_ParameterSlider> createState() => _ParameterSliderState();
}

class _ParameterSliderState extends State<_ParameterSlider> {
  int? pointer;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => pointer ??= event.pointer,
    onPointerUp: (event) {
      if (pointer == event.pointer) pointer = null;
    },
    onPointerCancel: (event) {
      if (pointer != event.pointer) return;
      Future.microtask(() {
        if (pointer == event.pointer) pointer = null;
      });
    },
    child: Semantics(
      label: widget.label,
      child: AppKeyboardSlider(
        child: Slider(
          key: ValueKey('eq-slider-${widget.label}'),
          value: widget.value,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          activeColor: KalinkaColors.textPrimary,
          inactiveColor: KalinkaColors.borderDefault,
          semanticFormatterCallback: widget.format,
          onChanged: widget.onPreview,
          onChangeEnd: widget.onPreview == null
              ? null
              : (value) {
                  if (pointer == null) {
                    widget.onCommit(value);
                  } else {
                    widget.onCancel();
                  }
                },
        ),
      ),
    ),
  );
}

/// Selecting a graph point can reveal its card without scrolling the graph away.
class EqBandList extends StatefulWidget {
  const EqBandList({
    super.key,
    required this.bands,
    required this.selected,
    required this.compact,
    required this.onSelect,
    this.addButton,
  });
  final List<EqBand> bands;
  final int selected;
  final bool compact;
  final ValueChanged<int> onSelect;
  final Widget? addButton;
  @override
  State<EqBandList> createState() => _EqBandListState();
}

class _EqBandListState extends State<EqBandList> {
  final activeCard = GlobalKey();

  @override
  void didUpdateWidget(EqBandList old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected &&
        old.bands.length == widget.bands.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = activeCard.currentContext;
      if (ctx == null) return;
      final position = Scrollable.of(ctx, axis: Axis.horizontal).position;
      final card = ctx.findRenderObject()!;
      position.ensureVisible(
        card,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      position.ensureVisible(
        card,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  Widget card(int i, double width) {
    final band = widget.bands[i], selected = i == widget.selected;
    final hz = '${formatEqNumber(band.hz)} Hz';
    final gain = '${band.gain > 0 ? "+" : ""}${formatEqNumber(band.gain)} dB';
    final level = band.shape.hasGain ? gain : '${band.shape.slope} dB/oct';
    final details = [level, if (band.shape.hasQ) 'Q ${formatEqNumber(band.q)}'];
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? KalinkaColors.accent : KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '${i + 1}',
          style: KalinkaTextStyles.textFieldInput.copyWith(
            fontSize: 13,
            color: selected
                ? KalinkaColors.textPrimary
                : KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
    final frequency = band.hz >= 1000
        ? '${formatEqNumber(band.hz / 1000)} kHz'
        : hz;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected
            ? KalinkaColors.textPrimary
            : KalinkaColors.borderDefault,
      ),
    );
    return SizedBox(
      key: selected ? activeCard : null,
      width: widget.compact ? null : width,
      child: Semantics(
        button: true,
        selected: selected,
        label: [
          'Band ${i + 1}',
          band.shape.label,
          hz,
          if (band.shape.hasGain) gain,
          if (band.shape.hasQ) 'Q ${formatEqNumber(band.q)}',
        ].join(', '),
        excludeSemantics: true,
        onTap: () => widget.onSelect(i),
        child: Material(
          color: selected
              ? KalinkaColors.surfaceElevated
              : KalinkaColors.surfaceRaised,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('eq-band-${i + 1}'),
            onTap: () => widget.onSelect(i),
            child: InkFocusOutline(
              shape: shape,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: widget.compact
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            badge,
                            if (!band.shape.hasGain)
                              FilterShapeIcon(band.shape),
                            Text(
                              frequency,
                              style: KalinkaTextStyles.textFieldInput,
                            ),
                            Text(
                              level,
                              style: KalinkaTextStyles.trayRowSublabel,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                badge,
                                const Spacer(),
                                Tooltip(
                                  message: band.shape.label,
                                  excludeFromSemantics: true,
                                  child: FilterShapeIcon(band.shape),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(hz, style: KalinkaTextStyles.textFieldInput),
                            Text(
                              details.join('  ·  '),
                              style: KalinkaTextStyles.trayRowSublabel,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width =
        146.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(16) / 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EqCard.title('Parametric bands (${widget.bands.length})'),
        Row(
          children: [
            if (widget.bands.isEmpty)
              const Flexible(
                child: Text(
                  'Flat response',
                  style: TextStyle(color: KalinkaColors.textSecondary),
                ),
              )
            else
              Flexible(
                child: ScrollEdgeFade(
                  axis: Axis.horizontal,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                    child: SingleChildScrollView(
                      key: const PageStorageKey('eq-band-cards'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          for (var i = 0; i < widget.bands.length; i++)
                            card(i, width),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.addButton != null) ...[
              const SizedBox(width: 8),
              widget.addButton!,
            ],
          ],
        ),
      ],
    );
  }
}
