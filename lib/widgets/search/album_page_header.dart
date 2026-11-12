import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../../utils/browse_links.dart';
import '../../utils/web_build_target.dart';
import '../browse_metadata_link.dart';
import '../fitted_title.dart';
import '../measure_size.dart';
import '../kalinka_back_button.dart';
import '../server_chip.dart';
import '../procedural_album_art.dart';
import '../search_cards/action_pill_button.dart';
import '../search_cards/track_row_support.dart';
import '../source_badge.dart';
import 'track_group_actions.dart';

/// A pane narrower than this stacks an album's cover over its tracks; from
/// here a fixed identity header sits over the cover and track columns.
const double kAlbumSideLayoutWidth = 528;

/// The artist an album page can open: only one its listing named by a full
/// id, so the link keeps the album's source and never looks a name up.
BrowseItem? albumArtistLink(CatalogPage page) =>
    artistBrowseLink(page.item?.album?.artist);

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
    return BrowseMetadataLink(
      label: name,
      style: style,
      item: albumArtistLink(page),
      onOpen: ref.read(searchSessionProvider.notifier).openBrowseItem,
    );
  }
}

/// The album's source, said once for the page.
class _SourceLine extends ConsumerWidget {
  final CatalogPage page;

  final bool compact;

  const _SourceLine({required this.page, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = page.provider?.trim() ?? '';
    if (provider.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SourceBadge(
          entityId: page.id!,
          size: compact ? SourceBadgeSize.small : SourceBadgeSize.standard,
        ),
        if (sourceBadgeVisible(ref, page.id!)) const SizedBox(width: 7),
        Flexible(
          child: Text(
            provider,
            style: KalinkaTextStyles.trackRowSubtitle.copyWith(
              fontSize: compact ? 12 : 14,
            ),
            maxLines: compact ? null : 1,
            overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Album details wrap as complete groups instead of being hidden sideways.
/// The same content can head the tracks on very short, enlarged-text panes.
class WideAlbumMetadata extends ConsumerWidget {
  final CatalogPage page;
  final int? year;
  final int? trackCount;
  final int? totalDurationSeconds;
  final bool compact;

  const WideAlbumMetadata({
    super.key,
    required this.page,
    this.year,
    this.trackCount,
    this.totalDurationSeconds,
    this.compact = false,
  });

  String get _artist => page.description?.trim() ?? '';
  String get _provider => page.provider?.trim() ?? '';
  String get _extent => _summary(
    year,
    trackCount,
    totalDurationSeconds ?? page.totalDurationSeconds,
  );
  bool get isEmpty => _artist.isEmpty && _provider.isEmpty && _extent.isEmpty;

  TextStyle get _style => KalinkaFonts.sans(
    fontSize: compact ? 12 : 14,
    height: 1.3,
    color: KalinkaColors.textSecondary,
  );

  /// Natural line width used to decide whether details fit under the title
  /// or need the full row below the navigation and playback controls.
  double lineWidth(BuildContext context, WidgetRef ref) {
    final widths = <double>[
      if (_artist.isNotEmpty)
        _albumTextWidth(context, _artist, _style) +
            (albumArtistLink(page) == null
                ? 0
                : BrowseMetadataLink.chevronWidth),
      if (_provider.isNotEmpty)
        _albumTextWidth(
              context,
              _provider,
              KalinkaTextStyles.trackRowSubtitle.copyWith(fontSize: 12),
            ) +
            (sourceBadgeVisible(ref, page.id!)
                ? MediaQuery.textScalerOf(context).scale(14) + 17
                : 0),
      if (_extent.isNotEmpty) _albumTextWidth(context, _extent, _style),
    ];
    return widths.fold(0.0, (sum, width) => sum + width) +
        math.max(0, widths.length - 1) * 12;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: 12,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (_artist.isNotEmpty)
        BrowseMetadataLink(
          label: _artist,
          style: _style.copyWith(color: KalinkaColors.textPrimary),
          item: albumArtistLink(page),
          onOpen: ref.read(searchSessionProvider.notifier).openBrowseItem,
        ),
      if (_provider.isNotEmpty) _SourceLine(page: page, compact: true),
      if (_extent.isNotEmpty) Text(_extent, style: _style),
    ],
  );
}

double _albumTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

/// A transparent, fixed header. Both playback actions show labels when they
/// fit alongside a readable title, and both use accessible icons otherwise.
class WideAlbumHeader extends ConsumerWidget {
  final CatalogPage page;
  final WideAlbumMetadata metadata;
  final bool metadataInTracks;
  final int? trackCount;
  final bool shortPane;
  final VoidCallback onBack;
  final VoidCallback? onServerTap;

  const WideAlbumHeader({
    super.key,
    required this.page,
    required this.metadata,
    required this.onBack,
    this.onServerTap,
    this.trackCount,
    this.shortPane = false,
    this.metadataInTracks = false,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: LayoutBuilder(
          builder: (context, space) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final titleStyle = KalinkaFonts.display(
              fontSize: shortPane
                  ? 20
                  : space.maxWidth >= 1100
                  ? 34
                  : 28,
              height: 1.15,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w500,
              color: KalinkaColors.frost,
            );
            // Back, gaps, and connection status keep their normal targets.
            const fixedWidth = 48 + 12 + 16 + 8 + 42;
            final labelledActions =
                ActionPillButton.widthOf(context, 'Play all') +
                ActionPillButton.widthOf(context, 'Enqueue');
            final availableTitle =
                space.maxWidth - fixedWidth - labelledActions;
            // Most wide panes can reserve the title's full minimum without
            // shaping it a second time solely to choose the action labels.
            final iconActions =
                availableTitle < 220 * scale &&
                availableTitle <
                    _albumTextWidth(context, page.title ?? '', titleStyle);
            final titleWidth =
                space.maxWidth -
                fixedWidth -
                (iconActions ? 2 * kKalinkaPillTarget : labelledActions);
            final inlineMetadata =
                !metadataInTracks &&
                metadata.lineWidth(context, ref) <= titleWidth;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    KalinkaBackButton(onPressed: onBack),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: page.title ?? '',
                            child: Semantics(
                              header: true,
                              child: Text(
                                page.title ?? '',
                                key: const ValueKey('album-bar-title'),
                                style: titleStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (inlineMetadata && !metadata.isEmpty) ...[
                            const SizedBox(height: 4),
                            metadata,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    PlayAllChip(
                      trackIds: [page.id!],
                      trackCount: trackCount,
                      enabled: trackCount != 0,
                      iconOnly: iconActions,
                    ),
                    const SizedBox(width: 8),
                    AddAllChip(
                      trackIds: [page.id!],
                      trackCount: trackCount,
                      name: page.title ?? '',
                      enabled: trackCount != 0,
                      iconOnly: iconActions,
                    ),
                    SizedBox(
                      width: 42,
                      height: 48,
                      child: Center(
                        child: ServerChip(compact: true, onTap: onServerTap),
                      ),
                    ),
                  ],
                ),
                if (!metadataInTracks && !inlineMetadata && !metadata.isEmpty)
                  Padding(
                    key: const ValueKey('album-metadata-full-row'),
                    padding: const EdgeInsets.only(left: 60, top: 4),
                    child: metadata,
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

String _summary(int? year, int? trackCount, int? duration) => [
  if (year != null) '$year',
  if (trackCount != null) '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
  if (duration != null && duration > 0) formatTotalDuration(duration),
].join(' · ');

/// How far up from an album header's foot its title ends, and its text's
/// shade starts.
typedef AlbumHeaderInsets = ({double title, double shade});

/// The cover is the album's backdrop. Its shade follows the text block, so
/// even long titles and enlarged system text stay on a dark enough surface.
class AlbumPageHeader extends StatefulWidget {
  final CatalogPage page;
  final int? year;
  final int? trackCount;
  final int? totalDurationSeconds;

  /// Home paints the cover behind its navigation and system status inset.
  /// Standalone uses can keep the same cover inside this header.
  final bool showArtwork;

  /// Where the title and the shade are, so Home's bar can match the shade
  /// where they meet and take the title over once it has scrolled away.
  final ValueChanged<AlbumHeaderInsets>? onInsets;

  const AlbumPageHeader({
    super.key,
    required this.page,
    this.year,
    this.trackCount,
    this.totalDurationSeconds,
    this.showArtwork = true,
    this.onInsets,
  });

  /// The clear-to-shaded lead-in above the text, and how dark the shade is
  /// where the text starts; it deepens to the canvas at the header's foot.
  static const leadIn = 64.0;
  static const shadeAlpha = 0.76;

  /// How dark the header's shade is [fromFoot] up from its foot.
  static double shadeAt(double fromFoot, AlbumHeaderInsets insets) {
    final text = insets.shade;
    final alpha = fromFoot <= text
        ? 1 - (1 - shadeAlpha) * fromFoot / math.max(text, 1)
        : shadeAlpha * (1 - (fromFoot - text) / leadIn);
    return alpha.clamp(0.0, 1.0);
  }

  @override
  State<AlbumPageHeader> createState() => _AlbumPageHeaderState();
}

class _AlbumPageHeaderState extends State<AlbumPageHeader> {
  static const _bottomPadding = 20.0;

  double? _titleInset;
  double? _shadeInset;

  void _report({double? title, double? shade}) {
    _titleInset = title ?? _titleInset;
    _shadeInset = shade ?? _shadeInset;
    if ((_titleInset, _shadeInset) case (final title?, final shade?)) {
      widget.onInsets?.call((title: title, shade: shade));
    }
  }

  /// [child], its height told to [onHeight] where the header reports.
  Widget _measure(ValueChanged<double> onHeight, Widget child) =>
      widget.onInsets == null
      ? child
      : MeasureSize(onChange: (size) => onHeight(size.height), child: child);

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final trackCount = widget.trackCount;
    final showArtwork = widget.showArtwork;
    final title = page.title ?? '';
    final artist = page.description?.trim() ?? '';
    final summary = _summary(
      widget.year,
      trackCount,
      widget.totalDurationSeconds ?? page.totalDurationSeconds,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // A compact cover leaves more tracks visible. This is a minimum so
        // enlarged system text can still grow the header without clipping.
        final heroHeight = width.clamp(320.0, 440.0);
        final titleSize = (width * 0.085).clamp(30.0, 44.0);
        final shade = KalinkaColors.background.withValues(
          alpha: AlbumPageHeader.shadeAlpha,
        );
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
                    height: AlbumPageHeader.leadIn,
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
                  _measure(
                    (height) => _report(shade: height),
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
                              minFontSize: 20,
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
                          _measure(
                            (height) => _report(title: height + _bottomPadding),
                            details,
                          ),
                        ],
                      ),
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
    cacheWidth: wasmSafeCacheSize(_decodeSize),
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => widget.fallback,
  );
}

/// Home's album cover spans the Android system inset, the pinned breadcrumb,
/// and the measured introduction, with the bar's controls straight over it.
/// It stays put while the page scrolls up over it, hidden from the header's
/// foot down and fading as it goes.
class AlbumPageBackdrop extends StatelessWidget {
  final CatalogPage page;
  final ValueListenable<double> headerHeight;
  final ValueListenable<double> scrollOffset;

  final Key artworkKey;

  const AlbumPageBackdrop({
    super.key,
    required this.page,
    required this.headerHeight,
    required this.scrollOffset,
    this.artworkKey = const ValueKey('album-backdrop'),
  });

  @override
  Widget build(BuildContext context) {
    final chromeHeight =
        MediaQuery.paddingOf(context).top + kKalinkaTopBarHeight;
    return IgnorePointer(
      child: ListenableBuilder(
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
