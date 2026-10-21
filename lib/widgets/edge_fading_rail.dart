import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import 'scroll_edge_fade.dart';

/// One line of [children] across the pane: centred while it fits, else
/// scrolled right out to the pane's edges past the [gutter] it sits within,
/// as Home's rails are. Each side fades as far as there is more to scroll
/// that way, so a line that seems to end on a whole child still shows it
/// goes on.
class EdgeFadingRail extends StatelessWidget {
  final List<Widget> children;

  /// The page's side inset, which the line runs out past to the edges.
  final double gutter;
  final double spacing;

  /// Keeps the line's scroll apart from the page's when it is built again.
  final String storageId;

  /// Centred while it fits; else it starts where the line does.
  final bool centred;

  /// Runs out past [gutter] at its start too; off where something stands
  /// before it on the line.
  final bool bleedStart;

  const EdgeFadingRail({
    super.key,
    required this.children,
    required this.gutter,
    required this.storageId,
    this.spacing = 8,
    this.centred = true,
    this.bleedStart = true,
  });

  static const fade = 32.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inner = constraints.maxWidth;
      final start = bleedStart ? gutter : 0.0;
      final end = gutter;
      final width = inner + start + end;
      return OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        // As far past the start as [start], however far past the end.
        alignment: AlignmentDirectional(
          start + end == 0 ? 0 : 2 * start / (start + end) - 1,
          0,
        ),
        minWidth: width,
        maxWidth: width,
        child: ScrollEdgeFade(
          axis: Axis.horizontal,
          extent: fade,
          child: ScrollConfiguration(
            // A mouse can drag it too; the wheel keeps scrolling the page.
            behavior: ScrollConfiguration.of(context)
                .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: SingleChildScrollView(
              key: PageStorageKey(storageId),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsetsDirectional.only(start: start, end: end),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: inner),
                child: Row(
                  mainAxisAlignment: centred
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  spacing: spacing,
                  children: [
                    for (final child in children)
                      // A long one shortens rather than outgrow the pane.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: inner),
                        child: child,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
