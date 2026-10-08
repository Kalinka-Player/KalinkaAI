import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Which panel of the tablet layout a dialog belongs to.
enum KalinkaDialogSide {
  /// Left panel — Now Playing and the Settings overlay, so settings
  /// confirmations (restart, upgrade) belong here.
  left,

  /// Right panel — the queue and the search session, so queue confirmations
  /// (clear all) belong here.
  right,

  /// Screens with no split layout, such as onboarding: the dialog owns the
  /// whole window at every width.
  full,
}

/// The app's dialog surface: a bottom-anchored card over its own scrim.
///
/// Below [kKalinkaTabletBreakpoint] the dialog owns the window. At or above
/// it, card *and* scrim confine themselves to the [side] panel, so a queue
/// confirmation sits over the queue and a settings confirmation over
/// settings instead of stretching across both. The other panel stays
/// undimmed but inert — tapping it dismisses. That choice is re-made from
/// layout constraints on every build, so a window resized across the
/// breakpoint while the dialog is open re-homes the card.
///
/// The content shape is fixed — optional icon tile, title, optional message,
/// optional [content] slot, and a row of [actions] — so every dialog in the
/// app reads the same. Show it with [showKalinkaDialog].
class KalinkaDialog extends StatelessWidget {
  /// Panel the dialog belongs to once the layout splits.
  final KalinkaDialogSide side;

  /// Glyph for the tinted tile above the title. Without it the card starts at
  /// the title.
  final IconData? icon;

  /// Tint the icon tile is built from — background at 12%, border at 20%.
  /// Defaults to the accent berry; pass [KalinkaColors.actionDelete] for
  /// destructive dialogs.
  final Color iconColor;

  /// Glyph colour, for tints that aren't legible on their own tinted surface
  /// (accent tiles take [KalinkaColors.accentTint]). Defaults to [iconColor].
  final Color? iconGlyphColor;

  final String title;

  /// Explanatory line under the title.
  final String? message;

  /// Body content under the message, for dialogs that show more than text
  /// (e.g. the speaker test's channel indicators).
  final Widget? content;

  /// Buttons along the bottom, laid out edge to edge in a single row. Pass
  /// them with `fullWidth: true`.
  final List<Widget> actions;

  const KalinkaDialog({
    super.key,
    required this.side,
    required this.title,
    this.icon,
    this.iconColor = KalinkaColors.accent,
    this.iconGlyphColor,
    this.message,
    this.content,
    this.actions = const [],
  });

  /// Card width cap — without it the card would grow to a 600px-wide
  /// confirmation on a tablet panel, wider still on desktop.
  static const double _maxCardWidth = 460;

  /// Gap between the card and the panel edges on narrow windows.
  static const double _cardMargin = 20;

  /// Marks the card itself, so placement tests can measure where it landed.
  @visibleForTesting
  static const cardKey = Key('kalinka_dialog_card');

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder (not MediaQuery) so the decision comes from the same
    // constraints the layout underneath splits on, and re-runs on resize.
    return LayoutBuilder(
      builder: (context, constraints) {
        final panel = Stack(
          fit: StackFit.expand,
          children: [
            _buildTapToDismiss(context, dimmed: true),
            _buildCard(context),
          ],
        );
        if (side == KalinkaDialogSide.full ||
            constraints.maxWidth < kKalinkaTabletBreakpoint) {
          return panel;
        }
        // The two panels are equal halves, so half the window is the dialog's
        // home.
        final away = Expanded(
          child: _buildTapToDismiss(context, dimmed: false),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: side == KalinkaDialogSide.left
              ? [Expanded(child: panel), away]
              : [away, Expanded(child: panel)],
        );
      },
    );
  }

  /// Everything around the card closes the dialog on tap. [dimmed] paints the
  /// scrim; the panel the dialog isn't in stays clear but still swallows taps,
  /// so the app behind can't be poked while a dialog is up.
  Widget _buildTapToDismiss(BuildContext context, {required bool dimmed}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: dimmed
            ? ColoredBox(color: Colors.black.withValues(alpha: 0.60))
            : const SizedBox.expand(),
      );

  Widget _buildCard(BuildContext context) {
    final card = Container(
      key: cardKey,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: KalinkaColors.borderDefault),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 60,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[_buildIconTile(), const SizedBox(height: 14)],
          Text(
            title,
            style: KalinkaTextStyles.dialogTitle,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: KalinkaTextStyles.dialogBody,
              textAlign: TextAlign.center,
            ),
          ],
          if (content != null) ...[const SizedBox(height: 16), content!],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 22),
            Row(
              spacing: 10,
              children: [for (final action in actions) Expanded(child: action)],
            ),
          ],
        ],
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _slideIn(
          context,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _cardMargin),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxCardWidth),
              // Absorb taps on the card so they don't reach the scrim behind
              // it; the empty space above stays dismiss-on-tap.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: card,
              ),
            ),
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 28),
      ],
    );
  }

  Widget _buildIconTile() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
      ),
      child: Icon(icon, size: 24, color: iconGlyphColor ?? iconColor),
    );
  }

  /// Lifts the card into place on open. Driven off the route animation so
  /// only the card moves: a scrim that slid in with it would leave an
  /// undimmed strip along the top. Outside a route (widget tests) it is a
  /// no-op.
  Widget _slideIn(BuildContext context, Widget child) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.4, 0, 0.2, 1),
            ),
          ),
      child: child,
    );
  }
}

/// Shows a [KalinkaDialog] with the app's standard fade-in.
///
/// The route barrier stays transparent — [KalinkaDialog] paints its own scrim
/// so it can dim a single panel and follow live resizes — and only serves to
/// block input to the app behind.
Future<T?> showKalinkaDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, _) =>
        Material(type: MaterialType.transparency, child: builder(ctx)),
  );
}
