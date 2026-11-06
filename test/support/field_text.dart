import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour of the typed text in the field [field] finds.
Color? fieldTextColor(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .style
    .color;
