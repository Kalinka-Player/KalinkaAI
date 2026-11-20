import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/browse_filter_form.dart';
import '../home/catalog_pin_button.dart';
import '../keyboard/app_keyboard_navigation.dart';
import '../source_badge.dart';
import '../search_cards/action_pill_button.dart';
import '../tap_highlight.dart';

/// Where the bar's host draws a folder's actions as its header collapses.
enum FolderActionsPlace {
  /// In the header, beside the title or under it.
  header,

  /// Beside the title, taken into the bar once they reach it.
  bar,

  /// Held as they are in a row of their own under the bar once the title has
  /// scrolled away: from under the title, or from beside it where the bar's
  /// row has no room for them.
  underBar,
}

/// A catalog's identity, which scrolls away with the page and slides under
/// the bar, handing over to it with Pin once out of sight; a folder's own
/// actions with it. Search, Filters and Grid/List are the bar's own.
class CatalogSliverHeader extends ConsumerStatefulWidget {
  final CatalogPage page;
  final BrowseFilterQuery query;

  /// Told when the identity hands over to the bar, and when it is back.
  final ValueChanged<bool>? onCollapsed;

  /// Told where the host should draw the actions it supplies. Folder actions
  /// can follow a description below the title, reaching the toolbar later
  /// than the title and Pin.
  final ValueChanged<FolderActionsPlace>? onActionsPlace;

  /// The transparent toolbar's obstruction, kept inside this viewport so
  /// content can paint behind it while keyboard focus clears it.
  final double topInset;
  final Widget? actions;

  /// The host takes [actions] outside the content mask on collapse: into its
  /// bar from beside the title, or into a row under it from below.
  final bool barTakesActions;

  /// The host's bar has room in its own row for [actions] as they are beside
  /// the title. Without it, they are held in the row under the bar instead,
  /// as from under the title, rather than shrunk to fit.
  final bool barHasRoom;

  /// The host holds [actions] in a row under its bar, which [topInset]
  /// already counts, so the header no longer keeps their place.
  final bool actionsUnderBar;
  final double? actionsWidth;
  final bool titleInBar;
  final bool summaryInBar;
  final String? itemSummary;

  const CatalogSliverHeader({
    super.key,
    required this.page,
    required this.query,
    this.onCollapsed,
    this.onActionsPlace,
    this.topInset = 0,
    this.actions,
    this.barTakesActions = false,
    this.barHasRoom = true,
    this.actionsUnderBar = false,
    this.actionsWidth,
    this.titleInBar = false,
    this.summaryInBar = false,
    this.itemSummary,
  });

  static bool appliesTo(CatalogPage page) => page.isCatalog || page.isPlaylist;

  /// How much of the header stays under the bar: a folder's actions, else
  /// nothing.
  static double pinnedExtent(BuildContext context, {required bool actions}) =>
      actions ? FilterSearchField.heightFor(context) + 16 : 0;

  /// Whether the page has a search.
  static bool searches(BrowseFilterCapabilities caps) =>
      caps.text != FacetSupport.hidden;

  /// Whether the bar has room for the search field itself; otherwise it
  /// holds a button that unrolls the field under it.
  static bool searchInBar(double width, double scale) => width >= 720 * scale;

  /// The search field's widest in the bar, at normal text size.
  static const searchMaxWidth = 360.0;

  /// Whether the page has anything for Filters to narrow.
  static bool filters(BrowseFilterCapabilities caps) =>
      caps.genre != FacetSupport.hidden ||
      caps.type != FacetSupport.hidden ||
      caps.kind != FacetSupport.hidden ||
      caps.source != FacetSupport.hidden ||
      caps.order != FacetSupport.hidden;

  @override
  ConsumerState<CatalogSliverHeader> createState() =>
      _CatalogSliverHeaderState();
}

class _CatalogSliverHeaderState extends ConsumerState<CatalogSliverHeader> {
  bool? _collapsed;
  FolderActionsPlace? _actionsPlace;
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

