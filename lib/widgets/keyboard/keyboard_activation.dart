import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Adds keyboard activation to a control that already owns its pointer/drag
/// gestures. A foreground ring leaves its dimensions and artwork unchanged.
class KeyboardActivation extends StatefulWidget {
  const KeyboardActivation({
    super.key,
    required this.onActivate,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.focusNode,
    this.showFocusOutline = true,
  });

  final VoidCallback? onActivate;
  final Widget child;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;
  final bool showFocusOutline;

  @override
  State<KeyboardActivation> createState() => _KeyboardActivationState();
}

class _KeyboardActivationState extends State<KeyboardActivation>
    with AutomaticKeepAliveClientMixin {
  bool _focused = false;
  bool _highlight = false;

  @override
  bool get wantKeepAlive => _focused;

  Object? _activate(Intent _) {
    widget.onActivate?.call();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      enabled: widget.onActivate != null,
      onFocusChange: (focused) {
        _focused = focused;
        updateKeepAlive();
      },
      onShowFocusHighlight: widget.showFocusOutline
          ? (highlight) => setState(() => _highlight = highlight)
          : null,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: _activate,
        ),
      },
      child: Semantics(
        button: widget.onActivate != null,
        child: widget.showFocusOutline
            ? DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: Border.all(
                    color: _highlight && widget.onActivate != null
                        ? KalinkaColors.textPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: widget.child,
              )
            : widget.child,
      ),
    );
  }
}
