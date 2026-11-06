import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/module_icons.dart';
import '../providers/module_icon_cache.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart' show KalinkaColors;

/// Plugin artwork painted as a shared bitmap, with its older icon as fallback.
class ModuleArtwork extends ConsumerWidget {
  final ModuleIcons? icons;
  final double size;
  final bool small;
  final Widget fallback;

  /// Match a surrounding button's hover, focus and selected foreground.
  final bool inheritIconColor;

  const ModuleArtwork({
    super.key,
    required this.icons,
    required this.size,
    required this.fallback,
    this.small = false,
    this.inheritIconColor = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = icons;
    if (artwork == null) return fallback;
    final icon = small ? artwork.small : artwork.standard;
    final url = ref.watch(urlResolverProvider).abs(icon.url);
    final cache = ref.watch(moduleIconCacheProvider);
    final height = math.max(size, icon.minHeight);
    final width = small
        ? height * icon.aspectRatio
        : math.max(height, icon.minHeight * icon.aspectRatio);
    return SizedBox(
      width: width,
      height: height,
      child: FutureBuilder(
        key: ValueKey((cache, url, icon.mimeType, small)),
        initialData: cache.peek(url, icon, small: small),
        future: cache.load(url, icon, small: small),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return snapshot.hasError
                ? Center(child: fallback)
                : const SizedBox.shrink();
          }
          return Image.memory(
            snapshot.requireData,
            width: width,
            height: height,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            color: artwork.monochrome
                ? (inheritIconColor ? IconTheme.of(context).color : null) ??
                      KalinkaColors.textSecondary
                : null,
            colorBlendMode: BlendMode.srcIn,
            errorBuilder: (_, _, _) => Center(child: fallback),
            // Keep the declared logo while rebuilding; don't alternate it
            // with a different fallback mark while the bitmap is decoding.
          );
        },
      ),
    );
  }
}
