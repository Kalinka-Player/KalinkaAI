import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Legacy ownership hint retained for callers; dialogs now center in the window.
enum KalinkaDialogSide {
  /// Playback and queue callers.
  player,

  /// Home, browsing and management callers.
  browsing,

  /// Screens with no split layout, such as onboarding.
  full,
}

/// The app's dialog surface: a card over its own scrim.
/// Settings, forms and confirmations are always centered in the whole window,
/// with a dimmed background and no beak. Content survives resizing.
///
/// The content shape is fixed — optional icon tile, title, optional message,
/// optional [content] slot, and a row of [actions] — so every dialog in the
/// app reads the same; [iconBeside] only turns the tile, title and message
/// into one row. Show it with [showKalinkaDialog].
class KalinkaDialog extends StatefulWidget {
  /// Retained for caller compatibility; placement is always window-centered.
  final KalinkaDialogSide side;

  /// Retained for caller compatibility; all dialogs now use centered placement.
  final bool centered;

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

  /// Sets the icon tile at the start of the title and message, which read
  /// in a column beside it: for a dialog about one thing, named and
  /// described, rather than a question.
  final bool iconBeside;

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
    this.centered = true,
    this.icon,
    this.iconColor = KalinkaColors.accent,
    this.iconGlyphColor,
    this.message,
    this.iconBeside = false,
    this.content,
    this.actions = const [],
  });

  /// Card width cap — without it the card would grow to a 600px-wide
  /// confirmation on a tablet panel, wider still on desktop.
  static const double _maxCardWidth = 460;

  /// Gap between the card and the window edges on narrow windows.
  static const double _cardMargin = 20;

  /// Marks the card itself, so placement tests can measure where it landed.
  @visibleForTesting
  static const cardKey = Key('kalinka_dialog_card');

  @override
  State<KalinkaDialog> createState() => _KalinkaDialogState();
}

class _KalinkaDialogState extends State<KalinkaDialog> {
  final _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: ColoredBox(
          key: const ValueKey('kalinka-dialog-scrim'),
          color: Colors.black.withValues(alpha: 0.60),
        ),
      ),
      _buildCard(context),
    ],
  );

  Widget _buildCard(BuildContext context) {
    final card = Container(
      key: KalinkaDialog.cardKey,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceDialog,
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
      child: _buildContents(),
    );

    final cardContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KalinkaDialog._cardMargin,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: KalinkaDialog._maxCardWidth,
        ),
        // Absorb taps on the card so they don't reach the scrim.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: card,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(
          vertical: KalinkaDialog._cardMargin,
        ),
        child: Center(child: SingleChildScrollView(child: cardContent)),
      ),
    );
  }

  Widget _buildContents() => KeyedSubtree(
    key: _bodyKey,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.iconBeside)
          _buildHeadingBeside()
        else ...[
          if (widget.icon != null) ...[
            _buildIconTile(),
            const SizedBox(height: 14),
          ],
          Text(
            widget.title,
            style: KalinkaTextStyles.dialogTitle,
            textAlign: TextAlign.center,
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.message!,
              style: KalinkaTextStyles.dialogBody,
              textAlign: TextAlign.center,
            ),
          ],
        ],
        if (widget.content != null) ...[
          const SizedBox(height: 16),
          widget.content!,
        ],
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            spacing: 10,
            children: [
              for (final action in widget.actions) Expanded(child: action),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _buildHeadingBeside() => Row(
    children: [
      if (widget.icon != null) ...[_buildIconTile(), const SizedBox(width: 16)],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: KalinkaTextStyles.dialogTitle),
            if (widget.message != null) ...[
              const SizedBox(height: 4),
              Text(widget.message!, style: KalinkaTextStyles.dialogBody),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _buildIconTile() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: widget.iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.iconColor.withValues(alpha: 0.2)),
      ),
      child: Icon(
        widget.icon,
        size: 24,
        color: widget.iconGlyphColor ?? widget.iconColor,
      ),
    );
  }
}

/// Shows a [KalinkaDialog] with the app's standard fade-in.
///
/// The route barrier stays transparent — [KalinkaDialog] paints its own scrim
/// across the whole window — and blocks input to the app behind.
Future<T?> showKalinkaDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => Material(
      type: MaterialType.transparency,
      child: Builder(builder: builder),
    ),
  );
}
