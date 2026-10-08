import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/catalog_cards_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';

// Minimum card width before the grid adds a column. Kept small so it doubles to
// two-up early, rather than letting a single 3:1 banner grow huge first.
const double _kMinCardWidth = 300;
const double _kCardGap = 14;
const double _kCardRunGap = 16;
const int _kMaxColumns = 2;

// Wide, compact banners: the app paints the source-coloured gradient + frame and
// the album cascade (a transparent tile) sits on the right.
const double _kCardAspect = 3 / 1;

// Left fraction reserved for the icon/title/description column, clear of the
// cascade on the right.
const double _kTextZoneWidth = 0.48;

/// Advertisement cards for the browsable catalogs, grouped by source, on the
/// Catalogs root. Each card's background is a server-rendered image (or black
/// until the server produces it).
class CatalogCardsSection extends ConsumerWidget {
  /// Opens the tapped catalog page directly via its stable browse id — no AI
  /// routing. [provider] is the resolved source label for the page subtitle.
  final OpenCatalog onOpenCatalog;

  const CatalogCardsSection({super.key, required this.onOpenCatalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Plans cache between refreshes; after a reconnect drop them so the section
    // re-fetches instead of keeping pre-outage data or a stuck error.
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        ref.invalidate(catalogCardGroupsProvider);
      }
    });

    final groupsAsync = ref.watch(catalogCardGroupsProvider);

    return groupsAsync.when(
      // Counts unknown yet — one nominal shimmer group so the section doesn't
      // pop in. Once plans resolve, each source gets its exact card count.
      loading: () => const _CardGrid(cardCount: 3, children: null),
      error: (_, _) => const SizedBox.shrink(),
      data: (groups) {
        if (groups.isEmpty) return const SizedBox.shrink();
        return _sectionColumn([
          for (final group in groups) ...[
            _SourceGroupHeader(group: group),
            const SizedBox(height: 10),
            _CardGrid(
              cardCount: group.cards.length,
              children: [
                for (final plan in group.cards)
                  _CatalogCard(
                    plan: plan,
                    tint: _tintFor(group.sourceName),
                    onTap: () => onOpenCatalog(plan, _providerFor(group)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ]);
      },
    );
  }

  Widget _sectionColumn(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The provider label shown as the opened catalog page's subtitle.
  String _providerFor(CatalogCardGroup group) => group.sourceTitle;
}

Color _tintFor(String sourceName) => colorForSourceName(sourceName);

/// Maps a backend preview_config icon id to a glyph; null falls back to the
/// content-type icon.
IconData? _iconForId(String? id) {
  switch (id) {
    case 'best_match':
      return Icons.star_rounded;
    case 'ai_suggestions':
      return Icons.auto_awesome;
    case 'popular':
      return Icons.trending_up_rounded;
    case 'new_releases':
      return Icons.new_releases_outlined;
    case 'recent':
      return Icons.history_rounded;
    case 'library':
      return Icons.library_music_rounded;
    case 'album':
      return Icons.album_outlined;
    case 'artist':
      return Icons.person_outline;
    case 'track':
      return Icons.music_note_rounded;
    case 'playlist':
      return Icons.queue_music_rounded;
    default:
      return null;
  }
}

/// Source attribution header: letter badge + tinted title.
class _SourceGroupHeader extends StatelessWidget {
  final CatalogCardGroup group;

  const _SourceGroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final tint = _tintFor(group.sourceName);
    final title = group.sourceTitle;

    return Row(
      children: [
        if (title.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              border: Border.all(color: tint.withValues(alpha: 0.30), width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              title[0].toUpperCase(),
              style: KalinkaTextStyles.sourceBadgeLetter.copyWith(
                fontSize: 11,
                color: tint,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: KalinkaTextStyles.sectionLabel.copyWith(color: tint),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Responsive card grid: 1–4 equal columns, never more, sized from the
/// available width. With [children] null it renders [cardCount] shimmer
/// cards instead (the plans-loading state).
class _CardGrid extends StatelessWidget {
  final int cardCount;
  final List<Widget>? children;

  const _CardGrid({required this.cardCount, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = ((w + _kCardGap) / (_kMinCardWidth + _kCardGap))
            .floor()
            .clamp(1, _kMaxColumns);
        final itemWidth = (w - (columns - 1) * _kCardGap) / columns;

        return Wrap(
          spacing: _kCardGap,
          runSpacing: _kCardRunGap,
          children: [
            for (int i = 0; i < cardCount; i++)
              SizedBox(
                width: itemWidth,
                child: children != null
                    ? children![i]
                    : const _ShimmerCatalogCard(),
              ),
          ],
        );
      },
    );
  }
}

// Shared geometry between the real card and its shimmer twin, so the swap
// doesn't shift the grid.
const double _kCardRadius = 16;
const double _kCardBasePad = 14;
const double _kBadgeSize = 30;

// Text, icon and padding scale with card width (1.0 at the min card, capped)
// so they stay proportionate from a narrow tile up to a wide single-column one.
const double _kContentScaleRef = 340;
const double _kMaxContentScale = 1.9;

// Text outline width as a fraction of font size — a crisp dark edge so white
// text holds up over a light cover.
const double _kStrokeRatio = 0.12;

double _contentScale(double cardWidth) =>
    (cardWidth / _kContentScaleRef).clamp(1.0, _kMaxContentScale);

/// One category card: the server-rendered background (or black until it
/// exists) with the icon, title and description drawn on top.
class _CatalogCard extends StatefulWidget {
  final CatalogCardPlan plan;
  final Color tint;
  final VoidCallback? onTap;

  const _CatalogCard({required this.plan, required this.tint, this.onTap});

  @override
  State<_CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<_CatalogCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHover(bool value) {
    if (value != _hovered) setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (value != _pressed) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final tint = widget.tint;
    final description = plan.description?.trim() ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AspectRatio(
            aspectRatio: _kCardAspect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: KalinkaColors.surfaceRaised,
                borderRadius: BorderRadius.circular(_kCardRadius),
                // Neutral frame at rest; the source tint only lights up on
                // hover (matching the source-badge colour).
                border: Border.all(
                  color: _hovered
                      ? tint.withValues(alpha: 0.85)
                      : KalinkaColors.borderDefault,
                  width: 1,
                ),
              ),
              // Clip one step inside the frame, else the art runs under the
              // border and swallows the rounded corners.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_kCardRadius - 1),
                child: Stack(
                  children: [
                    // Full-bleed generated artwork (background + album cascade).
                    Positioned.fill(child: _CardBackground(plan: plan)),
                    // Bound text to the dark left zone so it never sprawls
                    // across the artwork; scale it with the card width.
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Size off the card HEIGHT: these banners are 3:1 and
                          // short, so width-scaled text overflows the height.
                          final cardWidth = constraints.maxWidth;
                          final cardHeight = constraints.maxHeight;
                          final padX = cardWidth * 0.045;
                          final padY = cardHeight * 0.1;
                          final textMax = (cardWidth * _kTextZoneWidth - padX)
                              .clamp(0.0, cardWidth);
                          final iconSize = cardHeight * 0.22;
                          final titleSize = cardHeight * 0.125;
                          final descSize = cardHeight * 0.075;
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: padX,
                              vertical: padY,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: textMax),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _iconBadge(tint, iconSize),
                                    SizedBox(height: cardHeight * 0.05),
                                    _OutlinedText(
                                      plan.title,
                                      style: KalinkaFonts.sans(
                                        fontSize: titleSize,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                      ),
                                      strokeWidth: titleSize * _kStrokeRatio,
                                      maxLines: 1,
                                    ),
                                    if (description.isNotEmpty) ...[
                                      SizedBox(height: cardHeight * 0.03),
                                      _OutlinedText(
                                        description,
                                        style: KalinkaFonts.sans(
                                          fontSize: descSize,
                                          height: 1.2,
                                        ),
                                        fillColor: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        strokeWidth: descSize * _kStrokeRatio,
                                        maxLines: 2,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Right-center chevron affordance; fills with the source
                    // tint (selected) when the card is hovered.
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final d = constraints.maxHeight * 0.26;
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: constraints.maxWidth * 0.03,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: d,
                                height: d,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _hovered
                                      ? tint.withValues(alpha: 0.95)
                                      : Colors.black.withValues(alpha: 0.28),
                                  border: Border.all(
                                    color: _hovered
                                        ? tint
                                        : Colors.white.withValues(alpha: 0.45),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: d * 0.7,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBadge(Color tint, double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tint.withValues(alpha: 0.30),
          Colors.black.withValues(alpha: 0.38),
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: tint.withValues(alpha: 0.60), width: 1),
      ),
      child: Icon(
        _iconForId(widget.plan.icon) ?? _contentIcon(widget.plan.contentType),
        size: size * 0.56,
        color: Colors.white,
      ),
    );
  }

  IconData _contentIcon(PreviewContentType? type) {
    switch (type) {
      case PreviewContentType.artist:
        return Icons.person_outline;
      case PreviewContentType.playlist:
        return Icons.queue_music_rounded;
      case PreviewContentType.track:
        return Icons.music_note_rounded;
      case PreviewContentType.catalog:
        return Icons.grid_view_rounded;
      case PreviewContentType.album:
      case PreviewContentType.unknown:
      case null:
        return Icons.album_outlined;
    }
  }
}

/// Full-bleed generated artwork behind the card, or black until it exists / on
/// error. The URL key forces a re-decode when the link changes.
class _CardBackground extends ConsumerWidget {
  final CatalogCardPlan plan;

  const _CardBackground({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = plan.artPath;
    if (path == null || path.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    final url = ref.watch(urlResolverProvider).abs(path);
    return Image.network(
      url,
      key: ValueKey(url),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      // Fade in once decoded so the swap from black isn't a hard cut.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
    );
  }
}

/// Shimmer twin of a catalog card: same frame and aspect, neutral surfaces,
/// pulsing opacity like [ZeroStateShimmer].
class _ShimmerCatalogCard extends StatefulWidget {
  const _ShimmerCatalogCard();

  @override
  State<_ShimmerCatalogCard> createState() => _ShimmerCatalogCardState();
}

class _ShimmerCatalogCardState extends State<_ShimmerCatalogCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.4,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) =>
          Opacity(opacity: _opacity.value, child: child),
      child: AspectRatio(
        aspectRatio: _kCardAspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = _contentScale(constraints.maxWidth);
            return Container(
              padding: EdgeInsets.all(_kCardBasePad * scale),
              decoration: BoxDecoration(
                color: KalinkaColors.surfaceRaised,
                borderRadius: BorderRadius.circular(_kCardRadius),
                border: Border.all(color: KalinkaColors.borderSubtle, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: _kBadgeSize * scale,
                        height: _kBadgeSize * scale,
                        decoration: BoxDecoration(
                          color: KalinkaColors.surfaceInput,
                          borderRadius: BorderRadius.circular(9 * scale),
                        ),
                      ),
                      SizedBox(width: 10 * scale),
                      Expanded(
                        child: _ShimmerBar(width: 120, height: 14 * scale),
                      ),
                    ],
                  ),
                  SizedBox(height: 12 * scale),
                  _ShimmerBar(width: 150, height: 10 * scale),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// White text with a crisp dark outline (a stroke drawn under the fill), so it
/// stays legible on any background. [style] must not set a color.
class _OutlinedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double strokeWidth;
  final Color fillColor;
  final int maxLines;

  const _OutlinedText(
    this.text, {
    required this.style,
    required this.strokeWidth,
    this.fillColor = Colors.white,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xE6000000),
          ),
        ),
        Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: fillColor),
        ),
      ],
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  final double width;
  final double height;

  const _ShimmerBar({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceInput,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
