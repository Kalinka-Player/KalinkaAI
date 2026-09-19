// Editing the list of music folders: the control the backend's suggestions
// and its verdicts both land on.
//
// The rows commit the way every other settings input does — on blur, on
// submit — rather than on each keystroke. A half-typed path that staged
// itself would be sent away to be judged and come back marked wrong while
// it was still being written.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/widgets/settings_controls/option_picker.dart';
import 'package:kalinka/widgets/settings_controls/settings_combo_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_list_editor.dart';

const _suggestions = [
  OptionSpec(
    value: 'smb://192.168.1.20/',
    label: 'NAS',
    description: '192.168.1.20 · found over mDNS',
  ),
  OptionSpec(value: '/media/usb0', label: '/media/usb0'),
];

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<String> items,
  required void Function(List<String>) onChanged,
  List<OptionSpec>? suggestions,
  List<ConfigIssue> issues = const [],
}) async {
  await tester.pumpWidget(
    _wrap(
      SettingsListEditor(
        items: items,
        suggestions: suggestions,
        issues: issues,
        onChanged: onChanged,
      ),
    ),
  );
}

void main() {
  group('typing a folder', () {
    testWidgets('is not staged before the row is left', (tester) async {
      final staged = <List<String>>[];
      await _pumpEditor(tester, items: const ['/music'], onChanged: staged.add);

      await tester.enterText(find.byType(TextField).first, '/mus');
      await tester.pump();

      expect(staged, isEmpty);
    });

    testWidgets('is staged once the row is left', (tester) async {
      final staged = <List<String>>[];
      await _pumpEditor(
        tester,
        items: const ['/music', '/other'],
        onChanged: staged.add,
      );

      await tester.enterText(find.byType(TextField).first, '/elsewhere');
      await tester.tap(find.byType(TextField).last);
      await tester.pumpAndSettle();

      expect(staged.single, ['/elsewhere', '/other']);
    });
  });

  group('adding and removing', () {
    testWidgets('adding appends an empty row ready to type into', (
      tester,
    ) async {
      final staged = <List<String>>[];
      await _pumpEditor(tester, items: const ['/music'], onChanged: staged.add);

      await tester.tap(find.text('Add item'));
      await tester.pump();

      expect(staged.single, ['/music', '']);
    });

    testWidgets('the new row takes the focus', (tester) async {
      var items = <String>['/music'];
      late StateSetter refresh;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return SettingsListEditor(
                items: items,
                onChanged: (updated) => setState(() => items = updated),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      refresh(() {});

      final added = tester.widget<TextField>(find.byType(TextField).last);
      expect(added.focusNode?.hasFocus, isTrue);
    });

    testWidgets('removing a row takes its text with it', (tester) async {
      // Without a key per position the controllers would shift up and the
      // removed row's text would reappear on the row below it.
      var items = <String>['/first', '/second'];
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => SettingsListEditor(
              items: items,
              onChanged: (updated) => setState(() => items = updated),
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Remove').first);
      await tester.pumpAndSettle();

      expect(find.text('/second'), findsOneWidget);
      expect(find.text('/first'), findsNothing);
    });
  });

  group('what the backend says about an item', () {
    testWidgets('lands under the item it is about', (tester) async {
      await _pumpEditor(
        tester,
        items: const ['/music', 'smb://nas'],
        issues: const [
          ConfigIssue(
            path: 'folders',
            index: 1,
            message: 'name the share on nas',
          ),
        ],
        onChanged: (_) {},
      );

      expect(find.text('name the share on nas'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('a warning reads as one rather than as a refusal', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        items: const ['smb://nas/music'],
        issues: const [
          ConfigIssue(
            path: 'folders',
            index: 0,
            message: 'it did not answer',
            severity: IssueSeverity.warning,
          ),
        ],
        onChanged: (_) {},
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('picking a folder from what was found', () {
    testWidgets('a field with suggestions offers browsing', (tester) async {
      await _pumpEditor(
        tester,
        items: const [''],
        suggestions: _suggestions,
        onChanged: (_) {},
      );

      expect(find.byType(SettingsComboInput), findsOneWidget);
      expect(find.bySemanticsLabel('Browse'), findsOneWidget);
    });

    testWidgets('a field without them is a plain text row', (tester) async {
      await _pumpEditor(tester, items: const [''], onChanged: (_) {});

      expect(find.byType(SettingsComboInput), findsNothing);
      expect(find.bySemanticsLabel('Browse'), findsNothing);
    });

    testWidgets('what is picked is written into the row and staged', (
      tester,
    ) async {
      final staged = <List<String>>[];
      await _pumpEditor(
        tester,
        items: const [''],
        suggestions: _suggestions,
        onChanged: staged.add,
      );

      await tester.tap(find.bySemanticsLabel('Browse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(staged.single, ['smb://192.168.1.20/']);
    });

    testWidgets('an empty list says to type it instead', (tester) async {
      await _pumpEditor(
        tester,
        items: const [''],
        suggestions: const [],
        onChanged: (_) {},
      );

      await tester.tap(find.bySemanticsLabel('Browse'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing found yet'), findsOneWidget);
    });

    testWidgets('the browse control is there before anything has answered', (
      tester,
    ) async {
      // A NAS answers a broadcast when it feels like it. A button that
      // appears only once one has is a button nobody knows to wait for.
      await _pumpEditor(
        tester,
        items: const [''],
        suggestions: const [],
        onChanged: (_) {},
      );

      expect(find.bySemanticsLabel('Browse'), findsOneWidget);
    });

    testWidgets('an empty list says so rather than showing nothing', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        items: const [''],
        suggestions: const [],
        onChanged: (_) {},
      );

      await tester.tap(find.bySemanticsLabel('Browse'));
      await tester.pumpAndSettle();

      expect(find.byType(OptionPicker), findsOneWidget);
      expect(find.textContaining('Nothing found yet'), findsOneWidget);
    });
  });
}