  void _report(bool collapsed) {
    if (_collapsed == collapsed) return;
    _collapsed = collapsed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCollapsed?.call(collapsed);
    });
  }

  void _reportActions(FolderActionsPlace place) {
    if (_actionsPlace == place) return;
    _actionsPlace = place;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onActionsPlace?.call(place);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final pin =
        page.isCatalog &&
        !ref.watch(builtinSourcesProvider).contains(sourceOfId(page.id!));
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(16) / 16;
    final rowHeight = widget.barTakesActions
        ? ActionPillButton.heightOf(context)
        : FilterSearchField.heightFor(context);
    final subtitle = widget.summaryInBar
        ? ''
        : widget.titleInBar
        ? [
            if (page.provider?.trim().isNotEmpty == true) page.provider!.trim(),
            if (widget.itemSummary != null) widget.itemSummary!,
          ].join(' · ')
        : page.description?.trim().isNotEmpty == true
        ? page.description!.trim()
        : page.provider ?? '';
    final showSource = sourceBadgeVisible(ref, page.id!);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        if (widget.titleInBar) {
          // The host owns the title and Pin, and can also keep the summary
          // in its toolbar. Reserve that clearance inside the scroll.
          final summaryStyle = KalinkaTextStyles.trackRowSubtitle;
          final metrics = TextPainter(
            text: TextSpan(text: subtitle, style: summaryStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 2,
          )..layout(maxWidth: math.max(1, width - 32 - (showSource ? 24 : 0)));
          final summaryHeight = subtitle.isEmpty ? 0.0 : metrics.height;
          metrics.dispose();
          return SliverPersistentHeader(
            pinned: true,
            delegate: _CatalogHeaderDelegate(
              minHeight: widget.topInset,
              maxHeight: widget.topInset + summaryHeight + 12,
              builder: (context, offset) => ClipRect(
                child: Stack(
                  children: [
                    if (subtitle.isNotEmpty)
                      Positioned(
                        key: const ValueKey('catalog-compact-summary'),
                        left: 16,
                        right: 16,
                        top: widget.topInset + 4 - offset,
                        child: Row(
                          children: [
                            SourceBadge(
                              entityId: page.id!,
                              size: SourceBadgeSize.small,
                            ),
                            if (showSource) const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                subtitle,
                                style: summaryStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
        final titleFontSize = (width * 0.038).clamp(29.0, 41.0);
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
        final naturalMeasurement = (
          page.title ?? '',
          titleFontSize,
          scaler,
          Directionality.of(context),
        );
        if (_naturalMeasurement != naturalMeasurement) {
          _naturalMeasurement = naturalMeasurement;
          double lineWidth(String value, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(text: value, style: style),
              textScaler: scaler,
              textDirection: Directionality.of(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          _naturalTitleWidth = lineWidth(page.title ?? '', titleStyle);
        }
        final available = width - 32;
        final pinWidth = pin ? 56.0 : 0.0;
        // Play all, Enqueue and Up one folder, and on storage the library
        // and eject pills.
        final folderActions = widget.actions == null
            ? 0.0
            : widget.actionsWidth ?? (page.onStorage ? 560 : 400) * scale;
        // The title keeps its line where it can, and wraps to two before
        // a folder's actions give up the identity's row.
        const identityGap = 24.0;
        final wide =
            widget.actions != null &&
            available >=
                math.min(_naturalTitleWidth, 320 * scale) +
                    pinWidth +
                    identityGap +
                    folderActions;
        final controlsWidth = wide ? folderActions : available;
        final actionsHeight = widget.actions == null ? 0.0 : rowHeight + 8;
        // Only a folder's own actions stay under the bar, held there as its
        // trail is: a page's own always, a host's from under the title or
        // where its bar has no room for them. The rest, a host's beside the
        // title, go up into its bar.
        final held =
            widget.actions != null &&
            (!widget.barTakesActions || !wide || !widget.barHasRoom);
        final pinnedHeight = held ? rowHeight + 16 : 0.0;
        // Once the host holds that row under its bar, the inset counts it.
        // Measure from the bar's own bottom, so nothing here moves.
        final barTop =
            widget.topInset -
            (held && widget.barTakesActions && widget.actionsUnderBar
                ? pinnedHeight
                : 0);
        final headingWidth = wide
            ? available - controlsWidth - identityGap
            : available;
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
          width: headingWidth - pinWidth,
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
              math.max(1, headingWidth - pinWidth),
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
        // A control row centres its 40dp pill in 48.
        const pillInset = (kKalinkaPillTarget - kKalinkaPillHeight) / 2;
        final blockHeight = actionsHeight;
        final hasBlock = widget.actions != null;
        // Beside the identity the actions end level with it, their pills on
        // the attribution's last line; below it, they follow 8dp under.
        final expandedTop = wide
            ? math.max(0.0, headingHeight + pillInset - blockHeight)
            : headingHeight;
        final controlsBottom = expandedTop + blockHeight;
        // The content starts 12dp under whatever ends lowest, text or pill.
        final expandedHeight = math.max(
          pinnedHeight,
          math.max(
            wide || !hasBlock ? headingHeight + 12 : 0.0,
            hasBlock ? controlsBottom + 8 : 0.0,
          ),
        );
        final collapseExtent = expandedHeight - pinnedHeight;
        // Close under the bar. The identity slides under it with the page and
        // hands over once out of sight, Pin with it.
        final headingTop = barTop;
        return SliverPersistentHeader(
          pinned: true,
          delegate: _CatalogHeaderDelegate(
            minHeight: barTop + pinnedHeight,
            maxHeight: barTop + expandedHeight,
            builder: (context, offset) {
              final shrink = offset.clamp(0.0, collapseExtent);
              final settle = collapseExtent <= 0
                  ? (offset > 0 ? 1.0 : 0.0)
                  : (shrink / collapseExtent).clamp(0.0, 1.0);
              // Beside a folder's actions, the identity fades over the first
              // half of the collapse, and they cross its column in the second.
              final fade = wide && held
                  ? (1 - settle * 2).clamp(0.0, 1.0)
                  : 1.0;
              final spread = wide ? (settle * 2 - 1).clamp(0.0, 1.0) : settle;
              final compact =
                  fade == 0 ||
                  (shrink > 0 &&
                      shrink >= math.min(_titleHeight, collapseExtent));
              // The toolbar's Pin replaces the expanded Pin at the same
              // point the identity is removed, independently of the actions.
              _report(compact);
              if (widget.barTakesActions && widget.actions != null) {
                // Held actions hand over once settled 8dp under the bar,
                // where the host's row draws them, with the identity gone
                // and nothing yet beneath them. Others once at the bar.
                _reportActions(
                  held
                      ? settle >= 1
                            ? FolderActionsPlace.underBar
                            : FolderActionsPlace.header
                      : shrink > 0 &&
                            shrink >=
                                math.max(
                                  expandedTop + 8,
                                  math.min(_titleHeight, collapseExtent),
                                )
                      ? FolderActionsPlace.bar
                      : FolderActionsPlace.header,
                );
              }
              // Attribution follows the title up, fading as it nears the edge.
              final subtitleTop = headingTop + _titleHeight + 4 - shrink;
              final subtitleOpacity = math.min(
                ((subtitleTop - barTop) / 16).clamp(0.0, 1.0),
                fade,
              );
              final left = wide ? 16 + available - controlsWidth : 16.0;
              final top = expandedTop - shrink;
              // Up to 8dp under the bar, across the pane, and held there.
              final actionsTop =
                  barTop +
                  (held
                      ? math.min(
                          math.max(top + 8, 8.0),
                          expandedHeight - shrink - rowHeight - 8,
                        )
                      : top + 8);
              final actionsLeft = held ? left + (16 - left) * spread : left;
              return ColoredBox(
                key: const ValueKey('catalog-header-surface'),
                color: Colors.transparent,
                child: ClipRect(
                  child: Stack(
                    children: [
                      // Only a page's own held actions need a surface. Keep
                      // it below the transparent toolbar and status area; a
                      // host's are held outside its content mask instead.
                      if (widget.actions != null && !widget.barTakesActions)
                        Positioned.fill(
                          top: barTop,
                          child: ColoredBox(
                            color: KalinkaColors.background.withValues(
                              alpha: settle,
                            ),
                          ),
                        ),
                      if (!compact)
                        Positioned(
                          left: 16,
                          top: headingTop - shrink,
                          width: headingWidth,
                          child: Opacity(
                            opacity: fade,
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
                                      // Pin follows the longest line, not
                                      // the room the title was offered.
                                      textWidthBasis:
                                          TextWidthBasis.longestLine,
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
                      if (widget.actions != null)
                        Positioned(
                          top: actionsTop,
                          left: actionsLeft,
                          right: 16,
                          height: rowHeight,
                          child: widget.actions!,
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

/// The search and filter pills in the catalog toolbar.
ButtonStyle _pillStyle(double rowHeight, {required bool labelled}) {
  final pillHeight = rowHeight - (kKalinkaPillTarget - kKalinkaPillHeight);
  return kalinkaPillButtonStyle.merge(
    OutlinedButton.styleFrom(
      minimumSize: Size(pillHeight, pillHeight),
      fixedSize: Size.fromHeight(pillHeight),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.symmetric(horizontal: labelled ? 16 : 10),
      foregroundColor: KalinkaColors.textPrimary,
      backgroundColor: KalinkaColors.surfaceElevated,
      side: const BorderSide(color: KalinkaColors.borderDefault),
      textStyle: KalinkaFonts.sans(
        fontSize: KalinkaTypography.baseSize + 2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A pill centred in a target as tall as its row.
Widget _pillTarget({
  required String tooltip,
  required double rowHeight,
  required VoidCallback? onTap,
  required Widget pill,
}) => Tooltip(
  message: tooltip,
  child: GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    child: ConstrainedBox(
      constraints: BoxConstraints.tightFor(height: rowHeight)
          .copyWith(minWidth: kKalinkaPillTarget),
      child: Center(widthFactor: 1, child: pill),
    ),
  ),
);

/// Opens a catalog's filter card: labelled where there is room, else its
/// glyph with the count of filters on.
class CatalogFiltersButton extends StatelessWidget {
  final int count;
  final bool labelled;
  final double rowHeight;
  final VoidCallback? onTap;

  const CatalogFiltersButton({
    super.key,
    required this.count,
    required this.labelled,
    required this.rowHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _pillStyle(rowHeight, labelled: labelled);
    const glyph = Icon(Icons.tune_rounded, size: 20);
    return _pillTarget(
      tooltip: count == 0 ? 'Filters' : 'Filters, $count active',
      rowHeight: rowHeight,
      onTap: onTap,
      pill: labelled
          ? OutlinedButton.icon(
              onPressed: onTap,
              style: style,
              icon: glyph,
              label: Text(count == 0 ? 'Filters' : 'Filters · $count'),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: style,
              child: count == 0
                  ? glyph
                  : Badge(label: Text('$count'), child: glyph),
            ),
    );
  }
}

/// A catalog's search, folded into the bar: it unrolls the field below it.
/// A dot says a search is applied while the field is put away.
class CatalogSearchButton extends StatelessWidget {
  final bool active;

  /// Drawn as engaged while the field it unrolled is out.
  final bool open;
  final double rowHeight;
  final VoidCallback onTap;

  const CatalogSearchButton({
    super.key,
    required this.active,
    required this.open,
    required this.rowHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _pillStyle(rowHeight, labelled: false).copyWith(
      backgroundColor: WidgetStatePropertyAll(
        open ? KalinkaColors.surfaceOverlay : KalinkaColors.surfaceElevated,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: open ? KalinkaColors.textMuted : KalinkaColors.borderDefault,
        ),
      ),
    );
    const glyph = Icon(Icons.search_rounded, size: 20);
    return _pillTarget(
      tooltip: active ? 'Search, applied' : 'Search',
      rowHeight: rowHeight,
      onTap: onTap,
      pill: OutlinedButton(
        onPressed: onTap,
        style: style,
        child: active ? Badge(smallSize: 7, child: glyph) : glyph,
      ),
    );
  }
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
  ) => AppKeyboardRegion(
    area: AppKeyboardArea.toolbar,
    child: builder(context, shrinkOffset),
  );
  @override
  bool shouldRebuild(_CatalogHeaderDelegate oldDelegate) => true;
}
