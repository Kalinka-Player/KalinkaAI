import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../fitted_title.dart';
import '../procedural_album_art.dart';
import '../search_cards/track_row_support.dart';
import 'track_group_actions.dart';

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
    final duration = totalDurationSeconds ?? page.totalDurationSeconds;
    final summary = [
      if (trackCount != null)
        '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
      if (duration != null && duration > 0) formatTotalDuration(duration),
    ].join(' · ');

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
                          const SizedBox(height: 12),
                          Text(
                            artist,
                            style: KalinkaFonts.sans(
                              fontSize: 16,
                              height: 1.4,
                              color: KalinkaColors.textPrimary,
                            ),
                          ),
                        ],
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
