import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// What a settings page holds staged but not yet applied, and the two things
/// to do with it.
///
/// Presentational: the page that owns the staged values supplies the count
/// and the actions, so the same controls serve the server's settings (apply
/// can restart Kalinka) and a renderer's (apply writes its paths).
@immutable
class PendingChanges {
  final int count;

  /// What applying costs, after the count in Apply's tooltip: `restarts
  /// Kalinka`, `playback will stop`. Null when it costs nothing worth saying.
  final String? consequence;

  /// While true both actions are inert and Apply spins.
  final bool busy;

  /// What stands in the way of applying, e.g. `check Service name`. While set
  /// Apply becomes Review where [onReview] is given, else it is out of reach.
  final String? blockedReason;
  final VoidCallback? onReview;
  final VoidCallback onDiscard;
  final VoidCallback onApply;

  const PendingChanges({
    required this.count,
    required this.onDiscard,
    required this.onApply,
    this.consequence,
    this.busy = false,
    this.blockedReason,
    this.onReview,
  });

  bool get blocked => blockedReason != null;
  bool get reviews => blocked && onReview != null;

  String get _changes => '$count change${count == 1 ? '' : 's'}';

  @override
  bool operator ==(Object other) =>
      other is PendingChanges &&
      other.count == count &&
      other.consequence == consequence &&
      other.busy == busy &&
      other.blockedReason == blockedReason &&
      other.onReview == onReview &&
      other.onDiscard == onDiscard &&
      other.onApply == onApply;

  @override
  int get hashCode => Object.hash(
    count,
    consequence,
    busy,
    blockedReason,
    onReview,
    onDiscard,
    onApply,
  );
}

/// Hands a page's [PendingChanges] to every [SettingsTopBar] under it, so
/// Revert and Apply stay in reach on whichever of its pages is open.
class PendingChangesScope extends InheritedWidget {
  final PendingChanges changes;

  const PendingChangesScope({
    super.key,
    required this.changes,
    required super.child,
  });

  /// The nearest scope's changes while any are staged, else null.
  static PendingChanges? of(BuildContext context) {
    final changes = context
        .dependOnInheritedWidgetOfExactType<PendingChangesScope>()
        ?.changes;
    return changes == null || changes.count == 0 ? null : changes;
  }

  @override
  bool updateShouldNotify(PendingChangesScope oldWidget) =>
      changes != oldWidget.changes;
}

/// Revert and Apply, ahead of a settings top bar's other controls.
///
/// They share the bar's round 40dp buttons; Apply is drawn in the amber the
/// staged rows carry, so the pair stands out from the page's own controls.
/// [labelled] adds the names where the bar has room for them — see
/// [labelledWidth].
class PendingChangesActions extends StatelessWidget {
  final PendingChanges changes;
  final bool labelled;

  const PendingChangesActions({
    super.key,
    required this.changes,
    this.labelled = false,
  });

  /// Between the two faces. Round, each sits in a 48dp target whose
  /// padding makes the gap; named, they are wider than that and set it apart.
  static const gap = 8.0;
  static const _revert = 'Revert';

  static const _apply = 'Apply';
  static const _review = 'Review';

  /// How wide the pair sets with their labels, whichever Apply shows: the
  /// pair keeps its names, or its glyphs, as Apply turns into Review.
  static double labelledWidth(BuildContext context) =>
      _PillAction.widthOf(context, _revert) +
      gap +
      math.max(
        _PillAction.widthOf(context, _apply),
        _PillAction.widthOf(context, _review),
      );

  @override
  Widget build(BuildContext context) {
    final busy = changes.busy;
    final applyHint = changes.busy
        ? 'Applying ${changes._changes}'
        : changes.blocked
        ? 'Cannot apply yet, ${changes.blockedReason}'
        : ['Apply ${changes._changes}', ?changes.consequence].join(', ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: labelled ? gap : 0,
      children: [
        _PillAction(
          key: const ValueKey('pending-changes-revert'),
          icon: Icons.undo_rounded,
          label: _revert,
          hint: 'Revert ${changes._changes}',
          labelled: labelled,
          amber: false,
          onPressed: busy ? null : _leavingField(changes.onDiscard),
        ),
        _PillAction(
          key: const ValueKey('pending-changes-apply'),
          icon: changes.reviews
              ? Icons.error_outline_rounded
              : Icons.check_rounded,
          // Busy, the spinner in its glyph's place says so.
          busy: busy,
          label: changes.reviews ? _review : _apply,
          hint: applyHint,
          labelled: labelled,
          amber: true,
          onPressed: busy
              ? null
              : changes.reviews
              ? _leavingField(changes.onReview)
              : changes.blocked
              ? null
              : _leavingField(changes.onApply),
        ),
      ],
    );
  }
}

/// Leaves the field being typed in first, so its text is staged before
/// the action takes the changes and the keyboard goes with it.
VoidCallback? _leavingField(VoidCallback? action) => action == null
    ? null
    : () {
        FocusManager.instance.primaryFocus?.unfocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        action();
      };

