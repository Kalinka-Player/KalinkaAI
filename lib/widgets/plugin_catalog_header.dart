import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'slide_in_panel.dart';

/// One scroll-driven header: the display title contracts into a small toolbar,
/// while secondary copy fades out. No separate animation or nested scroll view.
class PluginCatalogHeader extends StatelessWidget {
  final String serverName, connectionLabel;
  final Color connectionColor;
  final bool phone;
  final double gutter;

  const PluginCatalogHeader({
    super.key,
    required this.serverName,
    required this.connectionLabel,
    required this.connectionColor,
    required this.phone,
    required this.gutter,
  });

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderDelegate(
        serverName: serverName,
        connectionLabel: connectionLabel,
        connectionColor: connectionColor,
        phone: phone,
        gutter: gutter,
        metrics: _HeaderMetrics(
          context,
          width: constraints.crossAxisExtent,
          gutter: gutter,
          phone: phone,
          serverName: serverName,
        ),
      ),
    ),
  );
}

const _description = 'Music sources and controls for your hi-fi.';
const _preview = 'Read-only preview';
const _bodyStart = 56.0; // Settings-style 42px Back, 6px inset, 8px gap.

class _HeaderMetrics {
  late final double titleWidth, titleHeight, serverHeight;
  late final double expandedHeight, compactHeight, compactTitleTop;
  final double titleSize, compactTitleSize;

  _HeaderMetrics(
    BuildContext context, {
    required double width,
    required double gutter,
    required bool phone,
    required String serverName,
  }) : titleSize = phone ? 29 : 35,
       compactTitleSize = phone ? 20 : 22 {
    // Measure using the actual pane width and accessibility text scale, rather
    // than assuming a fixed height for wrapped preview/description text.
    final bodyWidth = math.max(1.0, width - _bodyStart - gutter);
    Size measure(
      String text,
      TextStyle style,
      double maxWidth, {
      bool singleLine = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: singleLine ? 1 : null,
        ellipsis: singleLine ? '…' : null,
      )..layout(maxWidth: math.max(1.0, maxWidth));
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final title = measure(
      'Plugins',
      titleStyle(titleSize),
      bodyWidth,
      singleLine: true,
    );
    titleWidth = title.width;
    titleHeight = title.height;
    serverHeight = math.max(
      24,
      measure(
        serverName,
        KalinkaTextStyles.trayRowLabel,
        bodyWidth - 24,
        singleLine: true,
      ).height,
    );
    final preview = measure(
      _preview,
      KalinkaTextStyles.trayRowSublabel,
      bodyWidth,
    );
    final titleRowHeight = titleWidth + 12 + preview.width <= bodyWidth
        ? math.max(titleHeight, preview.height)
        : titleHeight + 4 + preview.height;
    final bodyHeight =
        serverHeight +
        2 +
        titleRowHeight +
        (phone
            ? 0
            : 6 +
                  measure(
                    _description,
                    KalinkaTextStyles.trayRowSublabel,
                    bodyWidth,
                  ).height);
    final compactTitleHeight = measure(
      'Plugins',
      titleStyle(compactTitleSize),
      bodyWidth - 32,
      singleLine: true,
    ).height;
    final toolbarHeight = math.max(42.0, compactTitleHeight);
    compactHeight = 16 + toolbarHeight;
    compactTitleTop = 8 + (toolbarHeight - compactTitleHeight) / 2;
    expandedHeight = math.max(compactHeight, 20 + math.max(42, bodyHeight));
  }

  static TextStyle titleStyle(double size) => KalinkaFonts.display(
    fontSize: size,
    fontWeight: FontWeight.w400,
    color: KalinkaColors.frost,
    height: 1.2,
  );
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final String serverName, connectionLabel;
  final Color connectionColor;
  final bool phone;
  final double gutter;
  final _HeaderMetrics metrics;

  const _HeaderDelegate({
    required this.serverName,
    required this.connectionLabel,
    required this.connectionColor,
    required this.phone,
    required this.gutter,
    required this.metrics,
  });

  @override
  double get minExtent => metrics.compactHeight;
  @override
  double get maxExtent => metrics.expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final progress = range == 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final opacity = (1 - progress * 2).clamp(0.0, 1.0);
    return Material(
      key: const ValueKey('catalog-heading'),
      color: KalinkaColors.background,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PositionedDirectional(
              start: _bodyStart,
              end: gutter,
              top: 8 - shrinkOffset.clamp(0.0, range) / 2,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  excluding: opacity == 0,
                  child: Opacity(
                    key: const ValueKey('catalog-heading-details'),
                    opacity: opacity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                serverName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KalinkaTextStyles.trayRowLabel,
                              ),
                            ),
                            const SizedBox(width: 24, height: 24),
                          ],
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              SizedBox(
                                width: metrics.titleWidth,
                                height: metrics.titleHeight,
                              ),
                              Text(
                                _preview,
                                textAlign: TextAlign.end,
                                style: KalinkaTextStyles.trayRowSublabel,
                              ),
                            ],
                          ),
                        ),
                        if (!phone) ...[
                          const SizedBox(height: 6),
                          Text(
                            _description,
                            style: KalinkaTextStyles.trayRowSublabel,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              start: _bodyStart,
              end: gutter + 32 * progress,
              top: lerpDouble(
                8 + metrics.serverHeight + 2,
                metrics.compactTitleTop,
                progress,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'Plugins',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _HeaderMetrics.titleStyle(
                    lerpDouble(
                      metrics.titleSize,
                      metrics.compactTitleSize,
                      progress,
                    )!,
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              start: 6,
              top: 8,
              child: Semantics(
                label: 'Back',
                button: true,
                child: GestureDetector(
                  key: const ValueKey('catalog-back'),
                  onTap: () => SlideInPanel.closeOf(context),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      Icons.arrow_back,
                      size: 22,
                      color: KalinkaColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: gutter,
              top: lerpDouble(
                8 + (metrics.serverHeight - 24) / 2,
                (minExtent - 24) / 2,
                progress,
              ),
              child: Tooltip(
                message: connectionLabel,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: DecoratedBox(
                      key: const ValueKey('catalog-connection-status'),
                      decoration: BoxDecoration(
                        color: connectionColor,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) => true;
}
