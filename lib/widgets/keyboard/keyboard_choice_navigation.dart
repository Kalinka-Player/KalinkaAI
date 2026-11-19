import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const keyboardArrowKeys = [
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
];

bool isKeyboardSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.gameButtonA;

/// A keypad popup keeps the text input connection on the field beneath it.
/// Navigate its visible choices with the same arrows and OK as the main grid.
class KeyboardChoiceNavigation extends StatefulWidget {
  const KeyboardChoiceNavigation({
    super.key,
    required this.enabled,
    required this.count,
    required this.columns,
    required this.onSelect,
    required this.builder,
    this.initialIndex = 0,
  });

  final bool enabled;
  final int count;
  final int columns;
  final int initialIndex;
  final ValueChanged<int> onSelect;
  final Widget Function(int? highlighted) builder;

  @override
  State<KeyboardChoiceNavigation> createState() =>
      _KeyboardChoiceNavigationState();
}

class _KeyboardChoiceNavigationState extends State<KeyboardChoiceNavigation> {
  late int _index = math.max(0, widget.initialIndex);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (!widget.enabled ||
        !TickerMode.valuesOf(context).enabled ||
        widget.count == 0 ||
        event.synthesized ||
        event is KeyUpEvent ||
        ModalRoute.isCurrentOf(context) != true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isKeyboardSelectKey(key)) {
      if (event is KeyDownEvent) widget.onSelect(_index);
    } else if (keyboardArrowKeys.contains(key)) {
      final row = _index ~/ widget.columns;
      final last = widget.count - 1;
      final next = switch (key) {
        LogicalKeyboardKey.arrowLeft => math.max(
          row * widget.columns,
          _index - 1,
        ),
        LogicalKeyboardKey.arrowRight => math.min(
          math.min(last, (row + 1) * widget.columns - 1),
          _index + 1,
        ),
        LogicalKeyboardKey.arrowUp when row > 0 => _index - widget.columns,
        LogicalKeyboardKey.arrowDown when row < last ~/ widget.columns =>
          math.min(last, _index + widget.columns),
        _ => _index,
      };
      if (next != _index) setState(() => _index = next);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(widget.enabled ? _index : null);
}
