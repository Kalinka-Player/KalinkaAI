import 'package:flutter/material.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../data_model/search_results.dart';
import '../../theme/app_theme.dart';
import '../loading_shimmer.dart';
import '../search_cards/track_row_support.dart';
import '../source_badge.dart';
import 'source_unavailable_row.dart';

/// Recommendations keep each backend's order and identity. Opening a card
/// browses the source's answer; playback belongs to the track-list page.
class InspiredBlock extends StatelessWidget {
  final SearchResults results;
  final NarrowedResults narrowed;
  final BrowseFilterQuery filter;
  final ValueChanged<String> onViewAll;
  final ValueChanged<String> onRetry;
  final double gutter;

  const InspiredBlock({
    super.key,
    required this.results,
    required this.narrowed,
    required this.filter,
    required this.onViewAll,
    required this.onRetry,
    this.gutter = 0,
  });

  static bool visible(
    SearchResults results,
    NarrowedResults narrowed,
    BrowseFilterQuery filter,
  ) =>
      filter.kind != ResultKind.nameMatches &&
      (filter.type == null || filter.type == SearchType.track) &&
      narrowed.groups.any((g) => g.state is! LegReady || g.tracks.isNotEmpty);

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(child: InspiredHeading(gutter: gutter)),
      for (final group in narrowed.groups)
        if (group.state is LegFailed)
          SliverToBoxAdapter(
            child: SourceUnavailableRow(
              source: group.source,
              title: results.sources.titleOf(group.source),
              onRetry: () => onRetry(group.source),
            ),
          )
        else if (group.state is LegLoading)
          SliverToBoxAdapter(
            child: InspiredSourceCardShimmer(
              source: group.source,
              title: results.sources.titleOf(group.source),
            ),
          )
        else if (group.tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: InspiredSourceCard(
              group: group,
              title: results.sources.titleOf(group.source),
              onTap: () => onViewAll(group.source),
            ),
          ),
    ],
  );
}

/// Kalinka's display heading and neutral wash, with its shared search mark.
class InspiredHeading extends StatelessWidget {
  final double gutter;
  final bool caption;
  const InspiredHeading({super.key, this.gutter = 0, this.caption = true});

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: -gutter,
        right: -gutter,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  KalinkaColors.surfaceElevated.withValues(alpha: 0),
                  KalinkaColors.surfaceElevated,
                  KalinkaColors.surfaceElevated.withValues(alpha: 0),
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: KalinkaColors.accentTint,
                        ),
                      ),
                    ),
                    const TextSpan(text: 'Inspired by your request'),
                  ],
                ),
                style: KalinkaTextStyles.blockTitle,
              ),
            ),
            if (caption) ...[
              const SizedBox(height: 6),
              Text('AI search', style: KalinkaTextStyles.trackRowSubtitle),
            ],
          ],
        ),
      ),
    ],
  );
}

/// Read the first three distinct names from the returned tracks, in backend
/// order. No artist lookups or extra requests are needed for this preview.
List<String> _performersOf(List<BrowseItem> tracks) {
  final names = <String>[];
  final seen = <String>{};
  String? known(String? value) {
    final name = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name == null ||
        name.isEmpty ||
        const {
          'unknown',
          'unknown artist',
          'unknown performer',
        }.contains(name.toLowerCase())) {
      return null;
    }
    return name;
  }

  for (final item in tracks) {
    final track = item.track;
    final name =
        known(track?.performer?.name) ?? known(track?.album?.artist?.name);
    if (name != null && seen.add(name.toLowerCase())) names.add(name);
    if (names.length == 3) break;
  }
  return names;
}

/// Pick distinct artwork paths from the existing answer without changing
/// its playback order or looking up more albums. Prefer actual covers; when
/// none are supplied, keep the normal per-track artwork fallbacks.
List<BrowseItem> _collageTracks(List<BrowseItem> tracks) {
  final covers = <BrowseItem>[];
  final seen = <String>{};
  for (final item in tracks) {
    final path = item.image?.smallest;
    if (path == null || path.isEmpty || !seen.add(path)) continue;
    covers.add(item);
    if (covers.length == 4) break;
  }
  return covers.isEmpty ? tracks.take(4).toList() : covers;
}

