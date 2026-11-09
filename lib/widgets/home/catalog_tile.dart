import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_theme.dart';
import '../../data_model/module_icons.dart';
import '../module_artwork.dart';
import '../../utils/click_cursor.dart';
import '../loading_shimmer.dart';

/// Shared tile treatment for source roots and compact pinned catalogs.
class CatalogTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final ModuleIcons? icons;
  final Color? tint;
  final VoidCallback? onTap;
  final bool shortcut;

  const CatalogTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.icons,
    this.tint,
    required this.onTap,
    this.shortcut = false,
  });

  @override
  Widget build(BuildContext context) {
    final scale = _TileScale.of(context);
    return _CatalogTileSurface(
      tint: tint,
      onTap: onTap,
      centerContent: !shortcut,
      child: shortcut
          ? Semantics(
              button: true,
              enabled: onTap != null,
              child: _ShortcutTileContents(
                title: Text(title, style: KalinkaTextStyles.trackRowTitle),
                footer: Row(
                  children: [
                    ModuleArtwork(
                      icons: icons,
                      small: true,
                      size: MediaQuery.textScalerOf(context).scale(18),
                      fallback: Icon(
                        icon,
                        color: KalinkaColors.textSecondary,
                        size: MediaQuery.textScalerOf(context).scale(18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtitle ?? '',
                        style: KalinkaTextStyles.trackRowSubtitle,
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: KalinkaColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListTile(
              enabled: onTap != null,
              leading: ModuleArtwork(
                icons: icons,
                size: 24 * scale,
                fallback: Icon(icon, color: tint, size: 24 * scale),
              ),
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

/// Shrinks to the wrapped content during grid measurement, then uses the
/// common tile height to align the title at the top and attribution below.
class _ShortcutTileContents extends StatelessWidget {
  final Widget title;
  final Widget footer;

  const _ShortcutTileContents({required this.title, required this.footer});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        title,
        Padding(padding: const EdgeInsets.only(top: 12), child: footer),
      ],
    ),
  );
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
  final bool shortcut;

  const CatalogTileShimmer({
    super.key,
    this.hasSubtitle = false,
    this.shortcut = false,
  });

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
        centerContent: !shortcut,
        child: shortcut
            ? _ShortcutTileContents(
                title: line(0.8, KalinkaTextStyles.trackRowTitle),
                footer: Row(
                  children: [
                    ShimmerBlock(
                      width: MediaQuery.textScalerOf(context).scale(18),
                      height: MediaQuery.textScalerOf(context).scale(18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: line(0.7, KalinkaTextStyles.trackRowSubtitle),
                    ),
                    const ShimmerBlock(width: 8, height: 16, radius: 4),
                  ],
                ),
              )
            : ListTile(
                leading: ShimmerBlock(width: 24 * scale, height: 24 * scale),
                title: line(
                  0.7,
                  _scaled(KalinkaTextStyles.trackRowTitle, scale),
                ),
                subtitle: hasSubtitle
                    ? line(
                        0.5,
                        _scaled(KalinkaTextStyles.trackRowSubtitle, scale),
                      )
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
  final bool centerContent;

  const _CatalogTileSurface({
    required this.child,
    this.tint,
    this.onTap,
    this.centerContent = true,
  });

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
          child: centerContent ? Center(child: child) : child,
        ),
      ),
    );
  }
}

/// Equal-width tiles in reading order, matching heights within each row.
/// Shortcut tiles share the available width up to a scaled 480dp cap. Count
/// actual children when choosing columns, so short rows can use that space.
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
      final columns = _balanced(fit);
      final grid = _EqualHeightTileGrid(
        columns: columns,
        maxTileWidth: fill ? double.infinity : 480 * scale,
        uniformRows: fill,
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
  final bool uniformRows;
  final TextDirection textDirection;

  const _EqualHeightTileGrid({
    required this.columns,
    required this.maxTileWidth,
    required this.uniformRows,
    required this.textDirection,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightTileGrid(
        columns,
        maxTileWidth,
        uniformRows,
        textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightTileGrid renderObject,
  ) {
    renderObject.updateLayout(
      columns,
      maxTileWidth,
      uniformRows,
      textDirection,
    );
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
  bool _uniformRows;
  TextDirection _textDirection;

  _RenderEqualHeightTileGrid(
    this._columns,
    this._maxTileWidth,
    this._uniformRows,
    this._textDirection,
  );

  void updateLayout(
    int columns,
    double maxTileWidth,
    bool uniformRows,
    TextDirection textDirection,
  ) {
    if (_columns == columns &&
        _maxTileWidth == maxTileWidth &&
        _uniformRows == uniformRows &&
        _textDirection == textDirection) {
      return;
    }
    _columns = columns;
    _maxTileWidth = maxTileWidth;
    _uniformRows = uniformRows;
    _textDirection = textDirection;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TileParentData) {
      child.parentData = _TileParentData();
    }
  }

  ({double width, List<double> heights}) _measure(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    final width = math.min(
      (constraints.maxWidth - _gap * (_columns - 1)) / _columns,
      _maxTileWidth,
    );
    final tileConstraints = BoxConstraints.tightFor(width: width);
    final heights = List.filled((childCount / _columns).ceil(), 0.0);
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final Size childSize;
      if (dry) {
        childSize = child.getDryLayout(tileConstraints);
      } else {
        child.layout(tileConstraints, parentUsesSize: true);
        childSize = child.size;
      }
      final row = index++ ~/ _columns;
      heights[row] = math.max(heights[row], childSize.height);
    }
    // Filling source grids retain their existing uniform tile treatment.
    if (_uniformRows && heights.isNotEmpty) {
      final tallest = heights.reduce(math.max);
      heights.fillRange(0, heights.length, tallest);
    }
    return (width: width, heights: heights);
  }

  Size _gridSize(BoxConstraints constraints, List<double> heights) {
    return constraints.constrain(
      Size(
        constraints.maxWidth,
        heights.fold(0.0, (sum, height) => sum + height) +
            math.max(0, heights.length - 1) * _gap,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _gridSize(constraints, _measure(constraints, dry: true).heights);

  @override
  void performLayout() {
    // Measure wrapped content first, then align cards within their own row.
    // A long title in another row must not make short shortcuts taller.
    final tileSize = _measure(constraints, dry: false);
    size = _gridSize(constraints, tileSize.heights);
    var index = 0;
    var y = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      // Keep height as a minimum, not a tight constraint: if metadata arrives
      // and wraps onto another line, the child must invalidate this grid's
      // measurement instead of overflowing inside its previous fixed height.
      child.layout(
        BoxConstraints(
          minWidth: tileSize.width,
          maxWidth: tileSize.width,
          minHeight: tileSize.heights[index ~/ _columns],
        ),
        parentUsesSize: true,
      );
      final column = index % _columns;
      if (index > 0 && column == 0) {
        y += tileSize.heights[index ~/ _columns - 1] + _gap;
      }
      final x = column * (tileSize.width + _gap);
      final parentData = child.parentData! as _TileParentData;
      parentData.offset = Offset(
        _textDirection == TextDirection.ltr
            ? x
            : size.width - tileSize.width - x,
        y,
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
