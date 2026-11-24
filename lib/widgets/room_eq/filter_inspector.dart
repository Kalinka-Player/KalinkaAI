import 'package:flutter/material.dart';

import '../../data_model/room_eq.dart';
import '../../theme/app_theme.dart';
import 'band_editor_header.dart';
import 'editor_dialogs.dart';
import 'filter_shape_icon.dart';

String formatEqNumber(double n) => n == n.roundToDouble()
    ? n.toInt().toString()
    : double.parse(n.toStringAsPrecision(6)).toString();

class FilterInspector extends StatelessWidget {
  final bool editable;
  final List<EqBand> bands;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<FilterShape> onAdd;
  final VoidCallback onRemove;
  final ValueChanged<EqBand> onChange;
  const FilterInspector({
    super.key,
    required this.bands,
    required this.selected,
    required this.onSelect,
    required this.editable,
    required this.onAdd,
    required this.onRemove,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final band = bands.elementAtOrNull(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Filter bands', style: KalinkaTextStyles.cardTitle),
            ),
            PopupMenuButton<FilterShape>(
              enabled: editable && bands.length < 20,
              tooltip: 'Add band',
              position: PopupMenuPosition.under,
              color: KalinkaColors.surfaceDialog,
              icon: const Icon(Icons.add_rounded),
              onSelected: onAdd,
              itemBuilder: (_) => [
                for (final shape in FilterShape.values)
                  PopupMenuItem(
                    value: shape,
                    child: Row(
                      children: [
                        FilterShapeIcon(shape),
                        const SizedBox(width: 12),
                        Flexible(child: Text(shape.label)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (band == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Flat response. Add a band to shape this preset.',
              style: TextStyle(color: KalinkaColors.textSecondary),
            ),
          )
        else ...[
          _BandPicker(bands: bands, selected: selected, onSelect: onSelect),
          const SizedBox(height: 8),
          BandEditorHeader(
            number: selected + 1,
            shape: band.shape,
            onShapeChanged: editable
                ? (type) => onChange(band.change(shape: type))
                : null,
            onRemove: editable ? onRemove : null,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final inline =
                  box.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(16) > 22;
              final fields = [
                EqValueControl(
                  inline: inline,
                  label: 'Frequency',
                  unit: 'Hz',
                  value: band.hz,
                  min: 0,
                  positiveOnly: true,
                  max: 384000,
                  onChanged: editable
                      ? (v) => onChange(band.change(hz: v))
                      : null,
                ),
                if (band.shape.hasGain)
                  EqValueControl(
                    inline: inline,
                    label: 'Gain',
                    unit: 'dB',
                    value: band.gain,
                    min: -30,
                    max: 30,
                    onChanged: editable
                        ? (v) => onChange(band.change(gain: v))
                        : null,
                  ),
                if (band.shape.hasQ)
                  EqValueControl(
                    inline: inline,
                    label: 'Q',
                    unit: '',
                    value: band.q,
                    min: 0.01,
                    max: 1000,
                    onChanged: editable
                        ? (v) => onChange(band.change(q: v))
                        : null,
                  ),
              ];
              if (inline) {
                return Column(
                  children: [
                    for (final f in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: f,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (final (i, f) in fields.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: f),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class EqValueControl extends StatelessWidget {
  const EqValueControl({
    super.key,
    this.inline = false,
    this.positiveOnly = false,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final bool inline, positiveOnly;
  final String label, unit;
  final double value, min, max;
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

  @override
  Widget build(BuildContext context) => Material(
    color: KalinkaColors.surfaceInput,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: KalinkaColors.borderDefault),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onChanged == null ? null : () => edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              Expanded(
                child: Flex(
                  direction: inline ? Axis.horizontal : Axis.vertical,
                  mainAxisAlignment: inline
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.start,
                  crossAxisAlignment: inline
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KalinkaColors.textSecondary,
                      ),
                    ),
                    if (!inline) const SizedBox(height: 3),
                    Text(
                      '${formatEqNumber(value)}${unit.isEmpty ? "" : " $unit"}',
                      style: KalinkaFonts.mono(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.edit_outlined,
                size: 15,
                color: KalinkaColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BandPicker extends StatefulWidget {
  const _BandPicker({
    required this.bands,
    required this.selected,
    required this.onSelect,
  });
  final List<EqBand> bands;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  State<_BandPicker> createState() => _BandPickerState();
}

class _BandPickerState extends State<_BandPicker> {
  final scroll = ScrollController();
  final active = GlobalKey();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_BandPicker old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = active.currentContext?.findRenderObject();
      if (target == null) return;
      scroll.position.ensureVisible(target, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: scroll,
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, b) in widget.bands.indexed)
          Padding(
            key: i == widget.selected ? active : null,
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              tooltip:
                  'Band ${i + 1}, ${b.shape.label}, ${formatEqNumber(b.hz)} Hz',
              avatar: FilterShapeIcon(b.shape),
              label: Text('${i + 1}'),
              selected: i == widget.selected,
              showCheckmark: false,
              onSelected: (_) => widget.onSelect(i),
            ),
          ),
      ],
    ),
  );
}
