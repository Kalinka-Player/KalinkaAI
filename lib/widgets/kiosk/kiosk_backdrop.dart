import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Full-bleed wash of the cover's colours behind the display.
///
/// The cover is decoded a few pixels wide and stretched with cubic filtering:
/// the upscale is the blur. An ImageFilter would be re-run on every composited
/// frame, which a streamer's GPU pays for while the music plays.
class KioskBackdrop extends StatelessWidget {
  /// A small rendition of the cover — only its colours survive.
  final String? imageUrl;

  const KioskBackdrop({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: KalinkaColors.background),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 1400),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: url == null
                ? const _Bloom(key: ValueKey('bloom'))
                : Opacity(
                    key: ValueKey(url),
                    opacity: 0.55,
                    child: Transform.scale(
                      // Pushes the cover's hard edges off-screen.
                      scale: 1.35,
                      child: Image.network(
                        url,
                        cacheWidth: 24,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const _Bloom(),
                      ),
                    ),
                  ),
          ),
          // An even dark layer: text reads the same wherever it sits, and
          // the cover's colour still shows through. Deeper at the edges
          // that carry the status strip and the progress bar.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3080808),
                  Color(0x8C080808),
                  Color(0x8C080808),
                  Color(0xD9080808),
                ],
                stops: [0.0, 0.2, 0.7, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// No cover: the berry bloom the Discover page wears.
class _Bloom extends StatelessWidget {
  const _Bloom({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.8, -0.9),
          radius: 1.2,
          colors: [
            KalinkaColors.accent.withValues(alpha: 0.22),
            KalinkaColors.accent.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
