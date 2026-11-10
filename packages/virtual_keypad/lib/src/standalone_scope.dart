import 'package:flutter/widgets.dart';

/// Scopes a [VirtualKeypad] in standalone mode to only respond to text fields
/// within its subtree.
///
/// Wrap both your text fields and [VirtualKeypad] with this widget to prevent
/// the keyboard from appearing when a text field outside the scope gains focus.
/// This is especially useful in tools like Widgetbook where multiple widget
/// previews are shown simultaneously.
///
/// ```dart
/// VirtualKeypadStandaloneScope(
///   child: Column(
///     children: [
///       TextField(controller: myController),
///       VirtualKeypad(standalone: true),
///     ],
///   ),
/// )
/// ```
///
/// Without this wrapper, [VirtualKeypad] in standalone mode responds to any
/// focused text field in the application.
class VirtualKeypadStandaloneScope extends StatefulWidget {
  /// Creates a standalone scope for [VirtualKeypad].
  const VirtualKeypadStandaloneScope({super.key, required this.child});

  /// The child widget tree containing text fields and the keyboard.
  final Widget child;

  /// Returns the nearest [VirtualKeypadStandaloneScopeState] ancestor, or
  /// null if there is none.
  static VirtualKeypadStandaloneScopeState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<VirtualKeypadStandaloneScopeState>();
  }

  @override
  State<VirtualKeypadStandaloneScope> createState() =>
      VirtualKeypadStandaloneScopeState();
}

/// State for [VirtualKeypadStandaloneScope].
class VirtualKeypadStandaloneScopeState
    extends State<VirtualKeypadStandaloneScope> {
  /// Creates the state that limits standalone keyboard routing to a subtree.
  VirtualKeypadStandaloneScopeState();

  @override
  Widget build(BuildContext context) => widget.child;
}
