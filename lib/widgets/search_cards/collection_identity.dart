import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/catalog_cards_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../collection_art_tile.dart';
import '../source_badge.dart';
import 'long_press_ring_painter.dart';
import 'track_row_support.dart';

/// Which collection a row is about: its cover, its name, and under it the
/// sources it draws on beside what it holds.
///
/// Laid out to fill the width it is given, so a caller puts it in an
/// [Expanded] and keeps whatever sits at the row's right end to itself.
class CollectionIdentity extends ConsumerWidget {
  final BrowseItem item;

  /// Drawn as the one taken: the name warms to match the row under it.
  final bool chosen;

  /// Laid over the cover, where that is how the row is marked. A row that
  /// says so some other way — a control at its end — passes none.
  final IconData? coverMark;

  /// How far a long press that would take it has run, 0 when none is.
  final double pressProgress;

  /// An action on the name itself, drawn right after it. Editing puts the
  /// rename pencil here, where the action row it usually sits on is given
  /// over to the tracks.
  final Widget? nameAction;

  const CollectionIdentity({
    super.key,
    required this.item,
    this.chosen = false,
    this.coverMark,
    this.pressProgress = 0,
    this.nameAction,
  });

  static const _thumb = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = item.playlist;
    final artPath = artPathOf(item);
    final sources = item.catalog?.sources ?? const <String>[];

    return Row(
      children: [
        SizedBox(
          width: _thumb,
          height: _thumb,
          child: Stack(
            children: [
              CollectionCover(
                artUrl: artPath == null
                    ? null
                    : ref.read(urlResolverProvider).abs(artPath),
                trackCount: playlist?.trackCount,
                seed: item.id,
                size: _thumb,
                radius: 10,
              ),
              if (pressProgress > 0)
                Positioned.fill(
                  child: CustomPaint(
                    painter: LongPressRingPainter(
                      progress: pressProgress,
                      color: KalinkaColors.accent,
                    ),
                  ),
                ),
              if (coverMark != null)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: KalinkaColors.accent.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(coverMark, color: Colors.white, size: 24),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      playlist?.name ?? item.name ?? 'Unknown',
                      style: KalinkaTextStyles.listName.copyWith(
                        color: chosen ? KalinkaColors.accentTint : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (nameAction != null) nameAction!,
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  for (final source in sources) ...[
                    SourceTile(source: source, size: 18),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      collectionSummary(item),
                      style: KalinkaTextStyles.trackRowSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What a collection holds, in one line: how many tracks and how long it
/// runs. Which sources they came from is said beside it, in their own
/// colours. An empty collection says so instead of counting to zero.
String collectionSummary(BrowseItem item) {
  final count = item.playlist?.trackCount;
  if (count == 0) return 'Empty collection';
  final duration = item.playlist?.duration;
  return [
    if (count != null) '$count ${count == 1 ? 'track' : 'tracks'}',
    if (duration != null && duration > 0) formatTotalDuration(duration),
  ].join(' · ');
}