class InspiredSourceCard extends StatelessWidget {
  final InspiredGroup group;
  final String title;
  final VoidCallback onTap;
  const InspiredSourceCard({
    super.key,
    required this.group,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final performers = _performersOf(group.tracks);
    final covers = _collageTracks(group.tracks);
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(14),
          hoverColor: KalinkaColors.surfaceOverlay,
          focusColor: KalinkaColors.surfaceOverlay,
          child: _SourceCardLayout(
            cover: (i, size) => TrackThumb(
              item: covers[i % covers.length],
              size: size,
              radius: 0,
            ),
            details: (compact) => _SourceDetails(
              source: group.source,
              title: title,
              compact: compact,
              trackCount: group.tracks.length,
              performers: performers,
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: KalinkaColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The same responsive collage and source details while tracks are pending.
class InspiredSourceCardShimmer extends StatelessWidget {
  final String source;
  final String title;
  const InspiredSourceCardShimmer({
    super.key,
    required this.source,
    required this.title,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading recommendations from $title',
    child: ExcludeSemantics(
      child: ShimmerPulse(
        child: _SourceCardLayout(
          cover: (i, size) => SizedBox.square(
            key: ValueKey('inspired-cover-placeholder-$i'),
            dimension: size,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: const ShimmerBlock(radius: 0),
            ),
          ),
          details: (compact) =>
              _SourceDetails(source: source, title: title, compact: compact),
          trailing: const SizedBox.square(
            dimension: 24,
            child: Center(
              child: ShimmerBlock(width: 12, height: 16, radius: 4),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shared text layout for the loaded card and its shimmer. A missing count
/// means the source's tracks have not arrived yet.
class _SourceDetails extends StatelessWidget {
  final String source;
  final String title;
  final bool compact;
  final int? trackCount;
  final List<String> performers;
  const _SourceDetails({
    required this.source,
    required this.title,
    required this.compact,
    this.trackCount,
    this.performers = const [],
  });

  @override
  Widget build(BuildContext context) {
    final loading = trackCount == null;
    final performerStyle = KalinkaTextStyles.trackRowTitle.copyWith(
      color: KalinkaColors.textSecondary,
    );
    final badge = ExcludeSemantics(
      child: SourceTile(
        source: source,
        small: true,
        size: 20,
        foreground: KalinkaColors.textPrimary,
      ),
    );
    final names = loading
        ? const ['Performer name', 'Performer name', 'Performer name']
        : performers;
    final count = trackCount ?? 20;
    Widget text(String value, TextStyle style, {bool singleLine = false}) =>
        loading
        ? _textPlaceholder(context, value, style, singleLine: singleLine)
        : Text(
            value,
            style: style,
            maxLines: singleLine ? 1 : null,
            overflow: singleLine ? TextOverflow.ellipsis : null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (loading)
              Stack(
                children: [
                  Opacity(opacity: 0, child: badge),
                  const Positioned.fill(child: ShimmerBlock(radius: 4)),
                ],
              )
            else
              badge,
            const SizedBox(width: 8),
            Expanded(child: text(title, KalinkaTextStyles.inspiredSourceTitle)),
          ],
        ),
        const SizedBox(height: 6),
        text(
          '$count track${count == 1 ? '' : 's'}',
          KalinkaTextStyles.trackRowSubtitle,
        ),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (compact)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  for (final name in names)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Text('•', style: performerStyle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: text(name, performerStyle, singleLine: true),
                        ),
                      ],
                    ),
                  // Keep the preview's three-line footprint when fewer
                  // distinct names are available, including after loading.
                  for (var i = names.length; i < 3; i++)
                    ExcludeSemantics(child: Text(' ', style: performerStyle)),
                ],
              ),
            )
          else
            text(names.join(' · '), performerStyle, singleLine: true),
        ],
      ],
    );
  }

  Widget _textPlaceholder(
    BuildContext context,
    String text,
    TextStyle style, {
    bool singleLine = false,
  }) => Stack(
    children: [
      // Match the loaded font's metrics and wrapping at the listener's scale.
      Opacity(
        opacity: 0,
        child: Text(
          text,
          style: style,
          maxLines: singleLine ? 1 : null,
          overflow: singleLine ? TextOverflow.ellipsis : null,
        ),
      ),
      Positioned.fill(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: .8,
            child: ShimmerBlock(
              height: MediaQuery.textScalerOf(context).scale(style.fontSize!),
              radius: 4,
            ),
          ),
        ),
      ),
    ],
  );
}

/// Shared loading/loaded geometry prevents a tall placeholder replacing a
/// compact source card, or artwork moving when the request completes.
class _SourceCardLayout extends StatelessWidget {
  final Widget Function(int index, double size) cover;
  final Widget Function(bool compact) details;
  final Widget trailing;
  const _SourceCardLayout({
    required this.cover,
    required this.details,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth <
          600 * MediaQuery.textScalerOf(context).scale(1);
      final columns = compact ? 2 : 4;
      final sourceDetails = details(compact);
      // A modest square on phones and beside name matches; four across when
      // this pane itself has room. Artwork never grows to fill vertical space.
      final width = compact
          ? ((constraints.maxWidth - 8) * .42).clamp(0.0, 180.0)
          : ((constraints.maxWidth - 8) * .6).clamp(0.0, 480.0);
      final size = width / columns;
      final stacked =
          constraints.maxWidth <
          280 * MediaQuery.textScalerOf(context).scale(1);
      final art = ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: width,
            height: size * (4 ~/ columns),
            child: Column(
              children: [
                for (var row = 0; row < 4 ~/ columns; row++)
                  Row(
                    children: [
                      for (var col = 0; col < columns; col++)
                        cover(row * columns + col, size),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KalinkaColors.borderSubtle)),
        ),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  art,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: sourceDetails),
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  art,
                  const SizedBox(width: 16),
                  Expanded(child: sourceDetails),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
      );
    },
  );
}
