import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/artist_relations_provider.dart' show imagePathOf;
import '../../providers/selection_state_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../catalog_art.dart';
import '../modifier_click.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import '../tap_highlight.dart' show kalinkaOverlay;
import 'browse_navigation_scope.dart';
import 'row_play_button.dart';

/// An artwork grid item: square covers and round artist portraits followed by
/// a name and detail, or a catalog's card with its name on it. The cover and
/// name open its page; Play rests on the cover while the card is lit,
/// and always on a touch screen. Long-press takes a playable item into the
/// selection, as its row would. Under the pointer, held or focused, the whole
/// card is outlined, as the cards of a Home rail are.
class ArtworkGridCard extends ConsumerStatefulWidget {
  final BrowseItem item;

  /// Between the card's frame and its cover and caption: half the room
  /// between two covers, so frames abut and two outlines side by side meet.
  static const inset = kKalinkaFrameInset;

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
  ConsumerState<ArtworkGridCard> createState() => _ArtworkGridCardState();
}

class _ArtworkGridCardState extends ConsumerState<ArtworkGridCard> {
  static const _inset = ArtworkGridCard.inset;

  /// Concentric with the cover's corners, a frame's inset out.
  static final _frame = BorderRadius.circular(10 + _inset);

  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  BrowseItem get item => widget.item;

  @override
  Widget build(BuildContext context) {
    final catalog = item.browseType == BrowseType.catalog;
    final (title, detail) = catalog
        ? (
            item.catalog?.title ?? item.name ?? 'Catalog',
            item.description ?? '',
          )
        : ArtworkGridCard.captionOf(item);
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

    final path = imagePathOf(item.image);
    final showSource = sourceBadgeVisible(ref, item.id);

    final card = ModifierClick(
      onModifiedClick: playable && !selecting ? select : null,
      child: Semantics(
        button: true,
        selected: selecting ? selected : null,
        label: [title, if (detail.isNotEmpty) detail].join(', '),
        explicitChildNodes: true,
        onTap: activate,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            excludeFromSemantics: true,
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: activate,
            onLongPress: playable && !selecting ? select : null,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            overlayColor: kalinkaOverlay,
            borderRadius: _frame,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: _frame,
                border: Border.all(
                  color: _hovered || _focused || _pressed
                      ? KalinkaColors.borderDefault
                      : Colors.transparent,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _artwork(
                      path: path,
                      round: round,
                      selected: selected,
                      playable: playable && !selecting,
                      catalogTitle: catalog ? title : null,
                      showSource: showSource,
                    ),
                    if (!catalog) ...[
                      const SizedBox(height: 8),
                      ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: KalinkaTextStyles.trackRowTitle.copyWith(
                                color: selected
                                    ? KalinkaColors.accentTint
                                    : null,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (showSource || detail.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (showSource) ...[
                                    SourceBadge(
                                      entityId: item.id,
                                      size: SourceBadgeSize.small,
                                    ),
                                    if (detail.isNotEmpty)
                                      const SizedBox(width: 6),
                                  ],
                                  if (detail.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        detail,
                                        style:
                                            KalinkaTextStyles.trackRowSubtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Around Play too, so moving onto it or tabbing to it keeps the card lit.
    Widget highlighted(Widget child) => MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focused = value),
        child: child,
      ),
    );
    return highlighted(card);
  }

  /// A catalog's card when [catalogTitle] is given, else a cover.
  Widget _artwork({
    required String? path,
    required bool round,
    required bool selected,
    required bool playable,
    required String? catalogTitle,
    required bool showSource,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.maxWidth;
      final Widget cover;
      if (catalogTitle != null) {
        cover = CatalogCard(
          artPath: path,
          aspectRatio: item.image?.aspectRatio,
          title: catalogTitle,
          description: item.description,
          subtitle: item.description,
          leading: showSource
              ? (_) =>
                    SourceBadge(entityId: item.id, size: SourceBadgeSize.small)
              : null,
          minScale: 0.8,
          maxLines: 2,
        );
      } else {
        final fallback = ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: ProceduralAlbumArt(trackId: item.id, size: size),
          ),
        );
        cover = AspectRatio(
          aspectRatio: 1,
          child: path == null
              ? fallback
              : Image.network(
                  ref.read(urlResolverProvider).abs(path),
                  width: size,
                  height: size,
                  cacheWidth: (size * 2.5).round(),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => fallback,
                ),
        );
      }
      final mouse = RendererBinding.instance.mouseTracker;
      return Stack(
        children: [
          ExcludeSemantics(
            child: round
                ? ClipOval(child: cover)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: cover,
                  ),
          ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: KalinkaColors.accent.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 32),
              ),
            ),
          if (playable)
            Positioned(
              right: 2,
              bottom: 2,
              child: ListenableBuilder(
                listenable: mouse,
                builder: (context, child) {
                  final shown =
                      _hovered ||
                      _focused ||
                      _pressed ||
                      !mouse.mouseIsConnected;
                  return IgnorePointer(
                    ignoring: !shown,
                    child: AnimatedOpacity(
                      opacity: shown ? 1 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      child: child,
                    ),
                  );
                },
                child: RowPlayButton(item: item),
              ),
            ),
        ],
      );
    },
  );
}
