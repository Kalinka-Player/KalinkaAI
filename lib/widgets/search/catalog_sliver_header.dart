import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/browse_filter_form.dart';
import '../browse_filters/presentation_toggle.dart';
import '../home/catalog_pin_button.dart';
import '../source_badge.dart';

/// Catalog identity and Pin move to the shell while filters stay in this sliver.
/// The same field stays mounted throughout the transition.
class CatalogSliverHeader extends ConsumerStatefulWidget {
  final CatalogPage page;
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onChanged;
  final VoidCallback? onOpenFilters;
  final ValueChanged<bool>? onCollapsed;

  /// Told how far the header scrolls before it is fully collapsed, so the
  /// bar above can take on its surface at the same pace.
  final ValueChanged<double>? onCollapseExtent;
  final Widget? actions;
  final Widget? presentation;

  const CatalogSliverHeader({
    super.key,
    required this.page,
    required this.capabilities,
    required this.query,
    required this.onChanged,
    this.onOpenFilters,
    this.onCollapsed,
    this.onCollapseExtent,
    this.actions,
    this.presentation,
  });

  static bool appliesTo(CatalogPage page) => page.isCatalog || page.isPlaylist;

  @override
  ConsumerState<CatalogSliverHeader> createState() =>
      _CatalogSliverHeaderState();
}

class _CatalogSliverHeaderState extends ConsumerState<CatalogSliverHeader> {
  final _fieldKey = GlobalKey();
  bool? _collapsed;
  ({
    String title,
    String subtitle,
    double width,
    double fontSize,
    TextScaler scaler,
    TextDirection direction,
  })?
  _measurement;
  double _titleHeight = 0;
  double _headingHeight = 0;
  (String, double, TextScaler, TextDirection)? _naturalMeasurement;
  double _naturalTitleWidth = 0;

  @override
  void reassemble() {
    super.reassemble();
    _measurement = null;
    _naturalMeasurement = null;
  }

  double? _extent;

