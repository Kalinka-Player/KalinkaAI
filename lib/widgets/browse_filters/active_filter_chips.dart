import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart' show FilterValue;
import '../../providers/filter_values_provider.dart';
import '../../theme/app_theme.dart';
import '../keyboard/ink_focus_outline.dart';
import '../tap_highlight.dart';
import 'browse_filter_form.dart';

/// One removable chip per active answer, shown above the rows.
///
/// This is what makes folding the controls away safe: the list is never
/// quietly filtered. Renders nothing when no filter is set.
class ActiveFilterChips extends ConsumerWidget {
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onChanged;

  final EdgeInsets padding;

  /// An inline search field already displays and clears this value.
  final bool showText;

  /// Query and navigation chips shown before the filter chips.
  final List<Widget> leading;

  const ActiveFilterChips({
    super.key,
    required this.capabilities,
    required this.query,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.leading = const [],
    this.showText = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facets = query.copyWith(text: '');
    if ((showText ? query : facets).isEmpty && leading.isEmpty) {
      return const SizedBox.shrink();
    }

    // In the order the surface offers its fields, then any it does not.
    final fields = [
      for (final facet in capabilities.choices) facet.id,
      for (final field in query.selections.keys)
        if (capabilities.choice(field) == null) field,
    ];
    final values = {
      for (final facet in capabilities.choices)
        if (query.selected(facet.id).isNotEmpty)
          facet.id: watchChoiceValues(ref, facet),
    };

    final chips = <Widget>[
      if (query.kind != null)
        ActiveFilterChip(
          label: resultKindLabel(query.kind!),
          onRemove: () => onChanged(query.copyWith(clearKind: true)),
        ),
      if (query.type != null)
        ActiveFilterChip(
          label: filterTypeLabel(query.type!),
          onRemove: () => onChanged(query.copyWith(clearType: true)),
        ),
      if (showText && query.text.isNotEmpty)
        ActiveFilterChip(
          label: '“${query.text}”',
          onRemove: () => onChanged(query.copyWith(text: '')),
        ),
      for (final source in query.sources)
        ActiveFilterChip(
          label: capabilities.sources.titleOf(source),
          onRemove: () => onChanged(
            query.copyWith(
              sources: [...query.sources.where((other) => other != source)],
            ),
          ),
        ),
      for (final field in fields)
        for (final id in query.selected(field))
          ActiveFilterChip(
            label: _nameOf(values[field], id),
            onRemove: () => onChanged(
              query.withSelected(field, [
                ...query.selected(field).where((other) => other != id),
              ]),
            ),
          ),
      if (query.order != NameMatchOrder.relevance)
        ActiveFilterChip(
          label: 'A–Z',
          onRemove: () =>
              onChanged(query.copyWith(order: NameMatchOrder.relevance)),
        ),
    ];

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...leading,
          ...chips,
          if (!facets.isEmpty)
            Tooltip(
              message: 'Clear filters, keep search text',
              child: TextButton(
                onPressed: () => onChanged(BrowseFilterQuery(text: query.text)),
                style: kalinkaPillButtonStyle.merge(
                  TextButton.styleFrom(
                    foregroundColor: KalinkaColors.textSecondary,
                    textStyle: KalinkaFonts.sans(
                      fontSize: KalinkaTypography.baseSize + 2,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(
                      kKalinkaPillTarget,
                      kKalinkaPillHeight,
                    ),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                  ),
                ),
                child: const Text('Clear filters'),
              ),
            ),
        ],
      ),
    );
  }

  /// Falls back to the raw id if the values have not landed — a chip with an
  /// ugly label still beats a filter with no chip.
  static String _nameOf(List<FilterValue>? values, String id) {
    for (final value in values ?? const <FilterValue>[]) {
      if (value.id == id) return value.name;
    }
    return id;
  }
}

/// One applied filter, drawn as a receipt: the filter card's own pill, grey,
/// because it is the trace of a choice made in the card rather than the place
/// the choice is made, and it stays on screen for as long as the listing does
/// (PALETTE.md, *A receipt is grey*).
class ActiveFilterChip extends StatefulWidget {
  final String label;
  final VoidCallback onRemove;

  /// A glyph ahead of the label, for the chip that is not an ordinary facet.
  final IconData? icon;

  const ActiveFilterChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.icon,
  });

  @override
  State<ActiveFilterChip> createState() => _ActiveFilterChipState();
}

class _ActiveFilterChipState extends State<ActiveFilterChip> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove filter ${widget.label}',
      excludeSemantics: true,
      onTap: widget.onRemove,
      child: Tooltip(
        message: widget.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onRemove,
            onHover: _setHovering,
            mouseCursor: WidgetStateMouseCursor.clickable,
            customBorder: FilterPillFace.shape,
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kKalinkaPillTarget),
              child: Center(
                widthFactor: 1,
                child: InkFocusOutline(
                  shape: FilterPillFace.shape,
                  child: FilterPillFace(
                    label: widget.label,
                    applied: true,
                    hovered: _hovering,
                    leading: widget.icon == null
                        ? null
                        : Icon(
                            widget.icon,
                            size: 16,
                            color: KalinkaColors.textSecondary,
                          ),
                    trailing: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _hovering
                          ? KalinkaColors.textPrimary
                          : KalinkaColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
