import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/source_modules_provider.dart';
import '../theme/app_theme.dart';
import 'module_artwork.dart';

enum SourceBadgeSize { standard, small }

/// A listing whose source is already named by its page heading. Null keeps
/// attribution on every item of a mixed-source listing.
class SourceAttributionScope extends InheritedWidget {
  final String? source;

  const SourceAttributionScope({
    super.key,
    required this.source,
    required super.child,
  });

  static String? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SourceAttributionScope>()
      ?.source;

  @override
  bool updateShouldNotify(SourceAttributionScope oldWidget) =>
      source != oldWidget.source;
}

/// Whether a [SourceBadge] for [entityId] renders anything — false for a
/// single source, an unparseable id, or a source the server provides itself.
/// Callers gate the badge's trailing spacer on this so no gap is left when
/// it's hidden.
bool sourceBadgeVisible(WidgetRef ref, String entityId) {
  if (ref.watch(sourceCountProvider) <= 1) return false;
  final source = sourceOfId(entityId);
  if (source == null) return false;
  if (SourceAttributionScope.of(ref.context) == source) return false;
  final info = ref.watch(sourceDisplayInfoProvider)[source];
  return info != null && !info.builtin;
}

/// Displays source artwork or its fallback icon without surrounding chrome.
/// Sources without an icon use their initial in a coloured pill.
///
/// Automatically hides when only one source is configured — with nothing to
/// tell apart, a badge is noise.
///
/// Icons use 20dp in list rows and now-playing, 18dp in queues and tiles.
/// Letter fallbacks retain their compact pill padding.
class SourceBadge extends ConsumerWidget {
  final String entityId;
  final SourceBadgeSize size;

  /// Optional border-radius override for collapsed multi-badge groups.
  final BorderRadius? borderRadiusOverride;

  const SourceBadge({
    super.key,
    required this.entityId,
    this.size = SourceBadgeSize.standard,
    this.borderRadiusOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sourceBadgeVisible(ref, entityId)) return const SizedBox.shrink();

    final source = EntityId.fromString(entityId).source;
    final info = ref.watch(sourceDisplayInfoProvider)[source]!;

    final color = info.color;
    final hasIcon = info.icons != null || info.icon != null;

    final double fs = size == SourceBadgeSize.small ? 10.0 : 11.0;
    final double iconSize = size == SourceBadgeSize.small ? 18.0 : 20.0;
    final double px = size == SourceBadgeSize.small ? 4.0 : 5.0;
    final double py = size == SourceBadgeSize.small ? 1.5 : 2.0;
    final BorderRadius radius =
        borderRadiusOverride ?? BorderRadius.circular(4);

    return Semantics(
      label: info.title,
      excludeSemantics: true,
      child: Container(
        padding: hasIcon
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: px, vertical: py),
        decoration: hasIcon
            ? null
            : BoxDecoration(
                color: color.withValues(alpha: 0.14),
                border: Border.all(
                  color: color.withValues(alpha: 0.30),
                  width: 1,
                ),
                borderRadius: radius,
              ),
        child: ModuleArtwork(
          icons: info.icons,
          small: true,
          size: MediaQuery.textScalerOf(context).scale(iconSize),
          fallback: _SourceMark(
            icon: info.icon,
            letter: info.abbreviation,
            letterSize: fs,
            iconSize: iconSize,
            color: hasIcon ? Theme.of(context).colorScheme.onSurface : color,
          ),
        ),
      ),
    );
  }
}

/// The tile that stands for a source where a results group, a filter pill or
/// a collection drawn from several names the sources it holds: its icon, or
/// its letter where it declares none.
class SourceTile extends ConsumerWidget {
  final String source;

  /// Side of the tile. Smaller where the letters sit on a row's second line
  /// rather than beside a heading.
  final double size;

  const SourceTile({super.key, required this.source, this.size = 22});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(sourceDisplayInfoProvider)[source];
    final color = info?.color ?? colorForSourceName(source);
    final hasIcon = info?.icons != null || info?.icon != null;
    final icon = info?.icons?.standard;
    final height = math.max(size, icon?.minHeight ?? 0);
    final width = math.max(
      size,
      (icon?.minHeight ?? 0) * (icon?.aspectRatio ?? 1),
    );
    final letter =
        info?.abbreviation ?? (source.isEmpty ? '?' : source[0].toUpperCase());
    return Semantics(
      label: info?.title ?? source,
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: hasIcon
            ? null
            : BoxDecoration(
                color: color.withValues(alpha: 0.14),
                border: Border.all(
                  color: color.withValues(alpha: 0.30),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(5),
              ),
        child: ModuleArtwork(
          icons: info?.icons,
          size: size,
          fallback: _SourceMark(
            icon: info?.icon,
            letter: letter,
            letterSize: size / 2,
            iconSize: size,
            color: hasIcon ? Theme.of(context).colorScheme.onSurface : color,
          ),
        ),
      ),
    );
  }
}

class _SourceMark extends StatelessWidget {
  final IconData? icon;
  final String letter;
  final double letterSize;
  final double iconSize;
  final Color color;

  const _SourceMark({
    required this.icon,
    required this.letter,
    required this.letterSize,
    required this.iconSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    // Scaled with the text, or a larger text size leaves it behind the letters.
    if (icon != null) {
      return Icon(icon, size: iconSize, color: color, applyTextScaling: true);
    }
    return Text(
      letter,
      style: KalinkaTextStyles.sourceBadgeLetter.copyWith(
        fontSize: letterSize,
        color: color,
      ),
    );
  }
}
