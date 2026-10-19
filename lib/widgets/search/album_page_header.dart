import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../fitted_title.dart';
import '../procedural_album_art.dart';
import '../search_cards/track_row_support.dart';
import '../source_badge.dart';
import 'track_group_actions.dart';

/// A phone-wide pane stacks an album's cover over its tracks; anything wider
/// sets the cover and what it says in a column beside them.
const double kAlbumSideLayoutWidth = 480;

/// The artist an album page can open: only one its listing named by a full
/// id, so the link keeps the album's source and never looks a name up.
BrowseItem? albumArtistLink(CatalogPage page) {
  final artist = page.item?.album?.artist;
  if (artist == null) return null;
  try {
    if (EntityId.fromString(artist.id).type != EntityType.artist) return null;
  } catch (_) {
    return null;
  }
  return BrowseItem(
    id: artist.id,
    name: artist.name,
    canBrowse: true,
    canAdd: false,
    artist: artist,
  );
}

/// The album's artist, opening the artist's page where the album says which
/// one it is; plain text otherwise.
class _ArtistLine extends ConsumerWidget {
  final CatalogPage page;
  final String name;

  const _ArtistLine({required this.page, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = KalinkaFonts.sans(
      fontSize: 16,
      height: 1.4,
      color: KalinkaColors.textPrimary,
    );
    final link = albumArtistLink(page);
    if (link == null) return Text(name, style: style);
    return Semantics(
      link: true,
      label: 'Open $name',
      excludeSemantics: true,
      child: InkWell(
        onTap: () =>
            ref.read(searchSessionProvider.notifier).openBrowseItem(link),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: style.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: KalinkaColors.textMuted,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: KalinkaColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The album's source, said once for the page.
class _SourceLine extends ConsumerWidget {
  final CatalogPage page;

  const _SourceLine({required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = page.provider?.trim() ?? '';
    if (provider.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SourceBadge(entityId: page.id!),
        if (sourceBadgeVisible(ref, page.id!)) const SizedBox(width: 7),
        Flexible(
          child: Text(
            provider,
            style: KalinkaTextStyles.trackRowSubtitle.copyWith(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// What an album is, beside its tracks on a wide pane: the square cover,
/// title, artist, source, extent and the actions on the whole of it. Its own
/// scroll, so a long title or enlarged text never clips.
class AlbumIdentityColumn extends StatelessWidget {
  final CatalogPage page;
  final int? trackCount;
  final int? totalDurationSeconds;

  const AlbumIdentityColumn({
    super.key,
    required this.page,
    this.trackCount,
    this.totalDurationSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final title = page.title ?? '';
    final artist = page.description?.trim() ?? '';
    final summary = _summary(
      trackCount,
      totalDurationSeconds ?? page.totalDurationSeconds,
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AlbumArtwork(page: page),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'ALBUM',
              style: KalinkaFonts.mono(
                fontSize: 12,
                letterSpacing: 2,
                color: KalinkaColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                title,
                style: KalinkaFonts.display(
                  fontSize: constraints.maxWidth < 300 ? 24 : 30,
                  height: 1.15,
                  letterSpacing: -0.5,
                  fontWeight: FontWeight.w500,
                  color: KalinkaColors.frost,
                ),
              ),
            ),
            if (artist.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ArtistLine(page: page, name: artist),
            ],
            const SizedBox(height: 8),
            _SourceLine(page: page),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                summary,
                style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PlayAllChip(trackIds: [page.id!], trackCount: trackCount),
                AddAllChip(
                  trackIds: [page.id!],
                  trackCount: trackCount,
                  name: title,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _summary(int? trackCount, int? duration) => [
  if (trackCount != null) '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
  if (duration != null && duration > 0) formatTotalDuration(duration),
].join(' · ');

/// The cover is the album's backdrop. Its shade follows the text block, so
/// even long titles and enlarged system text stay on a dark enough surface.
class AlbumPageHeader extends ConsumerWidget {
  final CatalogPage page;
  final int? trackCount;
  final int? totalDurationSeconds;

  /// Home paints the cover behind its navigation and system status inset.
  /// Standalone uses can keep the same cover inside this header.
  final bool showArtwork;

  const AlbumPageHeader({
    super.key,
    required this.page,
    this.trackCount,
    this.totalDurationSeconds,
    this.showArtwork = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = page.title ?? '';
    final artist = page.description?.trim() ?? '';
    final summary = _summary(
      trackCount,
      totalDurationSeconds ?? page.totalDurationSeconds,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // A compact cover leaves more tracks visible. This is a minimum so
        // enlarged system text can still grow the header without clipping.
        final heroHeight = width.clamp(320.0, 440.0);
        final titleSize = (width * 0.10).clamp(36.0, 52.0);
        final shade = KalinkaColors.background.withValues(alpha: 0.76);
        return Stack(
          children: [
            if (showArtwork) Positioned.fill(child: AlbumArtwork(page: page)),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: heroHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A separate lead-in keeps the art clear above the
                  // title; the title's own shade starts at 76% even when
                  // its height changes with wrapping or text scaling.
                  SizedBox(
                    height: 64,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            KalinkaColors.background.withValues(alpha: 0),
                            shade,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [shade, KalinkaColors.background],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ALBUM',
                          style: KalinkaFonts.mono(
                            fontSize: 12,
                            letterSpacing: 2,
                            color: KalinkaColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          header: true,
                          child: FittedTitle(
                            title,
                            // Keep long names within two display lines' height,
                            // leaving the cover visible above the metadata.
                            minFontSize: 24,
                            lines: 2,
                            style: KalinkaFonts.display(
                              fontSize: titleSize,
                              height: 1.12,
                              letterSpacing: -0.7,
                              fontWeight: FontWeight.w500,
                              color: KalinkaColors.frost,
                            ),
                          ),
                        ),
                        if (artist.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _ArtistLine(page: page, name: artist),
                        ],
                        const SizedBox(height: 4),
                        _SourceLine(page: page),
                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            summary,
                            style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            PlayAllChip(
                              trackIds: [page.id!],
                              trackCount: trackCount,
                            ),
                            AddAllChip(
                              trackIds: [page.id!],
                              trackCount: trackCount,
                              name: title,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single crisp cover shared by the system area, navigation and album
/// introduction. Its parent sizes it to the measured start of the track list.
class AlbumArtwork extends ConsumerWidget {
  final CatalogPage page;

  const AlbumArtwork({super.key, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = page.artPath;
    final url = path == null ? null : ref.watch(urlResolverProvider).abs(path);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final fallback = ProceduralAlbumArt(trackId: page.id!, size: width);
          // Reuse a few decoded sizes instead of creating a new cache entry
          // for every pixel of a window resize. Include height for cover-fit.
          final physicalSize =
              constraints.biggest.longestSide *
              MediaQuery.devicePixelRatioOf(context);
          final decodeSize = ((physicalSize / 512).ceil() * 512).clamp(
            512,
            2048,
          );
          return ClipRect(
            child: url == null
                ? fallback
                : _AlbumCoverImage(
                    // A different album must never retain the previous cover.
                    key: ValueKey(url),
                    url: url,
                    decodeSize: decodeSize,
                    fallback: fallback,
                  ),
          );
        },
      ),
    );
  }
}

class _AlbumCoverImage extends StatefulWidget {
  final String url;
  final int decodeSize;
  final Widget fallback;

  const _AlbumCoverImage({
    super.key,
    required this.url,
    required this.decodeSize,
    required this.fallback,
  });

  @override
  State<_AlbumCoverImage> createState() => _AlbumCoverImageState();
}

class _AlbumCoverImageState extends State<_AlbumCoverImage> {
  late int _decodeSize = widget.decodeSize;

  @override
  void didUpdateWidget(_AlbumCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the larger decode when shrinking or rotating back. Only upgrade
    // when needed, retaining the current frame while that decode is pending.
    if (widget.decodeSize > _decodeSize) _decodeSize = widget.decodeSize;
  }

  @override
  Widget build(BuildContext context) => Image.network(
    widget.url,
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    cacheWidth: _decodeSize,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => widget.fallback,
  );
}

/// Home's album cover spans the Android system inset, the pinned breadcrumb,
/// and the measured introduction. Only its transform updates while scrolling.
class AlbumPageBackdrop extends StatelessWidget {
  final CatalogPage page;
  final ValueListenable<double> headerHeight;
  final ValueListenable<double> scrollOffset;

  const AlbumPageBackdrop({
    super.key,
    required this.page,
    required this.headerHeight,
    required this.scrollOffset,
  });

  @override
  Widget build(BuildContext context) {
    final chromeHeight =
        MediaQuery.paddingOf(context).top + kKalinkaTopBarHeight;
    return IgnorePointer(
      child: Stack(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: scrollOffset,
            builder: (context, offset, child) =>
                Transform.translate(offset: Offset(0, -offset), child: child),
            child: ValueListenableBuilder<double>(
              valueListenable: headerHeight,
              builder: (context, height, child) => SizedBox(
                width: double.infinity,
                height: chromeHeight + height,
                child: child,
              ),
              child: RepaintBoundary(
                child: AlbumArtwork(
                  key: const ValueKey('album-backdrop'),
                  page: page,
                ),
              ),
            ),
          ),
          // Protect the white system icons and breadcrumb over pale art;
          // the separate, content-sized shade in the header covers its text.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: chromeHeight + 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, chromeHeight / (chromeHeight + 48), 1],
                  colors: [
                    KalinkaColors.background.withValues(alpha: 0.84),
                    KalinkaColors.background.withValues(alpha: 0.84),
                    KalinkaColors.background.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
