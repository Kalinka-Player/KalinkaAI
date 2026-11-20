import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show OpacityLayer, RenderObjectVisitor, RenderProxyBox, RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/artist_relations_provider.dart' show imagePathOf;
import '../../providers/selection_state_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/web_build_target.dart';
import '../catalog_art.dart';
import '../fitted_art.dart';
import '../modifier_click.dart';
import '../source_badge.dart';
import '../tap_highlight.dart' show kalinkaOverlay;
import 'browse_navigation_scope.dart';
import 'row_play_button.dart';
import 'track_row_support.dart' show ArtStandIn;

/// An artwork grid item: square covers and round artist portraits followed by
/// a name and detail, or a catalog's card with its name on it. The cover and
/// name open its page; Play rests on the cover while the card is lit,
/// and always on a touch screen. Long-press takes a playable item into the
/// selection, as its row would. Under the pointer, held or focused, the whole
/// card is outlined, as the cards of a Home rail are.
class ArtworkGridCard extends ConsumerStatefulWidget {
  final BrowseItem item;

  /// The shape its shelf lays covers out in, width over height. An artist's
  /// portrait stays round, and a catalog's card 3:1.
  final double shape;
  final bool compact;

  /// Between the card's frame and its cover and caption: half the room
  /// between two covers, so frames abut and two outlines side by side meet.
  static const inset = kKalinkaFrameInset;

  const ArtworkGridCard({
    super.key,
    required this.item,
    this.shape = 1,
    this.compact = false,
  });

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
  static const _playShortcut = SingleActivator(
    LogicalKeyboardKey.enter,
    shift: true,
    includeRepeats: false,
  );

  /// Concentric with the cover's corners, a frame's inset out.
  static final _frame = BorderRadius.circular(10 + _inset);

  final _interaction = WidgetStatesController();
  final _playButton = FocusNode(
    debugLabel: 'Grid card Play',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _interaction.dispose();
    _playButton.dispose();
    super.dispose();
  }

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
        hint: playable && !selecting ? 'Shift+Enter to play' : null,
        explicitChildNodes: true,
        onTap: activate,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            excludeFromSemantics: true,
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: activate,
            onLongPress: playable && !selecting ? select : null,
            onHighlightChanged: (value) =>
                _interaction.update(WidgetState.pressed, value),
            overlayColor: kalinkaOverlay,
            borderRadius: _frame,
            child: ValueListenableBuilder<Set<WidgetState>>(
              valueListenable: _interaction,
              builder: (context, states, child) => DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: _frame,
                  border: Border.all(
                    color: states.isNotEmpty
                        ? KalinkaColors.borderDefault
                        : Colors.transparent,
                  ),
                ),
                child: child,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _inset,
                  vertical: widget.compact ? 6 : _inset,
                ),
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
                      SizedBox(height: widget.compact ? 6 : 8),
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
    // One arrow stop per card. The shortcut invokes the same Play button
    // as a click, including its guard against starting playback twice.
    Widget highlighted(Widget child) => MouseRegion(
      onEnter: (_) => _interaction.update(WidgetState.hovered, true),
      onExit: (_) => _interaction.update(WidgetState.hovered, false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) =>
            _interaction.update(WidgetState.focused, value),
        onKeyEvent: (_, event) {
          final play = _playButton.context;
          if (playable &&
              !selecting &&
              play != null &&
              _playShortcut.accepts(event, HardwareKeyboard.instance)) {
            Actions.invoke(play, const ActivateIntent());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
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
          entityId: item.id,
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
            child: ArtStandIn(item: item, size: size),
          ),
        );
        final shape = round ? 1.0 : widget.shape;
        final height = size / shape;
        final ratio = item.image?.aspectRatio;
        final fills = fillsShape(ratio, shape);
        final byHeight = !fills && fitsByHeight(ratio, shape);
        // Decode for this display, not a fixed density. Reuse a size bucket
        // during window resizes instead of downloading and decoding at every
        // intermediate pixel size (ResizeImage's size is part of its key).
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final decode = math.max(
          1,
          (((byHeight ? height : size) * dpr) / 64).ceil() * 64,
        );
        final url = path == null
            ? null
            : ref.read(urlResolverProvider).abs(path);
        final art = url == null
            ? fallback
            : Image.network(
                url,
                width: size,
                height: height,
                cacheWidth: wasmSafeCacheSize(byHeight ? null : decode),
                cacheHeight: wasmSafeCacheSize(byHeight ? decode : null),
                fit: fills ? BoxFit.cover : BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => fallback,
              );
        cover = AspectRatio(
          aspectRatio: shape,
          child: url == null || fills
              ? art
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    SoftImageFill(url: url),
                    art,
                  ],
                ),
        );
      }
      final mouse = RendererBinding.instance.mouseTracker;
      return Stack(
        children: [
          // No RepaintBoundary: a cover is one image draw to re-record, but
          // its own layer costs every scroll frame for every visible card.
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
                listenable: Listenable.merge([_interaction, mouse]),
                builder: (context, child) {
                  final shown =
                      _interaction.value.isNotEmpty || !mouse.mouseIsConnected;
                  return IgnorePointer(
                    ignoring: !shown,
                    // Not Opacity or AnimatedOpacity: both keep a layer of
                    // their own even at 1, one more per card on every
                    // scrolled frame where Play always shows.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: shown ? 1 : 0),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      builder: (context, opacity, child) =>
                          _PlayFade(opacity: opacity, child: child),
                      child: child,
                    ),
                  );
                },
                child: Tooltip(
                  message: 'Play (Shift+Enter)',
                  excludeFromSemantics: true,
                  child: RowPlayButton(item: item, focusNode: _playButton),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Opacity that takes a layer only while partly transparent: fully opaque it
/// paints its child in place, and fully transparent not at all.
class _PlayFade extends SingleChildRenderObjectWidget {
  final double opacity;

  const _PlayFade({required this.opacity, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlayFade(opacity);

  @override
  void updateRenderObject(BuildContext context, _RenderPlayFade renderObject) {
    renderObject.opacity = opacity;
  }
}

class _RenderPlayFade extends RenderProxyBox {
  _RenderPlayFade(double opacity) : _alpha = Color.getAlphaFromOpacity(opacity);

  int _alpha;

  set opacity(double value) {
    final alpha = Color.getAlphaFromOpacity(value);
    if (alpha == _alpha) return;
    final composited = alwaysNeedsCompositing;
    final visible = _alpha != 0;
    _alpha = alpha;
    if (composited != alwaysNeedsCompositing) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
    if (visible != (_alpha != 0)) markNeedsSemanticsUpdate();
  }

  @override
  bool get alwaysNeedsCompositing =>
      child != null && _alpha > 0 && _alpha < 255;

  @override
  bool paintsChild(RenderBox child) => _alpha > 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _alpha == 0) {
      layer = null;
      return;
    }
    if (_alpha == 255) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushOpacity(
      offset,
      _alpha,
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (child != null && _alpha != 0) visitor(child!);
  }
}
