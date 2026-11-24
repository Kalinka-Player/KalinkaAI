import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'settings_help_button.dart';

/// A setting reached from elsewhere in the page. Reveal the editor without
/// activating it, including when the setting was already in the viewport.
class SettingsJumpTarget extends StatefulWidget {
  const SettingsJumpTarget({super.key, required this.child});
  final Widget child;

  @override
  State<SettingsJumpTarget> createState() => SettingsJumpTargetState();
}

class SettingsJumpTargetState extends State<SettingsJumpTarget> {
  final _focus = FocusNode(skipTraversal: true);
  Timer? _highlight;

  void reveal() {
    final control = _focus.traversalDescendants
        .where(
          (node) =>
              node.context
                  ?.findAncestorWidgetOfExactType<SettingsHelpButton>() ==
              null,
        )
        .firstOrNull;
    (control ?? _focus).requestFocus();
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    _highlight?.cancel();
    setState(() {
      _highlight = Timer(const Duration(milliseconds: 1500), () {
        setState(() => _highlight = null);
      });
    });
  }

  @override
  void dispose() {
    _highlight?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    skipTraversal: true,
    includeSemantics: false,
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: _highlight == null
            ? null
            : Border.all(color: KalinkaColors.textPrimary, width: 2),
      ),
      child: widget.child,
    ),
  );
}
