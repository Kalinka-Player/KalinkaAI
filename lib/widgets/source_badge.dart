import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../providers/source_modules_provider.dart';
import '../theme/app_theme.dart';

enum SourceBadgeSize { standard, small }

/// Whether a [SourceBadge] for [entityId] renders anything — false for a
/// single source, an unparseable id, or a source the server provides itself.
/// Callers gate the badge's trailing spacer on this so no gap is left when
/// it's hidden.
bool sourceBadgeVisible(WidgetRef ref, String entityId) {
  if (ref.watch(sourceCountProvider) <= 1) return false;
  final source = sourceOfId(entityId);
  if (source == null) return false;
  final info = ref.watch(sourceDisplayInfoProvider)[source];
  return info != null && !info.builtin;
}

/// Displays a source attribution badge: a pill holding the source's icon, or
/// the first letter of its name where it declares none, in the source colour.
///
/// Automatically hides when only one source is configured — with nothing to
/// tell apart, a badge is noise.
///
/// [size.standard]: 11dp font, 5dp h-padding, 2dp v-padding (list rows, now-playing)
/// [size.small]:    10dp font, 4dp h-padding, 1.5dp v-padding (queue rows, tiles)
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

    final double fs = size == SourceBadgeSize.small ? 10.0 : 11.0;
    final double px = size == SourceBadgeSize.small ? 4.0 : 5.0;
    final double py = size == SourceBadgeSize.small ? 1.5 : 2.0;
    final BorderRadius radius =
        borderRadiusOverride ?? BorderRadius.circular(4);

    return Semantics(
      label: info.title,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
          borderRadius: radius,
        ),
        // The icon takes the letter's height, so a row of badges lines up.
        child: _SourceMark(
          icon: info.icon,
          letter: info.abbreviation,
          letterSize: fs,
          iconSize: fs,
          color: color,
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
    final letter =
        info?.abbreviation ?? (source.isEmpty ? '?' : source[0].toUpperCase());
    return Semantics(
      label: info?.title ?? source,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
          borderRadius: BorderRadius.circular(5),
        ),
        child: _SourceMark(
          icon: info?.icon,
          letter: letter,
          letterSize: size / 2,
          iconSize: size * 0.6,
          color: color,
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
    if (icon != null) return Icon(icon, size: iconSize, color: color);
    return Text(
      letter,
      style: KalinkaTextStyles.sourceBadgeLetter.copyWith(
        fontSize: letterSize,
        color: color,
      ),
    );
  }
}
