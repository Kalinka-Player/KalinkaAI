import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_session_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../loading_shimmer.dart';

/// The catalog's own artwork and caption, without fetching its children.
class CatalogArtwork extends ConsumerWidget {
  final CatalogPage page;
  final String? description;
  final IconData sourceIcon;
  final Color? sourceColor;
  final VoidCallback? onOpen;

  const CatalogArtwork({
    super.key,
    required this.page,
    this.description,
    this.sourceIcon = Icons.library_music_outlined,
    this.sourceColor,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = page.artPath;
    final url = path == null || path.isEmpty
        ? null
        : ref.watch(urlResolverProvider).abs(path);
    return _ArtworkImage(
      image: url == null ? null : ResizeImage(NetworkImage(url), width: 1024),
      aspectRatio: page.preview?.aspectRatio,
      title: page.title ?? 'Catalog',
      description: description,
      sourceIcon: sourceIcon,
      sourceColor: sourceColor,
      onOpen: onOpen,
    );
  }
}

class _ArtworkImage extends StatefulWidget {
  final ImageProvider? image;
  final double? aspectRatio;
  final String title;
  final String? description;
  final IconData sourceIcon;
  final Color? sourceColor;
  final VoidCallback? onOpen;

  const _ArtworkImage({
    required this.image,
    required this.aspectRatio,
    required this.title,
    required this.description,
    required this.sourceIcon,
    required this.sourceColor,
    required this.onOpen,
  });

  @override
  State<_ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<_ArtworkImage> {
  ImageStream? _stream;
  double? _nativeRatio;
  late final _listener = ImageStreamListener(
    (info, synchronous) {
      final ratio = info.image.width / info.image.height;
      info.dispose();
      if (!mounted || ratio == _nativeRatio) return;
      if (synchronous) {
        _nativeRatio = ratio;
      } else {
        setState(() => _nativeRatio = ratio);
      }
    },
    onError: (Object _, StackTrace? _) {
      // The Image's errorBuilder supplies the visible fallback.
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _nativeRatio = null;
      _resolve();
    }
  }

  void _resolve() {
    final next = widget.image?.resolve(createLocalImageConfiguration(context));
    if (next?.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = next;
    _stream?.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Preview hints describe child items, so the image's own dimensions win
    // once decoded. Generated catalog art is 3:1 when no hint is available.
    final hint = widget.aspectRatio;
    final ratio =
        _nativeRatio ??
        (hint != null && hint.isFinite && hint > 0 ? hint : 3.0);
    const placeholder = Center(
      child: Tooltip(
        message: 'No artwork available',
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 32,
          color: KalinkaColors.textMuted,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 320 * ratio);
        // Scale the caption with the rendered card, including its height cap.
        // Keep the caption's base sizes on narrow cards.
        final captionScale = math.max(1.0, width / 400);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: Semantics(
              button: true,
              enabled: widget.onOpen != null,
              label: widget.onOpen == null
                  ? widget.title
                  : 'Open ${widget.title}',
              value: widget.description,
              onTap: widget.onOpen,
              excludeSemantics: true,
              child: Material(
                color: KalinkaColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    AspectRatio(
                      aspectRatio: ratio,
                      child: widget.image == null
                          ? placeholder
                          : Image(
                              image: widget.image!,
                              fit: BoxFit.contain,
                              frameBuilder: (_, child, frame, _) =>
                                  frame == null
                                  ? const ShimmerPulse(child: ShimmerBlock())
                                  : child,
                              errorBuilder: (_, _, _) => placeholder,
                            ),
                    ),
                    // Keeps the caption legible over bright art.
                    if (widget.image != null)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: AlignmentDirectional.centerStart,
                              end: AlignmentDirectional.centerEnd,
                              colors: [
                                KalinkaColors.background.withValues(
                                  alpha: 0.85,
                                ),
                                KalinkaColors.background.withValues(alpha: 0.7),
                                KalinkaColors.background.withValues(alpha: 0),
                              ],
                              // Dense under the caption, which takes about
                              // the first half of the card.
                              stops: const [0, 0.5, 0.9],
                            ),
                          ),
                        ),
                      ),
                    // Both the image and caption contribute to the card's
                    // height, so large text can grow without cropping the art.
                    _caption(captionScale),
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          mouseCursor: WidgetStateMouseCursor.clickable,
                          onTap: widget.onOpen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Lifts the caption off bright spots the scrim leaves showing.
  static const _captionShadows = [
    Shadow(color: Color(0x99000000), blurRadius: 8),
  ];

  Widget _caption(double scale) {
    final textScale = scale * 0.85;
    return Padding(
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.sourceIcon,
                size: 15 * scale,
                color: widget.sourceColor,
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Text(
                  widget.title,
                  style: KalinkaTextStyles.blockTitle.apply(
                    fontSizeFactor: textScale,
                    shadows: _captionShadows,
                  ),
                ),
              ),
            ],
          ),
          if (widget.description != null) ...[
            SizedBox(height: 4 * scale),
            Text(
              widget.description!,
              style: KalinkaTextStyles.trackRowSubtitle.apply(
                fontSizeFactor: textScale,
                shadows: _captionShadows,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
