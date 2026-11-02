import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour the text field [field] finds draws what is typed in.
Color? fieldTextColor(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .style
    .color;
