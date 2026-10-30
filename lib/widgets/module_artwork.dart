import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/module_icons.dart';
import '../providers/module_icon_cache.dart';
import '../providers/url_resolver.dart';

/// Plugin artwork painted as a shared bitmap, with its older icon as fallback.
class ModuleArtwork extends ConsumerWidget {
  final ModuleIcons? icons;
  final double size;
  final bool small;
  final Widget fallback;

  const ModuleArtwork({
    super.key,
    required this.icons,
    required this.size,
    required this.fallback,
    this.small = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = icons;
    if (artwork == null) return fallback;
    final icon = small ? artwork.small : artwork.standard;
    final url = ref.watch(urlResolverProvider).abs(icon.url);
    final width = small ? size * icon.aspectRatio : size;
    return SizedBox(
      width: width,
      height: size,
      child: FutureBuilder(
        future: ref
            .watch(moduleIconCacheProvider)
            .load(url, icon, small: small),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData) {
            return Center(child: fallback);
          }
          return Image.memory(
            snapshot.requireData,
            width: width,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            color: artwork.monochrome
                ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black)
                : null,
            colorBlendMode: BlendMode.srcIn,
            errorBuilder: (_, _, _) => Center(child: fallback),
            frameBuilder: (_, child, frame, _) =>
                frame == null ? Center(child: fallback) : child,
          );
        },
      ),
    );
  }
}
