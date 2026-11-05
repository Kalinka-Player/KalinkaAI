import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/settings_controls/warning_note.dart';

Future<double> _width(WidgetTester tester, {required bool fitsContent}) async {
  await tester.binding.setSurfaceSize(const Size(800, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WarningNote(
              message: 'Short',
              fitsContent: fitsContent,
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ),
  );
  return tester
      .getSize(
        find
            .descendant(
              of: find.byType(WarningNote),
              matching: find.byType(Container),
            )
            .first,
      )
      .width;
}

void main() {
  testWidgets('a note spans the width it is given', (tester) async {
    expect(await _width(tester, fitsContent: false), 800);
  });

  testWidgets('a note that fits its content is only as wide as its message', (
    tester,
  ) async {
    expect(await _width(tester, fitsContent: true), lessThan(200));
  });
}
