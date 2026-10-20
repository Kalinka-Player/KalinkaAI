import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import '../loading_shimmer.dart';

/// Shared tile treatment for source roots and compact pinned catalogs.
class CatalogTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? tint;
  final VoidCallback? onTap;

  const CatalogTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = _TileScale.of(context);
    return _CatalogTileSurface(
      tint: tint,
      onTap: onTap,
      child: ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: tint, size: 24 * scale),
        title: Text(
          title,
          style: _scaled(KalinkaTextStyles.trackRowTitle, scale),
        ),
        subtitle: subtitle == null || subtitle!.isEmpty
            ? null
            : Text(
                subtitle!,
                style: _scaled(KalinkaTextStyles.trackRowSubtitle, scale),
              ),
        trailing: onTap == null
            ? null
            : Icon(Icons.chevron_right, size: 24 * scale),
      ),
    );
  }
}

TextStyle _scaled(TextStyle style, double scale) =>
    scale == 1 ? style : style.copyWith(fontSize: style.fontSize! * scale);

/// How much larger than a compact catalog's a tile in a filling
/// [CatalogTileGrid] draws. Width adds only a little emphasis; system text
/// scaling remains independent and labels can wrap to their full height.
class _TileScale extends InheritedWidget {
  final double scale;

  const _TileScale({required this.scale, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TileScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(_TileScale oldWidget) => scale != oldWidget.scale;
}

/// Uses the source tile's own frame and list layout while its metadata loads.
class CatalogTileShimmer extends StatelessWidget {
  final bool hasSubtitle;

  const CatalogTileShimmer({super.key, this.hasSubtitle = false});

  @override
  Widget build(BuildContext context) {
    final scale = _TileScale.of(context);
    // Measure inside ListTile's inherited text style, just as its labels do.
    // Font metrics (not just font size) determine the tile's large-text height.
    Widget line(double fraction, TextStyle style) => Builder(
      builder: (context) {
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          text: TextSpan(
            text: 'Ag',
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final height = painter.height;
        painter.dispose();
        return SizedBox(
          height: height,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: ShimmerBlock(
                height: scaler.scale(style.fontSize!),
                radius: 4,
              ),
            ),
          ),
        );
      },
    );
    return ShimmerPulse(
      child: _CatalogTileSurface(
        child: ListTile(
          leading: ShimmerBlock(width: 24 * scale, height: 24 * scale),
          title: line(0.7, _scaled(KalinkaTextStyles.trackRowTitle, scale)),
          subtitle: hasSubtitle
              ? line(0.5, _scaled(KalinkaTextStyles.trackRowSubtitle, scale))
              : null,
          trailing: SizedBox(
            width: 24 * scale,
            height: 24 * scale,
            child: Center(
              child: ShimmerBlock(
                width: 8 * scale,
                height: 16 * scale,
                radius: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogTileSurface extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final VoidCallback? onTap;

  const _CatalogTileSurface({required this.child, this.tint, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scale = _TileScale.of(context);
    return Material(
      color: tint == null
          ? KalinkaColors.surfaceRaised
          : Color.alphaBlend(
              tint!.withValues(alpha: 0.14),
              KalinkaColors.surfaceRaised,
            ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: tint?.withValues(alpha: 0.30) ?? KalinkaColors.borderDefault,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        // Keep icons close to the labels without crowding the text.
        child: ListTileTheme.merge(
          mouseCursor: WidgetStatePropertyAll(
            clickCursor(interactive: onTap != null),
          ),
          contentPadding: EdgeInsetsDirectional.only(
            start: 12 * scale,
            end: 8 * scale,
          ),
          horizontalTitleGap: 8 * scale,
          minLeadingWidth: 24 * scale,
          minVerticalPadding: scale == 1 ? null : 10 * scale,
          minTileHeight: scale == 1 ? null : 56 * scale,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Equal-size tiles in reading order, allowing more room at large text sizes.
/// A wide pane adds columns rather than stretching tiles, so a short row of
/// pinned catalogs keeps tile-sized tiles at its start.
///
/// With [fill], as for the music sources, the tiles share the whole width
/// instead — a lone one spans it — in as few rows as fit, as evenly filled
/// as their count allows, with modest growth capped at 10%.
class CatalogTileGrid extends StatelessWidget {
  final List<Widget> children;
  final bool fill;

  const CatalogTileGrid({super.key, required this.children, this.fill = false});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      const gap = _RenderEqualHeightTileGrid._gap;
      // Reserve room for a label, metadata and both icons before adding a
      // column. Phone layouts use one full-width tile per row.
      final fit = ((constraints.maxWidth + gap) / (240 * scale + gap))
          .floor()
          .clamp(1, 6);
      final columns = fill ? _balanced(fit) : fit;
      final grid = _EqualHeightTileGrid(
        columns: columns,
        maxTileWidth: fill || columns == 1 ? double.infinity : 260 * scale,
        textDirection: Directionality.of(context),
        children: children,
      );
      if (!fill) return grid;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return _TileScale(
        scale: (width / 180 / scale).clamp(1.0, 1.1),
        child: grid,
      );
    },
  );

  /// As many columns as fit, but no more than the tiles need, and the rows
  /// as evenly filled as the count allows: five across three makes three and
  /// two, not four and one.
  int _balanced(int fit) {
    if (children.isEmpty) return 1;
    final rows = (children.length / fit).ceil();
    return (children.length / rows).ceil();
  }
}

class _EqualHeightTileGrid extends MultiChildRenderObjectWidget {
  final int columns;
  final double maxTileWidth;
  final TextDirection textDirection;

  const _EqualHeightTileGrid({
    required this.columns,
    required this.maxTileWidth,
    required this.textDirection,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightTileGrid(columns, maxTileWidth, textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightTileGrid renderObject,
  ) {
    renderObject.updateLayout(columns, maxTileWidth, textDirection);
  }
}

class _TileParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightTileGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TileParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TileParentData> {
  static const _gap = 8.0;
  int _columns;
  double _maxTileWidth;
  TextDirection _textDirection;

  _RenderEqualHeightTileGrid(
    this._columns,
    this._maxTileWidth,
    this._textDirection,
  );

  void updateLayout(
    int columns,
    double maxTileWidth,
    TextDirection textDirection,
  ) {
    if (_columns == columns &&
        _maxTileWidth == maxTileWidth &&
        _textDirection == textDirection) {
      return;
    }
    _columns = columns;
    _maxTileWidth = maxTileWidth;
    _textDirection = textDirection;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TileParentData) {
      child.parentData = _TileParentData();
    }
  }

  Size _measure(BoxConstraints constraints, {required bool dry}) {
    final width = math.min(
      (constraints.maxWidth - _gap * (_columns - 1)) / _columns,
      _maxTileWidth,
    );
    final tileConstraints = BoxConstraints.tightFor(width: width);
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final Size childSize;
      if (dry) {
        childSize = child.getDryLayout(tileConstraints);
      } else {
        child.layout(tileConstraints, parentUsesSize: true);
        childSize = child.size;
      }
      height = math.max(height, childSize.height);
    }
    return Size(width, height);
  }

  Size _gridSize(BoxConstraints constraints, double tileHeight) {
    final rows = (childCount / _columns).ceil();
    return constraints.constrain(
      Size(
        constraints.maxWidth,
        rows == 0 ? 0 : rows * tileHeight + (rows - 1) * _gap,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _gridSize(constraints, _measure(constraints, dry: true).height);

  @override
  void performLayout() {
    // Measure wrapped content first, then give every tile the same full frame.
    // This also keeps the final, partially filled row the same size.
    final tileSize = _measure(constraints, dry: false);
    size = _gridSize(constraints, tileSize.height);
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints.tight(tileSize), parentUsesSize: true);
      final column = index % _columns;
      final x = column * (tileSize.width + _gap);
      final parentData = child.parentData! as _TileParentData;
      parentData.offset = Offset(
        _textDirection == TextDirection.ltr
            ? x
            : size.width - tileSize.width - x,
        (index ~/ _columns) * (tileSize.height + _gap),
      );
      index++;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
