import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_theme.dart';
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
  Widget build(BuildContext context) => _CatalogTileSurface(
    tint: tint,
    onTap: onTap,
    child: ListTile(
      enabled: onTap != null,
      leading: Icon(icon, color: tint),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: KalinkaTextStyles.trackRowTitle,
      ),
      subtitle: subtitle == null || subtitle!.isEmpty
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: KalinkaTextStyles.trackRowSubtitle,
            ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    ),
  );
}

/// Uses the source tile's own frame and list layout while its metadata loads.
class CatalogTileShimmer extends StatelessWidget {
  final bool hasSubtitle;

  const CatalogTileShimmer({super.key, this.hasSubtitle = false});

  @override
  Widget build(BuildContext context) {
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
          leading: const ShimmerBlock(width: 24, height: 24),
          title: line(0.7, KalinkaTextStyles.trackRowTitle),
          subtitle: hasSubtitle
              ? line(0.5, KalinkaTextStyles.trackRowSubtitle)
              : null,
          trailing: const SizedBox(
            width: 24,
            height: 24,
            child: Center(child: ShimmerBlock(width: 8, height: 16, radius: 4)),
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
  Widget build(BuildContext context) => Material(
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
      onTap: onTap,
      // Tighter than ListTile's defaults, so a half-width phone tile keeps
      // room for its title.
      child: ListTileTheme.merge(
        contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 8),
        horizontalTitleGap: 8,
        minLeadingWidth: 24,
        child: Center(child: child),
      ),
    ),
  );
}

/// Equal-size tiles in reading order, allowing more room at large text sizes.
class CatalogTileGrid extends StatelessWidget {
  final List<Widget> children;

  const CatalogTileGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      const gap = _RenderEqualHeightTileGrid._gap;
      // Two to a row on a 360dp phone, with room for "My Library".
      final columns = ((constraints.maxWidth + gap) / (160 * scale + gap))
          .floor()
          .clamp(1, 4);
      return _EqualHeightTileGrid(
        columns: columns,
        textDirection: Directionality.of(context),
        children: children,
      );
    },
  );
}

class _EqualHeightTileGrid extends MultiChildRenderObjectWidget {
  final int columns;
  final TextDirection textDirection;

  const _EqualHeightTileGrid({
    required this.columns,
    required this.textDirection,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightTileGrid(columns, textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightTileGrid renderObject,
  ) {
    renderObject.updateLayout(columns, textDirection);
  }
}

class _TileParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightTileGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TileParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TileParentData> {
  static const _gap = 8.0;
  int _columns;
  TextDirection _textDirection;

  _RenderEqualHeightTileGrid(this._columns, this._textDirection);

  void updateLayout(int columns, TextDirection textDirection) {
    if (_columns == columns && _textDirection == textDirection) return;
    _columns = columns;
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
    final width = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
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
