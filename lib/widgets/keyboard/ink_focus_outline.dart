import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Traces the edge of an InkWell's visible face using its existing focus target.
class InkFocusOutline extends StatefulWidget {
  const InkFocusOutline({
    super.key,
    required this.shape,
    required this.child,
    this.color = KalinkaColors.textPrimary,
  });

  final OutlinedBorder shape;
  final Widget child;
  final Color color;

  @override
  State<InkFocusOutline> createState() => _InkFocusOutlineState();
}

class _InkFocusOutlineState extends State<InkFocusOutline> {
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final focused = Focus.of(context).hasPrimaryFocus;
    if (_focused == focused) return;
    _focused = focused;
    if (focused) {
      FocusManager.instance.addHighlightModeListener(_highlightChanged);
    } else {
      FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    }
  }

  void _highlightChanged(FocusHighlightMode _) => setState(() {});

  @override
  void dispose() {
    if (_focused) {
      FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      if (_focused &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: widget.shape.copyWith(
                  side: BorderSide(color: widget.color, width: 2),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
