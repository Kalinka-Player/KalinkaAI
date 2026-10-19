import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/artist_relations_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../procedural_album_art.dart';
import '../source_badge.dart';

/// Who an artist page is about: the portrait (or its stand-in), the name,
/// where the artist comes from, and how many releases the source counts.
class ArtistPageHeader extends ConsumerWidget {
  final CatalogPage page;

  const ArtistPageHeader({super.key, required this.page});

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.maxWidth * 0.28).clamp(96.0, 168.0);
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
                            cacheWidth: (size * 3).round(),
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
                    Semantics(
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
                      ),
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

  /// Sits at the row's far end — the listing's Grid/List control.
  final Widget? trailing;

  const ArtistRelationTabs({
    super.key,
    required this.relations,
    required this.shown,
    required this.onShow,
    this.trailing,
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
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
