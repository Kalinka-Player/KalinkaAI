import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/widgets/settings_controls/settings_row.dart';

// Staging a setting tints its row; nothing in the row may move or resize.

Widget _row({required bool staged, required bool vertical}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        SettingsRow(
          label: 'Server name',
          sublabel: 'How the server shows up on the network',
          isStaged: staged,
          isVertical: vertical,
          control: const SizedBox(width: 120, height: 32),
        ),
      ],
    ),
  ),
);

void main() {
  for (final vertical in [false, true]) {
    testWidgets(
      'staging a ${vertical ? 'vertical' : 'horizontal'} row keeps its layout',
      (tester) async {
        Rect labelRect() => tester.getRect(find.text('Server name'));
        Size rowSize() => tester.getSize(find.byType(SettingsRow));

        await tester.pumpWidget(_row(staged: false, vertical: vertical));
        final label = labelRect();
        final size = rowSize();

        await tester.pumpWidget(_row(staged: true, vertical: vertical));
        expect(labelRect(), label);
        expect(rowSize(), size);
        expect(find.text('Staged'), findsNothing);
      },
    );
  }
}
