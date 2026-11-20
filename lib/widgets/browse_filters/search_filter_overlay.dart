import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final bool showSearch;

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
    this.showSearch = true,
  });

  @override
  State<SearchFilterOverlay> createState() => _SearchFilterOverlayState();
}

class _SearchFilterOverlayState extends State<SearchFilterOverlay> {
  // Keep the options and selection from the same snapshot while editing.
  late final BrowseFilterCapabilities _capabilities = widget.capabilities;
  late BrowseFilterQuery _staged = widget.applied;
  bool _reset = false;
  final _traversal = _FilterTraversalPolicy();

  @override
  Widget build(BuildContext context) {
    final card = KalinkaOverlayCard(
      maxHeight: widget.maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(0),
            child: OverlayCardHeader(
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
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: BrowseFilterForm(
                  capabilities: _capabilities,
                  query: _staged,
                  searchHint: widget.searchHint,
                  searchCaption: widget.searchCaption,
                  showSearch: widget.showSearch,
                  // Staged: nothing is sent until Show results, so there is
                  // nothing to coalesce and the badge can track every key.
                  textDebounce: Duration.zero,
                  onChanged: (query) => setState(() => _staged = query),
                ),
              ),
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: _buildFooter(),
          ),
        ],
      ),
    );
    // Web maps bare arrows to scrolling. The filter dialog uses them to move
    // focus through chip rows and then into the footer on every platform.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
        ),
      },
      child: FocusTraversalGroup(policy: _traversal, child: card),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [
            KalinkaButton(
              label: 'Cancel',
              variant: KalinkaButtonVariant.neutral,
              size: KalinkaButtonSize.compact,
              onTap: widget.onCancel,
            ),
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

/// Up and Down visit each row before moving between the header, scrolling
/// options and footer. A footer button may line up better with Close than
/// any of the chips, and offscreen chips can lie behind either fixed row.
class _FilterTraversalPolicy extends OrderedTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final down = direction == TraversalDirection.down;
    if (!down && direction != TraversalDirection.up) {
      return super.inDirection(currentNode, direction);
    }
    final scope = currentNode.nearestScope;
    if (scope == null || currentNode is FocusScopeNode) {
      return super.inDirection(currentNode, direction);
    }
    final from = currentNode.rect;
    final order = FocusTraversalOrder.maybeOf(currentNode.context!);
    if (order is! NumericFocusOrder) {
      return super.inDirection(currentNode, direction);
    }
    FocusNode? best;
    var bestSection = double.infinity;
    var bestRow = double.infinity;
    var bestColumn = double.infinity;
    for (final node in scope.traversalDescendants) {
      if (node is FocusScopeNode ||
          FocusTraversalGroup.maybeOfNode(node) != this) {
        continue;
      }
      final section = FocusTraversalOrder.maybeOf(node.context!);
      if (section is! NumericFocusOrder) continue;
      final ahead = down
          ? section.order - order.order
          : order.order - section.order;
      if (ahead < 0 || ahead > bestSection) continue;
      final rect = node.rect;
      if (ahead == 0 &&
          (down ? rect.center.dy <= from.bottom : rect.center.dy >= from.top)) {
        continue;
      }
      final row = down ? rect.top : -rect.bottom;
      final column = (rect.center.dx - from.center.dx).abs();
      if (ahead == bestSection &&
          (row > bestRow || (row == bestRow && column >= bestColumn))) {
        continue;
      }
      best = node;
      bestSection = ahead;
      bestRow = row;
      bestColumn = column;
    }
    if (best == null) return false;
    requestFocusCallback(
      best,
      alignmentPolicy: down
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    return true;
  }
}
