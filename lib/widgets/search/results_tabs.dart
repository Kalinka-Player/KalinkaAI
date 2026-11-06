import 'package:flutter/material.dart';

import '../section_tab_button.dart';

/// The same accessible, horizontally scrollable tabs for result types and
/// recommendation sources. Changing a tab never opens another route.
class ResultsTabs extends StatefulWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<Widget>? leading;

  const ResultsTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.leading,
  }) : assert(leading == null || leading.length == labels.length);

  @override
  State<ResultsTabs> createState() => _ResultsTabsState();
}

class _ResultsTabsState extends State<ResultsTabs> {
  final _keys = <int, GlobalKey>{};
  (String, int, double, double)? _layout;

  @override
  Widget build(BuildContext context) => Padding(
    // The label/badge begins at the content gutter; its padded highlight
    // extends into the gutter without being clipped by the scroll viewport.
    padding: const EdgeInsets.only(
      left: 16 - SectionTabButton.horizontalPadding,
      right: 16,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final layout = (
          widget.labels.join('|'),
          widget.selected,
          constraints.maxWidth,
          MediaQuery.textScalerOf(context).scale(14),
        );
        if (_layout != layout) {
          _layout = layout;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final target = _keys[widget.selected]?.currentContext;
            if (target == null) return;
            Scrollable.of(target, axis: Axis.horizontal).position.ensureVisible(
              target.findRenderObject()!,
              alignment: 0.5,
            );
          });
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: SectionTabButton.spacing,
            children: [
              for (var i = 0; i < widget.labels.length; i++)
                SectionTabButton(
                  key: _keys.putIfAbsent(i, GlobalKey.new),
                  label: widget.labels[i],
                  leading: widget.leading?[i],
                  contentAlignment: AlignmentDirectional.centerStart,
                  selected: widget.selected == i,
                  onTap: () => widget.onSelected(i),
                ),
            ],
          ),
        );
      },
    ),
  );
}
