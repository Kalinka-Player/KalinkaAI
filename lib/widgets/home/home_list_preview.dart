import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data_model/data_model.dart';
import '../browse_rows_shimmer.dart';
import '../search_cards/browse_item_rows.dart';
import 'home_preview_layout.dart';

/// Bounded Home rows, read down each column before moving to the next.
class HomeListPreview extends StatelessWidget {
  final List<BrowseItem> items;
  final int rowsPerColumn;
  final bool labelled;
  final bool inFolder;

  const HomeListPreview({
    super.key,
    required this.items,
    required this.rowsPerColumn,
    this.labelled = true,
    this.inFolder = false,
  });

  @override
  Widget build(BuildContext context) => _HomeListColumns(
    count: items.length,
    rowsPerColumn: rowsPerColumn,
    builder: (start, end, columns) => BrowseItemRows(
      items: items.sublist(start, end),
      labelled: labelled,
      inFolder: inFolder,
      // Parallel lists keep metadata beneath each title. A mixed list must
      // not gain a table heading just because one slice contains only albums.
      table: columns == 1,
    ),
  );
}

class HomeListPreviewShimmer extends StatelessWidget {
  final int rowsPerColumn;
  const HomeListPreviewShimmer({super.key, required this.rowsPerColumn});

  @override
  Widget build(BuildContext context) => _HomeListColumns(
    count: 64,
    rowsPerColumn: rowsPerColumn,
    builder: (start, end, _) => BrowseRowsShimmer(count: end - start),
  );
}

class _HomeListColumns extends StatefulWidget {
  final int count;
  final int rowsPerColumn;
  final Widget Function(int start, int end, int columns) builder;
  const _HomeListColumns({
    required this.count,
    required this.rowsPerColumn,
    required this.builder,
  });

  @override
  State<_HomeListColumns> createState() => _HomeListColumnsState();
}

class _HomeListColumnsState extends State<_HomeListColumns> {
  final _focus = FocusNode(skipTraversal: true);
  HomeListLayout? _previous;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plan = homeListLayout(
            width: constraints.maxWidth,
            count: widget.count,
            rowsPerColumn: widget.rowsPerColumn,
            textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
          );
          final previous = _previous;
          if (previous != null &&
              (previous.columns != plan.columns ||
                  previous.count != plan.count) &&
              _focus.hasFocus) {
            // A focused row may leave its column. Clear focus history too, so
            // Flutter cannot activate an earlier track when that row unmounts.
            _focus.unfocus();
          }
          _previous = plan;
          if (plan.count == 0) return const SizedBox.shrink();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < plan.columns; c++) ...[
                if (c > 0) const SizedBox(width: homePreviewColumnGap),
                SizedBox(
                  width: plan.columnWidth,
                  child: FocusTraversalGroup(
                    child: Semantics(
                      container: true,
                      sortKey: OrdinalSortKey(c.toDouble()),
                      child: widget.builder(
                        plan.startOf(c),
                        plan.startOf(c + 1),
                        plan.columns,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
