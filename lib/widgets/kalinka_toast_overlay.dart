import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import 'tap_highlight.dart';

/// Height of the MiniPlayer (not including SafeArea bottom inset).
const double kMiniPlayerHeight = 72.0;

/// Keep both metadata lines readable at the system text size. The shell and
/// queue reserve the same measured height as the bar, excluding safe insets.
double kalinkaMiniPlayerHeight(BuildContext context) {
  var textHeight = 0.0;
  for (final style in [
    KalinkaTextStyles.miniPlayerTitle,
    KalinkaTextStyles.miniPlayerArtist,
  ]) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    textHeight += painter.height;
    painter.dispose();
  }
  return (textHeight + 28).clamp(kMiniPlayerHeight, double.infinity);
}

/// Which toasts an overlay is responsible for. The tablet layout mounts two —
/// one per half — so an answer appears where its question was asked; the phone
/// mounts one that takes everything.
enum ToastScope {
  /// Every toast (phone).
  all,

  /// Only toasts not raised inside a panel (tablet, over browsing).
  window,

  /// Only toasts raised inside a panel (tablet, over the player's pane).
  panel,
}

/// Overlay that renders themed toast notifications above the bottom dock.
///
/// On phone: toasts stack upward from just above the bottom bar, cleared by
/// [bottomOffset] (the height of whatever docks at the bottom — the mini
/// player + search pill on the main screen, or the composer on the search
/// screen). On tablet (isTablet: true): toasts appear at bottom-right of
/// whichever half [scope] assigns them to.
///
/// Taps go through to whatever is under a toast, except on a toast with an
/// action: its card takes them.
class KalinkaToastOverlay extends ConsumerWidget {
  final bool isTablet;

  /// Space to leave below the toasts on phone so they clear the bottom dock.
  final double bottomOffset;

  /// Which toasts this overlay draws; see [ToastScope].
  final ToastScope scope;

  const KalinkaToastOverlay({
    super.key,
    this.isTablet = false,
    this.bottomOffset = kMiniPlayerHeight,
    this.scope = ToastScope.all,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastProvider).where(_mine).toList();
    if (toasts.isEmpty) return const SizedBox.shrink();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bottomPadding = isTablet ? 0.0 : bottomOffset + bottomInset + 8.0;
    // A leaving toast's action is gone already, so a second tap can't rerun it.
    Widget card(ToastEntry toast) => IgnorePointer(
      ignoring: toast.action == null || toast.dismissing,
      child: _ToastCard(
        entry: toast,
        onDismiss: () => ref.read(toastProvider.notifier).dismiss(toast.id),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isTablet
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.stretch,
      children: [
        for (final toast in toasts.reversed)
          Padding(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 0 : 16,
              0,
              isTablet ? 0 : 16,
              4,
            ),
            // Compact toasts sit as a right-aligned pill; others stretch.
            child: toast.compact && !isTablet
                ? Align(alignment: Alignment.centerRight, child: card(toast))
                : card(toast),
          ),
        SizedBox(height: bottomPadding),
      ],
    );
  }

  bool _mine(ToastEntry entry) => switch (scope) {
    ToastScope.all => true,
    ToastScope.window => !entry.inPanel,
    ToastScope.panel => entry.inPanel,
  };
}

/// Paints window-scoped toasts over [child], which is the whole app.
///
/// Belongs in [MaterialApp.builder], outside the navigator: mounted on a
/// screen it would be painted under every route covering that screen, and
/// those routes are where most toasts are raised from.
///
/// The tablet layout's panel-scoped overlay stays inside that panel, whose
/// bounds are the point of it and are unknown from here.
class KalinkaToastHost extends ConsumerWidget {
  final Widget child;

  const KalinkaToastHost({super.key, required this.child});

  // The Material is what the text takes its style from; without one in scope
  // MaterialApp's debug fallback strikes a yellow double underline through it.
  // A transparent one takes no taps of its own.
  static Widget _layer(Widget overlay) =>
      Material(type: MaterialType.transparency, child: overlay);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inset = ref.watch(toastBottomInsetProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The shell keeps clear of side insets; so do its panes.
        final padding = MediaQuery.paddingOf(context);
        final shellWidth = constraints.maxWidth - padding.horizontal;
        final isTablet = kalinkaSplitLayout(
          shellWidth,
          textScaler: MediaQuery.textScalerOf(context),
        );
        final rail = kalinkaNavigationRailWidth(
          shellWidth,
          windowHeight: MediaQuery.sizeOf(context).height,
          textScaler: MediaQuery.textScalerOf(context),
        );
        return Stack(
          children: [
            child,
            if (isTablet)
              // Bottom-right of browsing, which ends where the player's pane
              // begins.
              Positioned(
                right:
                    padding.right + kalinkaPlayerPaneWidth(shellWidth) + 1 + 20,
                bottom: inset,
                child: _layer(
                  const SizedBox(
                    width: 300,
                    child: KalinkaToastOverlay(
                      isTablet: true,
                      scope: ToastScope.window,
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: rail > 0 ? padding.left + rail : 0.0,
                right: 0,
                bottom: 0,
                child: _layer(KalinkaToastOverlay(bottomOffset: inset)),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ToastCard extends StatefulWidget {
  final ToastEntry entry;

  /// Called once the entry's action has run.
  final VoidCallback onDismiss;

  const _ToastCard({required this.entry, required this.onDismiss});

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    // Enter animation
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_ToastCard old) {
    super.didUpdateWidget(old);
    // Trigger exit animation when the provider marks this entry as dismissing
    if (widget.entry.dismissing && !old.entry.dismissing) {
      _ctrl.reverse();
      return;
    }
    // If dismissing gets canceled (e.g. aggregated toast updated), show again.
    if (!widget.entry.dismissing && old.entry.dismissing) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.entry.isError;
    final action = widget.entry.action;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            color: isError
                ? KalinkaColors.actionDeleteSurface
                : KalinkaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isError
                  ? KalinkaColors.actionDelete
                  : KalinkaColors.borderDefault,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.entry.isLoading)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      KalinkaColors.accentTint,
                    ),
                  ),
                )
              else if (isError)
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: KalinkaColors.actionDeleteLight,
                )
              else
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: KalinkaColors.statusOnline,
                  ),
                ),
              const SizedBox(width: 10),
              // Message
              Flexible(
                child: Text(
                  // Wrapped, not clipped: an ellipsis lands on the half
                  // that says why.
                  widget.entry.message,
                  style: KalinkaTextStyles.toastText,
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 6),
                _ToastActionButton(
                  label: action.label,
                  onPressed: () {
                    action.onPressed();
                    widget.onDismiss();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Neutral text button: the toast says what went wrong, this is where to go.
class _ToastActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ToastActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: clickCursor(interactive: true),
        overlayColor: kalinkaOverlay,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: KalinkaTextStyles.toastText.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