  void _reportExtent(double extent) {
    if (_extent == extent) return;
    _extent = extent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCollapseExtent?.call(extent);
    });
  }

  void _report(bool collapsed) {
    if (_collapsed == collapsed) return;
    _collapsed = collapsed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCollapsed?.call(collapsed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final caps = widget.capabilities;
    final text = caps.text != FacetSupport.hidden;
    final filters =
        caps.genre != FacetSupport.hidden ||
        caps.type != FacetSupport.hidden ||
        caps.kind != FacetSupport.hidden ||
        caps.source != FacetSupport.hidden ||
        caps.order != FacetSupport.hidden;
    final pin =
        page.isCatalog &&
        !ref.watch(builtinSourcesProvider).contains(sourceOfId(page.id!));
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(16) / 16;
    final rowHeight = FilterSearchField.heightFor(context);
    final subtitle = page.description?.trim().isNotEmpty == true
        ? page.description!.trim()
        : page.provider ?? '';
    final showSource = sourceBadgeVisible(ref, page.id!);
    final presentation = widget.presentation != null;
    final count = widget.query.copyWith(text: '').activeCount;
    final labelPainter = TextPainter(
      text: TextSpan(
        text: count == 0 ? 'Filters' : 'Filters · $count',
        style: KalinkaFonts.sans(
          fontSize: KalinkaTypography.baseSize + 2,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    // Padding, glyph and its gap around the label.
    final filterLabelWidth = labelPainter.width + 60;
    labelPainter.dispose();

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final titleFontSize = (width * 0.045).clamp(34.0, 48.0);
        final naturalMeasurement = (
          page.title ?? '',
          titleFontSize,
          scaler,
          Directionality.of(context),
        );
        if (_naturalMeasurement != naturalMeasurement) {
          _naturalMeasurement = naturalMeasurement;
          final painter = TextPainter(
            text: TextSpan(
              text: page.title ?? '',
              style: KalinkaFonts.display(
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout();
          _naturalTitleWidth = painter.width;
          painter.dispose();
        }
        final actionCount = (filters ? 1 : 0) + (presentation ? 1 : 0);
        final actionWidth =
            (filters ? 48 : 0) +
            (presentation ? PresentationToggle.width : 0) +
            math.max(0, actionCount - 1) * 8;
        // Pin belongs to the identity. Grid/List can share that row when
        // there is room; search and filters use the remaining control space.
        final wide = text || filters || widget.actions != null
            ? width >= 800 * scale
            : actionCount > 0 &&
                  width - 32 - actionWidth - 24 >=
                      math.min(_naturalTitleWidth, 320 * scale) +
                          (pin ? 56 : 0);
        final controlsWidth = wide
            ? (text || filters || widget.actions != null
                  ? (width - 32) * 0.60
                  : actionWidth.toDouble())
            : width - 32;
        bool stacks(double availableWidth) =>
            text &&
            (filters || presentation) &&
            availableWidth < 140 * scale + actionWidth + 8;
        final stacked = stacks(controlsWidth);
        // Wrapping is a width/text-size decision, never a scroll decision.
        // Keep the field and Filters in their rows while Grid/List leaves.
        final collapsedStacked = stacked && filters;
        double controlsHeight(bool stacked, {required bool withPresentation}) =>
            text || filters || withPresentation
            ? rowHeight * (stacked ? 2 : 1) + (stacked ? 8 : 0)
            : 0.0;
        final expandedControlsHeight = controlsHeight(
          stacked,
          withPresentation: presentation,
        );
        final actionsHeight = widget.actions == null ? 0.0 : rowHeight + 8;
        final collapsedControlsHeight = controlsHeight(
          collapsedStacked,
          withPresentation: false,
        );
        final hasPinnedContent = text || filters || widget.actions != null;
        final pinnedHeight = hasPinnedContent
            ? collapsedControlsHeight + actionsHeight + 17
            : 1.0;
        final expandedControlsArea =
            expandedControlsHeight + actionsHeight + 17;
        final headingWidth = wide ? width - controlsWidth - 56 : width - 32;
        final titleStyle = KalinkaFonts.display(
          fontSize: titleFontSize,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: KalinkaColors.textPrimary,
        );
        final subtitleStyle = KalinkaTextStyles.trackRowSubtitle.copyWith(
          fontSize: 16,
          height: 1.4,
          color: KalinkaColors.textSecondary,
        );
        double textHeight(String value, TextStyle style, double maxWidth) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 2,
          )..layout(maxWidth: maxWidth);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final measurement = (
          title: page.title ?? '',
          subtitle: subtitle,
          width: headingWidth - (pin ? 56 : 0),
          fontSize: titleStyle.fontSize!,
          scaler: scaler,
          direction: Directionality.of(context),
        );
        // Sliver constraints change on every scroll tick; text only needs
        // measuring when its content, width or system text size changes.
        if (_measurement != measurement) {
          _measurement = measurement;
          _titleHeight = math.max(
            pin ? 48 : 0,
            textHeight(
              page.title ?? '',
              titleStyle,
              math.max(1, headingWidth - (pin ? 56 : 0)),
            ),
          );
          _headingHeight =
              _titleHeight +
              (subtitle.isEmpty
                  ? 0
                  : 4 +
                        textHeight(
                          subtitle,
                          subtitleStyle,
                          math.max(1, headingWidth - 30),
                        ));
        }
        final headingHeight = _headingHeight;
        final expandedHeight = wide
            ? math.max(headingHeight + 16, expandedControlsArea + 16)
            : headingHeight + 16 + expandedControlsArea;
        final collapseExtent = expandedHeight - pinnedHeight;
        _reportExtent(collapseExtent);
        const headingTop = 8.0;
        // Transfer the identity before its first line meets the viewport edge,
        // not after the entire sliver has shrunk. Pin fades with that identity,
        // before its old space is reclaimed by the remaining controls.
        final handoffExtent = math.min(headingTop, collapseExtent);
        final labelledFilters =
            controlsWidth >=
            actionWidth -
                (filters ? 48 : 0) +
                filterLabelWidth +
                (text && !stacked ? 140 * scale + 8 : 0);
        return SliverPersistentHeader(
          pinned: true,
          delegate: _CatalogHeaderDelegate(
            minHeight: pinnedHeight,
            maxHeight: expandedHeight,
            builder: (context, offset) {
              final shrink = offset.clamp(0.0, collapseExtent);
              final handoff = (shrink / handoffExtent).clamp(0.0, 1.0);
              final compact = handoff >= 1;
              _report(compact);
              final settle =
                  ((shrink - handoffExtent) / (collapseExtent - handoffExtent))
                      .clamp(0.0, 1.0);
              final hasSideControls = wide && hasPinnedContent;
              // Attribution follows the title up naturally. On a wide pane,
              // let it fade before the filter row expands into its column.
              final subtitleTop = headingTop + _titleHeight + 4 - shrink;
              final subtitleOpacity = math.min(
                (subtitleTop / 16).clamp(0.0, 1.0),
                hasSideControls ? (1 - settle * 2).clamp(0.0, 1.0) : 1.0,
              );
              final spread = subtitle.isNotEmpty && hasSideControls
                  ? ((settle - 0.5) * 2).clamp(0.0, 1.0)
                  : settle;
              final left = wide
                  ? 16 + (width - 32 - controlsWidth) * (1 - spread)
                  : 16.0;
              final expandedTop = wide
                  ? (expandedHeight -
                            expandedControlsHeight -
                            actionsHeight -
                            1) /
                        2
                  : headingHeight + 16;
              final visibleHeight = expandedHeight - shrink;
              final controlsHeight =
                  expandedControlsHeight +
                  (collapsedControlsHeight - expandedControlsHeight) * settle;
              // Every visible control stays fully above the divider. The
              // former interpolation could push a 48dp Pin into a 17dp sliver.
              final top = math.max(
                hasPinnedContent ? 8.0 : 0.0,
                math.min(
                  expandedTop - shrink,
                  visibleHeight - controlsHeight - actionsHeight - 9,
                ),
              );
              return ColoredBox(
                key: const ValueKey('catalog-header-surface'),
                color: KalinkaColors.background.withValues(
                  alpha: shrink / collapseExtent,
                ),
                child: ClipRect(
                  child: Stack(
                    children: [
                      if (!compact)
                        Positioned(
                          left: 16,
                          top: headingTop - shrink,
                          width: headingWidth,
                          child: Opacity(
                            opacity: 1 - handoff,
                            child: Row(
                              key: const ValueKey('catalog-identity'),
                              children: [
                                Flexible(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      page.title ?? '',
                                      key: const ValueKey(
                                        'catalog-expanded-title',
                                      ),
                                      style: titleStyle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (pin) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: CatalogPinButton(
                                      page: page,
                                      filter: widget.query,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (subtitle.isNotEmpty && subtitleOpacity > 0)
                        Positioned(
                          left: 16,
                          top: subtitleTop,
                          width: headingWidth,
                          child: Opacity(
                            opacity: subtitleOpacity,
                            child: Row(
                              children: [
                                SourceBadge(entityId: page.id!),
                                if (showSource) const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    style: subtitleStyle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        key: const ValueKey('catalog-controls-position'),
                        top: top,
                        left: left,
                        right: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CatalogControls(
                              page: page,
                              capabilities: caps,
                              query: widget.query,
                              onChanged: widget.onChanged,
                              onOpenFilters: widget.onOpenFilters,
                              text: text,
                              filters: filters,
                              presentationOpacity: 1 - handoff,
                              presentationSpace: 1 - settle,
                              stacked: stacked,
                              labelledFilters: labelledFilters,
                              rowHeight: rowHeight,
                              fieldKey: _fieldKey,
                              presentation: widget.presentation,
                            ),
                            if (widget.actions != null) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: rowHeight,
                                child: widget.actions!,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Positioned(
                        bottom: 0,
                        left: 16,
                        right: 16,
                        child: SizedBox(
                          key: ValueKey('catalog-header-divider'),
                          height: 1,
                          child: ColoredBox(color: KalinkaColors.borderDefault),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CatalogControls extends StatelessWidget {
  /// The inline field's widest, at normal text size.
  static const fieldMaxWidth = 360.0;

  final CatalogPage page;
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onChanged;
  final VoidCallback? onOpenFilters;
  final bool text, filters, stacked;
  final bool labelledFilters;
  final double presentationOpacity, presentationSpace;
  final double rowHeight;
  final GlobalKey fieldKey;
  final Widget? presentation;

  const _CatalogControls({
    required this.page,
    required this.capabilities,
    required this.query,
    required this.onChanged,
    this.onOpenFilters,
    required this.text,
    required this.filters,
    required this.presentationOpacity,
    required this.presentationSpace,
    required this.stacked,
    required this.labelledFilters,
    required this.rowHeight,
    required this.fieldKey,
    this.presentation,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final labelled = labelledFilters;
      final count = query.copyWith(text: '').activeCount;
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      // The Play all pill's chrome, as tall as the field's.
      final pillHeight = rowHeight - (kKalinkaPillTarget - kKalinkaPillHeight);
      final buttonStyle = OutlinedButton.styleFrom(
        minimumSize: Size(pillHeight, pillHeight),
        fixedSize: Size.fromHeight(pillHeight),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(horizontal: labelled ? 16 : 10),
        foregroundColor: KalinkaColors.textPrimary,
        backgroundColor: KalinkaColors.surfaceElevated,
        side: const BorderSide(color: KalinkaColors.borderDefault),
        shape: const StadiumBorder(),
        textStyle: KalinkaFonts.sans(
          fontSize: KalinkaTypography.baseSize + 2,
          fontWeight: FontWeight.w600,
        ),
      );
      final field = FilterSearchField(
        key: fieldKey,
        enabled: capabilities.text == FacetSupport.supported,
        value: query.text,
        hint: 'Search ${page.title ?? 'catalog'}',
        neutral: true,
        onChanged: (value) => onChanged(query.copyWith(text: value)),
      );
      final actions = <Widget>[
        if (filters)
          Tooltip(
            message: count == 0 ? 'Filters' : 'Filters, $count active',
            child: GestureDetector(
              // The target is the row; the pill is centred in it.
              onTap: onOpenFilters,
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(height: rowHeight)
                    .copyWith(minWidth: kKalinkaPillTarget),
                child: Center(
                  widthFactor: 1,
                  child: labelled
                      ? OutlinedButton.icon(
                          onPressed: onOpenFilters,
                          style: buttonStyle,
                          icon: const Icon(Icons.tune_rounded, size: 20),
                          label: Text(
                            count == 0 ? 'Filters' : 'Filters · $count',
                          ),
                        )
                      : OutlinedButton(
                          onPressed: onOpenFilters,
                          style: buttonStyle,
                          child: count == 0
                              ? const Icon(Icons.tune_rounded, size: 20)
                              : Badge(
                                  label: Text('$count'),
                                  child: const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                  ),
                                ),
                        ),
                ),
              ),
            ),
          ),
      ];
      Widget row({required bool withField}) => Row(
        children: [
          // Held against Filters, at a width a search term needs.
          Expanded(
            child: withField
                ? Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _CatalogControls.fieldMaxWidth * scale,
                      ),
                      child: field,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          for (var i = 0; i < actions.length; i++) ...[
            if (withField || i > 0) const SizedBox(width: 8),
            actions[i],
          ],
          if (presentation != null && presentationSpace > 0)
            SizedBox(
              width:
                  (PresentationToggle.width + (withField || filters ? 8 : 0)) *
                  presentationSpace,
              height: rowHeight,
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: PresentationToggle.width,
                maxWidth: PresentationToggle.width,
                child: presentationOpacity > 0
                    ? Opacity(opacity: presentationOpacity, child: presentation)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      );
      if (!text &&
          !filters &&
          (presentation == null || presentationSpace == 0)) {
        return const SizedBox.shrink();
      }
      // Only the now-invisible Grid/List row shrinks. A wrapped Filters row keeps
      // its height, so it cannot be clipped or change rows during scrolling.
      final presentationOnlyRow = !filters && (stacked || !text);
      final actionRow = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stacked) const SizedBox(height: 8),
          row(withField: text && !stacked),
        ],
      );
      return Column(
        key: const ValueKey('catalog-control-line'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stacked) field,
          if (presentationOnlyRow)
            ClipRect(
              child: Align(heightFactor: presentationSpace, child: actionRow),
            )
          else
            actionRow,
        ],
      );
    },
  );
}

class _CatalogHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight, maxHeight;
  final Widget Function(BuildContext, double) builder;
  const _CatalogHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
  });
  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => builder(context, shrinkOffset);
  @override
  bool shouldRebuild(_CatalogHeaderDelegate oldDelegate) => true;
}
