import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../column_separator.dart';
import '../source_badge.dart';

/// The columns a listing row adds as it widens: the album first, then the
/// artist, then the source. Every width here comes from the row's own width
/// and the columns end a fixed [gutter] from its right edge, so rows of one
/// listing — whatever they list — draw their separators on the same lines.
class RowColumns {
  /// The row's full width, edge to edge.
  final double width;

  const RowColumns(this.width);

  static const none = RowColumns(0);

  /// What a row keeps right of its columns for its own controls: a play
  /// button and a chevron.
  static const double gutter = 92;

  bool get album => width >= 600;
  bool get artist => width >= 800;
  bool get source => width >= 1000;
  bool get any => album;

  double get albumWidth => (width * 0.2).clamp(140.0, 280.0);
  double get artistWidth => (width * 0.16).clamp(120.0, 220.0);
  static const double sourceWidth = 132;

  /// The row's trailing slot, sized so its columns end at [gutter] from the
  /// edge; [inset] is what the row already holds between the slot and it.
  double trailingWidth(double inset) => gutter - inset;
}

/// Hands each row of a listing the columns its width earns. Placed outside
/// the row's own padding so its width is the row's.
class RowColumnsScope extends StatelessWidget {
  final Widget Function(BuildContext context, RowColumns columns) builder;

  const RowColumnsScope({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        builder(context, RowColumns(constraints.maxWidth)),
  );
}

/// The cells right of a row's title, each after a hairline. A row with
/// nothing for a column leaves it empty, keeping the lines unbroken.
class RowColumnCells extends ConsumerWidget {
  final RowColumns columns;
  final String? album;
  final String? artist;

  /// The entity whose source the source column names.
  final String? sourceOf;

  const RowColumnCells({
    super.key,
    required this.columns,
    this.album,
    this.artist,
    this.sourceOf,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!columns.any) return const SizedBox.shrink();
    Widget text(String? value) => Text(
      value ?? '',
      style: KalinkaTextStyles.trackRowSubtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (columns.artist) ...[
          const ColumnSeparator(),
          SizedBox(width: columns.artistWidth, child: text(artist)),
        ],
        const ColumnSeparator(),
        SizedBox(width: columns.albumWidth, child: text(album)),
        if (columns.source) ...[
          const ColumnSeparator(),
          SizedBox(
            width: RowColumns.sourceWidth,
            child: sourceOf == null ? null : _SourceCell(entityId: sourceOf!),
          ),
        ],
      ],
    );
  }
}

class _SourceCell extends ConsumerWidget {
  final String entityId;

  const _SourceCell({required this.entityId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = sourceOfId(entityId);
    final title = source == null
        ? null
        : ref.watch(sourceDisplayInfoProvider)[source]?.title;
    return Row(
      children: [
        if (sourceBadgeVisible(ref, entityId)) ...[
          SourceBadge(entityId: entityId),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            title ?? '',
            style: KalinkaTextStyles.trackRowSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A row's trailing controls, held to the slot [RowColumns] keeps for them
/// while the row shows columns; as they are otherwise.
class RowTrailing extends StatelessWidget {
  final RowColumns columns;

  /// Room the row keeps between this slot and its right edge.
  final double inset;
  final Widget child;

  const RowTrailing({
    super.key,
    required this.columns,
    required this.child,
    this.inset = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!columns.any) return child;
    return SizedBox(
      width: columns.trailingWidth(inset),
      child: Align(alignment: Alignment.centerRight, child: child),
    );
  }
}
