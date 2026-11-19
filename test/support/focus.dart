import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Available keyboard targets, including controls reached with arrow keys.
Iterable<FocusNode> traversableFocusNodesIn(Finder target) {
  final targets = target.evaluate().toSet();
  return FocusManager.instance.rootScope.descendants.where((node) {
    if (!node.canRequestFocus || node.skipTraversal || node is FocusScopeNode) {
      return false;
    }
    final context = node.context;
    if (context == null) return false;
    if (targets.contains(context)) return true;
    var found = false;
    context.visitAncestorElements((element) {
      found = targets.contains(element);
      return !found;
    });
    return found;
  });
}

/// Whether keyboard focus is on what [target] finds, or inside it.
bool focusIsOn(Finder target) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final targets = target.evaluate().toSet();
  if (targets.contains(focused)) return true;
  var found = false;
  focused.visitAncestorElements((element) {
    found = targets.contains(element);
    return !found;
  });
  return found;
}

/// Presses Tab until focus reaches [target], at most [stops] times.
Future<bool> tabTo(WidgetTester tester, Finder target, {int stops = 40}) async {
  for (var i = 0; i < stops; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (focusIsOn(target)) return true;
  }
  return false;
}

/// The two-pixel foreground outline painted over the control's face.
Finder focusOutlineIn(Finder target, Color color) => find.descendant(
  of: target,
  matching: find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! ShapeDecoration || decoration.shape is! OutlinedBorder) {
      return false;
    }
    return (decoration.shape as OutlinedBorder).side ==
        BorderSide(color: color, width: 2);
  }),
);
