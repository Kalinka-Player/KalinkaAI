import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'procedural_album_art.dart';

/// A collection's cover wherever it is shown: the server's collage once
/// there are tracks to compose one from, and the stand-in tile until then.
/// One rule for the row and the page, so a collection looks the same in
/// both.
class CollectionCover extends StatelessWidget {
  /// The collage, already resolved to an absolute URL; null before the
  /// server has rendered one.
  final String? artUrl;

  /// How many tracks the collection holds. An empty one has nothing to
  /// compose, so it shows the tile even if stale art exists for it.
  final int? trackCount;

  /// Seeds the tile, so one collection always gets the same one.
  final String seed;
  final double size;
  final double radius;

  const CollectionCover({
    super.key,
    required this.artUrl,
    required this.trackCount,
    required this.seed,
    required this.size,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final tile = CollectionArtTile(seed: seed, size: size, radius: radius);
    final url = artUrl;
    if (url == null || trackCount == 0) return tile;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        cacheHeight: (size * 3).round(),
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => tile,
      ),
    );
  }
}

/// The stand-in cover for a collection with no collage of its own: the
/// generated rings, with the playlist glyph over them and a mark that says
/// there is room for more.
class CollectionArtTile extends StatelessWidget {
  /// Seeds the generated art, so one collection always gets the same tile.
  final String seed;
  final double size;
  final double radius;

  const CollectionArtTile({
    super.key,
    required this.seed,
    required this.size,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = size * 0.42;
    final badge = (glyph * 0.36).clamp(14.0, 26.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ProceduralAlbumArt(trackId: seed, size: size),
            Container(
              width: glyph,
              height: glyph,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(glyph * 0.18),
                border: Border.all(
                  color: KalinkaColors.textPrimary.withValues(alpha: 0.55),
                  width: (glyph * 0.045).clamp(1.5, 3.0),
                ),
              ),
              child: Icon(
                Icons.queue_music_rounded,
                size: glyph * 0.62,
                color: KalinkaColors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            Positioned(
              left: size / 2 + glyph * 0.28,
              top: size / 2 + glyph * 0.28,
              child: Container(
                width: badge,
                height: badge,
                decoration: const BoxDecoration(
                  color: KalinkaColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add,
                  size: badge * 0.7,
                  color: KalinkaColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
