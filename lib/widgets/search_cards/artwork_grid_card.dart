import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import 'browse_navigation_scope.dart';
import 'row_play_button.dart';

/// An album, artist or playlist in an artwork grid: its square cover (round
/// for an artist), name and one line of detail. The cover and name open its
/// page; Play, where it has one, rests on the cover so touch and keyboard
/// reach it without hovering. Long-press takes a playable one into the
/// selection, as its row would.
class ArtworkGridCard extends ConsumerWidget {
  final BrowseItem item;

  static const _inset = 6.0;

  const ArtworkGridCard({super.key, required this.item});

  /// What [item] is called on its card, and the detail under it.
  static (String, String) captionOf(BrowseItem item) {
    final album = item.album;
    if (album != null) {
      return (
        album.title,
        [
          if (album.artist?.name case final artist? when artist.isNotEmpty)
            artist,
          if (album.year != null) '${album.year}',
        ].join(' · '),
      );
    }
    final artist = item.artist;
    if (artist != null) {
      final count = artist.albumCount;
      return (
        artist.name,
        count == null ? '' : '$count ${count == 1 ? 'album' : 'albums'}',
      );
    }
    final playlist = item.playlist;
    if (playlist != null) {
      final count = playlist.trackCount;
      return (
        playlist.name,
        count == null ? '' : '$count ${count == 1 ? 'track' : 'tracks'}',
      );
    }
    return (item.name ?? 'Unknown', item.subname ?? '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, detail) = captionOf(item);
    final round = item.browseType == BrowseType.artist;
    final playable = item.canAdd && !round;
    final selecting = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    final selected =
        playable &&
        ref.watch(
          selectionStateProvider.select((s) => s.isContainerSelected(item.id)),
        );
    void select() =>
        ref.read(selectionStateProvider.notifier).toggleContainer(item.id);
    void activate() {
      if (selecting && playable) {
        select();
      } else if (!selecting) {
        openBrowsable(context, ref, item);
      }
    }

    final path =
        item.image?.large ?? item.image?.small ?? item.image?.thumbnail;
    final url = path == null ? null : ref.read(urlResolverProvider).abs(path);

    final card = Semantics(
      button: true,
      selected: selecting ? selected : null,
      label: [title, if (detail.isNotEmpty) detail].join(', '),
      excludeSemantics: true,
      onTap: activate,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: activate,
          onLongPress: playable && !selecting ? select : null,
          borderRadius: BorderRadius.circular(12),
          focusColor: KalinkaColors.surfaceOverlay,
          hoverColor: KalinkaColors.surfaceRaised,
          child: Padding(
            padding: const EdgeInsets.all(_inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.maxWidth;
                      final stand = ProceduralAlbumArt(
                        trackId: item.id,
                        size: size,
                      );
                      final art = url == null
                          ? stand
                          : Image.network(
                              url,
                              width: size,
                              height: size,
                              cacheWidth: (size * 2.5).round(),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, _, _) => stand,
                            );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          round
                              ? ClipOval(child: art)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: art,
                                ),
                          if (selected)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: KalinkaColors.accent.withValues(
                                  alpha: 0.4,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: KalinkaTextStyles.trackRowTitle.copyWith(
                    color: selected ? KalinkaColors.accentTint : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (sourceBadgeVisible(ref, item.id)) ...[
                      SourceBadge(
                        entityId: item.id,
                        size: SourceBadgeSize.small,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (detail.isNotEmpty)
                      Expanded(
                        child: Text(
                          detail,
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
        ),
      ),
    );
    if (!playable || selecting) return card;
    // Play rests on the cover's corner, a target of its own beside the way in.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cover = constraints.maxWidth - 2 * _inset;
        return Stack(
          children: [
            card,
            Positioned(
              right: _inset + 2,
              top: _inset + cover - 50,
              child: RowPlayButton(item: item),
            ),
          ],
        );
      },
    );
  }
}
