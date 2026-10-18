import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
