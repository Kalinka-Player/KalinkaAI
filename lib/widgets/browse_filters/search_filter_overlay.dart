import 'package:flutter/material.dart';

import '../../data_model/browse_filters.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../overlay_card.dart';
import 'browse_filter_form.dart';

/// The unfolded state of the search-and-filters control: a card resting under
/// the title bar, holding the search field and every facet group the surface
/// offers.
///
/// Edits are **staged** — nothing reaches the list until Show results, so a
/// visit costs one reload however many pills are touched. Cancel and the
/// system back both discard; Reset empties the staged selection without
/// leaving.
class SearchFilterOverlay extends StatefulWidget {
  final BrowseFilterCapabilities capabilities;

  /// The filter currently applied to the list — the starting point, and what
  /// Cancel returns to.
  final BrowseFilterQuery applied;

  final String searchHint;

  final void Function(BrowseFilterQuery filter, {required bool reset}) onApply;
  final VoidCallback onCancel;

  /// Vertical space the card may occupy before its body starts scrolling.
  final double maxHeight;

  /// The card's name, in mono caps.
  final String title;

  /// One quiet line under the search field, where what that field does needs
  /// saying — on results it starts a new search rather than narrowing one.
  final String? searchCaption;

  const SearchFilterOverlay({
    super.key,
    required this.capabilities,
    required this.applied,
    required this.onApply,
    required this.onCancel,
    required this.maxHeight,
    this.searchHint = 'Search',
    this.title = 'SEARCH & FILTERS',
    this.searchCaption,
  });

  @override
  State<SearchFilterOverlay> createState() => _SearchFilterOverlayState();
}

class _SearchFilterOverlayState extends State<SearchFilterOverlay> {
  // Keep the options and selection from the same snapshot while editing.
  late final BrowseFilterCapabilities _capabilities = widget.capabilities;
  late BrowseFilterQuery _staged = widget.applied;
  bool _reset = false;

  @override
  Widget build(BuildContext context) {
    return KalinkaOverlayCard(
      maxHeight: widget.maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OverlayCardHeader(
            title: widget.title,
            onClose: widget.onCancel,
            closeLabel: 'Close filters',
            action: _staged.isEmpty
                ? null
                : OverlayTextAction(
                    label: 'RESET',
                    onTap: () => setState(() {
                      _staged = const BrowseFilterQuery();
                      _reset = true;
                    }),
                  ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: BrowseFilterForm(
                capabilities: _capabilities,
                query: _staged,
                searchHint: widget.searchHint,
                searchCaption: widget.searchCaption,
                // Staged: nothing is sent until Show results, so there is
                // nothing to coalesce and the badge can track every key.
                textDebounce: Duration.zero,
                onChanged: (query) => setState(() => _staged = query),
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            KalinkaButton(
              label: 'Cancel',
              variant: KalinkaButtonVariant.neutral,
              size: KalinkaButtonSize.compact,
              onTap: widget.onCancel,
            ),
            const SizedBox(width: 10),
            KalinkaButton(
              // The app's primary CTA, filled — the same weight as committing
              // anything else. No count: the filtered total is not known
              // until the selection is applied.
              label: 'Show results',
              size: KalinkaButtonSize.compact,
              onTap: () => widget.onApply(_staged, reset: _reset),
            ),
          ],
        ),
      ),
    );
  }
}