/// A round 40dp top-bar button that grows into a pill when [labelled], in a
/// target at least 48dp each way.
class _PillAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool labelled;
  final bool amber;
  final bool busy;
  final VoidCallback? onPressed;

  const _PillAction({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.labelled,
    required this.amber,
    required this.onPressed,
    this.busy = false,
  });

  static const _iconSize = 18.0;
  static const _markSide = 12.0;
  static const _markGap = 6.0;
  static const _side = 16.0;

  static final _labelStyle = KalinkaFonts.sans(
    fontSize: KalinkaTypography.baseSize + 2,
    fontWeight: FontWeight.w600,
  );

  /// The pending surface laid on the bar, so the face is opaque and
  /// `statusPendingLight` sits on the surface it is made for.
  static final _amberFill = Color.alphaBlend(
    KalinkaColors.statusPendingSurface,
    KalinkaColors.surfaceBase,
  );

  /// How wide a labelled [label] sets, as [build] lays it out: the button
  /// sets its label in its own style, not merged into the ambient one.
  static double widthOf(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _markSide + _iconSize + _markGap + width.ceilToDouble() + _side;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // Busy keeps its colour: the spinner says the press was taken.
    final dimmed = !enabled && !busy;
    final fg = amber
        ? KalinkaColors.statusPendingLight
        : KalinkaColors.textPrimary;
    final border = amber
        ? KalinkaColors.statusPending.withValues(alpha: 0.45)
        : KalinkaColors.borderDefault;
    final glyph = busy
        ? SizedBox.square(
            dimension: _iconSize,
            child: Padding(
              padding: const EdgeInsets.all(1.5),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
                // A still ring where animations are off.
                value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
              ),
            ),
          )
        : Icon(icon, size: _iconSize);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size.square(kKalinkaPillHeight),
      ),
      padding: WidgetStatePropertyAll(
        labelled
            ? const EdgeInsets.fromLTRB(_markSide, 0, _side, 0)
            : EdgeInsets.zero,
      ),
      // A 40dp face in a 48dp target, as Back has.
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(_labelStyle),
      backgroundColor: WidgetStatePropertyAll(
        amber ? _amberFill : KalinkaColors.surfaceElevated,
      ),
      foregroundColor: WidgetStatePropertyAll(
        dimmed ? fg.withValues(alpha: 0.4) : fg,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
            : BorderSide(
                color: dimmed ? border.withValues(alpha: 0.15) : border,
              ),
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.any({WidgetState.hovered, WidgetState.pressed}.contains)
            ? amber
                  ? KalinkaColors.statusPending.withValues(alpha: 0.12)
                  : KalinkaColors.surfaceOverlay
            : null,
      ),
    );
    return Tooltip(
      message: hint,
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          label: hint,
          child: TextButton(
            onPressed: onPressed,
            style: style,
            // The hint already names it.
            child: ExcludeSemantics(
              child: labelled
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        glyph,
                        const SizedBox(width: _markGap),
                        Text(label, maxLines: 1, softWrap: false),
                      ],
                    )
                  : glyph,
            ),
          ),
        ),
      ),
    );
  }
}

/// One staged change as the leave dialog lists it: the setting, and where it
/// lives when the name alone would not say ("Enabled" under Qobuz).
@immutable
class PendingChangeItem {
  final String label;
  final String? where;

  const PendingChangeItem(this.label, {this.where});

  @override
  bool operator ==(Object other) =>
      other is PendingChangeItem &&
      other.label == label &&
      other.where == where;

  @override
  int get hashCode => Object.hash(label, where);
}

enum PendingChangesChoice { apply, discard }

/// Asks what becomes of the changes staged on a settings page being left:
/// Apply or Discard, with [items] listed. Null — the scrim, Escape or Back —
/// stays on the page.
Future<PendingChangesChoice?> askAboutPendingChanges(
  BuildContext context, {
  required List<PendingChangeItem> items,
  String? message,
}) => showKalinkaDialog<PendingChangesChoice>(
  context: context,
  builder: (dialog) => KalinkaDialog(
    side: KalinkaDialogSide.browsing,
    icon: Icons.warning_amber_rounded,
    iconColor: KalinkaColors.statusPending,
    iconGlyphColor: KalinkaColors.statusPendingLight,
    title: 'Apply your changes?',
    message: message,
    content: items.isEmpty ? null : _ChangeList(items: items),
    actions: [
      KalinkaButton(
        key: const ValueKey('pending-changes-dialog-discard'),
        label: 'Discard',
        variant: KalinkaButtonVariant.neutral,
        fullWidth: true,
        onTap: () => Navigator.pop(dialog, PendingChangesChoice.discard),
      ),
      KalinkaButton(
        key: const ValueKey('pending-changes-dialog-apply'),
        label: 'Apply',
        fullWidth: true,
        onTap: () => Navigator.pop(dialog, PendingChangesChoice.apply),
      ),
    ],
  ),
);

/// What is staged, one row each, marked with the staged rows' amber dot.
class _ChangeList extends StatelessWidget {
  final List<PendingChangeItem> items;

  const _ChangeList({required this.items});

  /// Past this many the list says how many more rather than scrolling on.
  static const _shown = 6;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(_shown).toList();
    // Several paths can be one row (a collection's entries), so the rest is
    // counted from the rows, not the paths.
    final more = math.max(0, items.length - shown.length);
    final rowStyle = KalinkaTextStyles.dialogBody.copyWith(height: 1.4);
    return Container(
      key: const ValueKey('pending-changes-list'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          for (final item in shown)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // On the first line's centre, however the text scales.
                SizedBox(
                  width: 6,
                  height: MediaQuery.textScalerOf(context)
                      .scale(rowStyle.fontSize! * rowStyle.height!),
                  child: const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: KalinkaColors.statusPending,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (item.where case final where?)
                          TextSpan(
                            text: '$where · ',
                            style: rowStyle.copyWith(
                              color: KalinkaColors.textSecondary,
                            ),
                          ),
                        TextSpan(
                          text: item.label,
                          style: rowStyle.copyWith(
                            color: KalinkaColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'and $more more',
                style: rowStyle.copyWith(color: KalinkaColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
