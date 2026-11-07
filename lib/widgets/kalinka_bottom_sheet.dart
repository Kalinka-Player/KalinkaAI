import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'kalinka_centered_surface.dart';
import 'kalinka_popover.dart';
import 'overlay_card.dart';
import 'sheet_anchor.dart';
import 'tap_highlight.dart';

/// The width cap shared by sheets and their desktop dialogs.
const double kSheetMaxWidth = kKalinkaPopupMaxWidth;

/// Opens a bottom sheet on phones and a centered, dimmed dialog on wider
/// windows. Only the output selector and Connect opt into [useBeak]: an
/// anchored popup with a transparent barrier. Pass their control's context
/// (or [origin]) for the pointer. Content and edits survive resizing. Phone
/// sheets retain drag dismissal and their [SheetAnchor] pane placement.
/// [dialogMaxWidth] caps wide dialogs without narrowing phone sheets.
Future<T?> showKalinkaBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) contentBuilder,
  bool mayFillScreen = false,
  KalinkaPopupOrigin? origin,
  double dialogMaxWidth = kSheetMaxWidth,
  bool useBeak = false,
}) {
  final navigator = Navigator.of(context);
  return navigator.push<T>(
    _AdaptiveSheetRoute<T>(
      origin: origin ?? KalinkaPopupOrigin.forContext(context),
      anchor: SheetAnchor.elementOf(context),
      contentBuilder: contentBuilder,
      mayFillScreen: mayFillScreen,
      dialogMaxWidth: dialogMaxWidth,
      useBeak: useBeak,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      reducedMotion: MediaQuery.disableAnimationsOf(context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _AdaptiveSheetRoute<T> extends PopupRoute<T> {
  final KalinkaPopupOrigin origin;
  final Element? anchor;
  final WidgetBuilder contentBuilder;
  final bool mayFillScreen;
  final double dialogMaxWidth;
  final bool useBeak;
  final CapturedThemes themes;
  final bool reducedMotion;

  _AdaptiveSheetRoute({
    required this.origin,
    required this.anchor,
    required this.contentBuilder,
    required this.mayFillScreen,
    required this.dialogMaxWidth,
    required this.useBeak,
    required this.themes,
    required this.reducedMotion,
    required this.barrierLabel,
  });

  @override
  final String barrierLabel;
  @override
  Color get barrierColor => Colors.black.withValues(alpha: 0.60);
  @override
  bool get barrierDismissible => true;
  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 180);

  @override
  Widget buildModalBarrier() => Builder(
    builder: (context) => AnimatedModalBarrier(
      color: animation!.drive(
        ColorTween(
          begin: Colors.transparent,
          end: offstage || (useBeak && kalinkaUsesPopovers(context))
              ? Colors.transparent
              : barrierColor,
        ).chain(CurveTween(curve: barrierCurve)),
      ),
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    ),
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    KalinkaPopupOriginScope(
      origin: origin,
      // Preserve ModalBottomSheetRoute's announcement and child semantics
      // for both phone sheets and their wide dialog presentation.
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: switch (defaultTargetPlatform) {
          TargetPlatform.iOS || TargetPlatform.macOS => '',
          _ => MaterialLocalizations.of(context).dialogLabel,
        },
        child: _AdaptiveSheet(
          origin: origin,
          anchor: anchor,
          contentBuilder: contentBuilder,
          mayFillScreen: mayFillScreen,
          dialogMaxWidth: dialogMaxWidth,
          useBeak: useBeak,
          animation: animation,
          controller: controller!,
          onClosing: () {
            if (isCurrent) navigator!.pop();
          },
        ),
      ),
    ),
  );
}

class _AdaptiveSheet extends StatefulWidget {
  final KalinkaPopupOrigin origin;
  final Element? anchor;
  final WidgetBuilder contentBuilder;
  final bool mayFillScreen;
  final double dialogMaxWidth;
  final bool useBeak;
  final Animation<double> animation;
  final AnimationController controller;
  final VoidCallback onClosing;

  const _AdaptiveSheet({
    required this.origin,
    required this.anchor,
    required this.contentBuilder,
    required this.mayFillScreen,
    required this.dialogMaxWidth,
    required this.useBeak,
    required this.animation,
    required this.controller,
    required this.onClosing,
  });

  @override
  State<_AdaptiveSheet> createState() => _AdaptiveSheetState();
}

class _AdaptiveSheetState extends State<_AdaptiveSheet> {
  final _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final body = KeyedSubtree(
      key: _bodyKey,
      child: Builder(builder: widget.contentBuilder),
    );
    if (kalinkaUsesPopovers(context)) {
      final content = MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: body,
        ),
      );
      return FadeTransition(
        opacity: widget.animation,
        child: widget.useBeak
            ? KalinkaAnchoredSurface(
                origin: widget.origin,
                maxWidth: widget.dialogMaxWidth,
                child: content,
              )
            : KalinkaCenteredSurface(
                maxWidth: widget.dialogMaxWidth,
                child: content,
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = SheetAnchor.paddingFor(
          widget.anchor,
          constraints.maxWidth,
        );
        return Padding(
          padding: padding,
          child: SafeArea(
            top: widget.mayFillScreen,
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(widget.animation),
                child: BottomSheet(
                  animationController: widget.controller,
                  onClosing: widget.onClosing,
                  backgroundColor: KalinkaColors.surfaceDialog,
                  elevation: 20,
                  shadowColor: Colors.black,
                  constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    side: BorderSide(color: KalinkaColors.borderDefault),
                  ),
                  clipBehavior: Clip.antiAlias,
                  builder: (_) => SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(top: 12),
                              decoration: BoxDecoration(
                                color: KalinkaColors.surfaceOverlay,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Flexible(child: body),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The margin a sheet's rows keep: where their content starts, how far the
/// rule between them runs, and where the mark under the pointer stops. All
/// three read as one edge, so they are one number.
const double kSheetGutter = 20;

/// A sheet's title, what it is about under it, and the × that closes it.
class SheetHeader extends StatelessWidget {
  final String title;
  final String summary;

  const SheetHeader({super.key, required this.title, this.summary = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetGutter, 16, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KalinkaTextStyles.sectionLabel),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(summary, style: KalinkaTextStyles.trackRowSubtitle),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          OverlayCloseButton(
            onTap: () => Navigator.of(context).pop(),
            label: 'Close',
          ),
        ],
      ),
    );
  }
}

/// The hairline between two rows of a sheet. Every sheet's sections are ruled
/// the same way.
class SheetDivider extends StatelessWidget {
  const SheetDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kSheetGutter),
    child: Divider(color: KalinkaColors.borderSubtle, height: 1),
  );
}

/// What the rows under it have in common, over the first of them.
class SheetSectionLabel extends StatelessWidget {
  final String text;

  const SheetSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(kSheetGutter, 0, kSheetGutter, 8),
    child: Text(text, style: KalinkaTextStyles.traySectionLabel),
  );
}

/// A row in a sheet: a tinted glyph, what it does, and whatever sits at its
/// end. Its content, the rule under it and the mark under the pointer all
/// keep the same gutter, so the three read as one edge.
class SheetRow extends StatelessWidget {
  /// The tile at the row's head. Left out where the row reads as a setting
  /// rather than a destination, and then the label starts at the gutter.
  final IconData? icon;

  final Color? iconBackground;
  final Color? iconColor;
  final String label;

  /// A second line under the label. Empty leaves the row a single line.
  final String sublabel;

  /// Colours the label where the row is worth hesitating over. A row that
  /// merely goes somewhere leaves it alone.
  final Color? labelColor;

  /// What sits at the row's end — a [SheetChevron] where it opens something
  /// else, a badge, a switch.
  final Widget? trailing;

  final VoidCallback? onTap;

  const SheetRow({
    super.key,
    this.icon,
    this.iconBackground,
    this.iconColor,
    required this.label,
    this.sublabel = '',
    this.labelColor,
    this.trailing,
    this.onTap,
  }) : assert(
         icon == null || (iconBackground != null && iconColor != null),
         'an icon needs the tile it sits in',
       );

  @override
  Widget build(BuildContext context) {
    return TapHighlight(
      onTap: onTap,
      inset: kSheetGutter,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSheetGutter,
          vertical: 13,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: KalinkaTextStyles.trayRowLabel.copyWith(
                      color: labelColor,
                    ),
                  ),
                  if (sublabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sublabel, style: KalinkaTextStyles.trayRowSublabel),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The mark at the end of a row that opens something else.
class SheetChevron extends StatelessWidget {
  const SheetChevron({super.key});

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right, size: 18, color: KalinkaColors.textMuted);
}
