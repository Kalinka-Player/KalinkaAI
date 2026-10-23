import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../fitted_title.dart';
import '../measure_size.dart';
import '../procedural_album_art.dart';
import '../search_cards/track_row_support.dart';
import '../source_badge.dart';
import 'track_group_actions.dart';

/// A pane narrower than this stacks an album's cover over its tracks; from
/// here the cover and what it says stand in a column beside them.
const double kAlbumSideLayoutWidth = 528;

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
        mouseCursor: WidgetStateMouseCursor.clickable,
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
/// title, artist, source, extent and the actions on the whole of it. The page
/// scrolls this content together with the tracks, including enlarged text.
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
      builder: (context, constraints) => Padding(
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
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
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

  /// How far above the header's foot the title ends, so Home's bar can take
  /// the title over once it has scrolled away.
  final ValueChanged<double>? onTitleInset;

  const AlbumPageHeader({
    super.key,
    required this.page,
    this.trackCount,
    this.totalDurationSeconds,
    this.showArtwork = true,
    this.onTitleInset,
  });

  static const _bottomPadding = 20.0;

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
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
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
        );
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
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      _bottomPadding,
                    ),
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
                        if (onTitleInset case final report?)
                          MeasureSize(
                            onChange: (size) =>
                                report(size.height + _bottomPadding),
                            child: details,
                          )
                        else
                          details,
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
/// and the measured introduction. It stays put while the page scrolls up
/// over it, hidden from the header's foot down and fading as it goes.
class AlbumPageBackdrop extends StatelessWidget {
  final CatalogPage page;
  final ValueListenable<double> headerHeight;
  final ValueListenable<double> scrollOffset;

  /// Darkens the top for the status bar and breadcrumb.
  final bool shaded;

  final Key artworkKey;

  const AlbumPageBackdrop({
    super.key,
    required this.page,
    required this.headerHeight,
    required this.scrollOffset,
    this.shaded = true,
    this.artworkKey = const ValueKey('album-backdrop'),
  });

  @override
  Widget build(BuildContext context) {
    final chromeHeight =
        MediaQuery.paddingOf(context).top + kKalinkaTopBarHeight;
    return IgnorePointer(
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([headerHeight, scrollOffset]),
            builder: (context, child) {
              final height = headerHeight.value;
              final offset = scrollOffset.value;
              return SizedBox(
                width: double.infinity,
                height: chromeHeight + height,
                child: ClipRect(
                  clipper: _UncoveredClip(chromeHeight + height - offset),
                  child: Opacity(
                    opacity: height <= 0
                        ? 1
                        : 1 - (offset / height).clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              );
            },
            child: RepaintBoundary(
              child: AlbumArtwork(key: artworkKey, page: page),
            ),
          ),
          // Protect the white system icons and breadcrumb over pale art;
          // the separate, content-sized shade in the header covers its text.
          if (shaded)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: chromeHeight + AlbumStatusShade.fade,
              child: const AlbumStatusShade(),
            ),
        ],
      ),
    );
  }
}

/// What of the cover the page has not yet risen over: everything above
/// [bottom].
class _UncoveredClip extends CustomClipper<Rect> {
  final double bottom;

  const _UncoveredClip(this.bottom);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width, bottom.clamp(0.0, size.height));

  @override
  bool shouldReclip(_UncoveredClip oldClipper) => oldClipper.bottom != bottom;
}

/// The shade over the top of an album's cover: solid behind the status bar
/// and breadcrumb, then fading out over [fade].
class AlbumStatusShade extends StatelessWidget {
  const AlbumStatusShade({super.key});

  static const fade = 48.0;

  @override
  Widget build(BuildContext context) {
    final chromeHeight =
        MediaQuery.paddingOf(context).top + kKalinkaTopBarHeight;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, chromeHeight / (chromeHeight + fade), 1],
          colors: [
            KalinkaColors.background.withValues(alpha: 0.84),
            KalinkaColors.background.withValues(alpha: 0.84),
            KalinkaColors.background.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
