import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/artist_relations_provider.dart';
import '../../providers/listing_presentation_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/web_build_target.dart';
import '../browse_filters/presentation_toggle.dart';
import '../favorite_toggle.dart';
import '../home/catalog_pin_button.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';
import 'page_favorite_button.dart';

/// Who an artist page is about: the portrait (or its stand-in), the name,
/// where the artist comes from, and how many releases the source counts.
class ArtistPageHeader extends ConsumerWidget {
  final CatalogPage page;

  /// The releases' Grid/List, at the far end level with the portrait's
  /// foot; one switching button where the pane is narrow.
  final ListingLayout? presentation;

  /// On the Pin and the heart beside the name, so the page can tell when
  /// they have scrolled under the bar.
  final Key? actionsKey;

  const ArtistPageHeader({
    super.key,
    required this.page,
    this.presentation,
    this.actionsKey,
  });

  /// The least a name keeps beside Pin and the heart, before text scaling.
  static const _nameRoom = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = page.title ?? '';
    final albums = page.item?.artist?.albumCount;
    final path =
        imagePathOf(page.item?.image) ??
        page.artPath ??
        ref.watch(artistPortraitProvider(page.id!)).value;
    final url = path == null ? null : ref.read(urlResolverProvider).abs(path);
    final provider = page.provider?.trim() ?? '';
    final pin = !ref
        .watch(builtinSourcesProvider)
        .contains(sourceOfId(page.id!));
    final favorable = watchCanFavorite(ref, page.id!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.maxWidth * 0.28).clamp(96.0, 168.0);
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final stand = ProceduralAlbumArt(trackId: page.id!, size: size);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Row(
            children: [
              ExcludeSemantics(
                child: ClipOval(
                  child: SizedBox.square(
                    dimension: size,
                    child: url == null
                        ? stand
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            cacheWidth: wasmSafeCacheSize((size * 3).round()),
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => stand,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ARTIST',
                      style: KalinkaFonts.mono(
                        fontSize: 12,
                        letterSpacing: 2,
                        color: KalinkaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, room) {
                        final title = Semantics(
                          header: true,
                          child: Text(
                            name,
                            style: KalinkaFonts.display(
                              fontSize: 30,
                              height: 1.15,
                              letterSpacing: -0.5,
                              fontWeight: FontWeight.w500,
                              color: KalinkaColors.frost,
                            ),
                            // Pin follows the longest line.
                            textWidthBasis: TextWidthBasis.longestLine,
                          ),
                        );
                        final actions = Row(
                          key: actionsKey,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pin)
                              CatalogPinButton(
                                page: page,
                                filter: const BrowseFilterQuery(),
                              ),
                            if (favorable) PageFavoriteButton(id: page.id!),
                          ],
                        );
                        // Together they would leave a phone's name a few
                        // letters a line, so there they go under it, their
                        // first glyph at its edge.
                        if (pin &&
                            favorable &&
                            room.maxWidth - 8 - 2 * PageFavoriteButton.size <
                                _nameRoom * scale) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              Transform.translate(
                                offset: const Offset(
                                  (CatalogPinButton.iconSize -
                                          PageFavoriteButton.size) /
                                      2,
                                  0,
                                ),
                                child: actions,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Flexible(child: title),
                            if (pin || favorable) ...[
                              const SizedBox(width: 8),
                              actions,
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SourceBadge(entityId: page.id!),
                        if (sourceBadgeVisible(ref, page.id!))
                          const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            [
                              if (provider.isNotEmpty) provider,
                              if (albums != null)
                                '$albums ${albums == 1 ? 'album' : 'albums'}',
                            ].join(' · '),
                            style: KalinkaTextStyles.trackRowSubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (presentation case final layout?) ...[
                const SizedBox(width: 12),
                SizedBox(
                  height: size,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    // Its pill, not its target, ends with the portrait.
                    child: Transform.translate(
                      offset: const Offset(
                        0,
                        (kKalinkaPillTarget - kKalinkaPillHeight) / 2,
                      ),
                      child: PresentationToggle(
                        layout: layout,
                        compact: constraints.maxWidth < 600 * scale,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The artist page's relations, when it has more than one. Choosing one
/// changes what the page lists; it adds nothing to Back.
class ArtistRelationTabs extends StatelessWidget {
  final List<ArtistRelation> relations;
  final ArtistRelation shown;
  final ValueChanged<ArtistRelation> onShow;

  const ArtistRelationTabs({
    super.key,
    required this.relations,
    required this.shown,
    required this.onShow,
  });

  static String labelOf(ArtistRelation relation) => switch (relation) {
    ArtistRelation.albums => 'ALBUMS',
    ArtistRelation.tracks => 'TRACKS',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
      child: Row(
        children: [
          for (final relation in relations)
            Semantics(
              selected: relation == shown,
              button: true,
              label: labelOf(relation),
              excludeSemantics: true,
              onTap: () => onShow(relation),
              child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                onTap: () => onShow(relation),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: relation == shown
                              ? KalinkaColors.textPrimary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      labelOf(relation),
                      style: KalinkaTextStyles.sectionLabel.copyWith(
                        color: relation == shown
                            ? KalinkaColors.textPrimary
                            : KalinkaColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
