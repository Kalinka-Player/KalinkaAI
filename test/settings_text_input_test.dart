import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/widgets/pending_changes_banner.dart';
import 'package:kalinka/widgets/settings_controls/settings_row.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';

const _namePath = 'base_config.server.service_name';

class _Settings extends SettingsNotifier {
  @override
  SettingsState build() =>
      const SettingsState(values: {_namePath: 'Living Room'});
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  ValueChanged<String>? onApply,
}) async {
  var open = true;
  final rowKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(_Settings.new)],
      child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(settingsProvider);
                final notifier = ref.read(settingsProvider.notifier);
                return Column(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => open = !open),
                      child: Text(open ? 'Back to queue' : 'Settings'),
                    ),
                    if (open) ...[
                      PendingChangesBanner(
                        pendingCount: state.pendingCount,
                        onDiscard: notifier.discardAll,
                        onApply: () => onApply?.call(
                          state.getEffective(_namePath) as String,
                        ),
                      ),
                      SettingsRow(
                        key: rowKey,
                        label: 'Server name',
                        isVertical: true,
                        isStaged: state.isStaged(_namePath),
                        control: SettingsTextInput(
                          value: state.getEffective(_namePath) as String,
                          onChanged: (value) =>
                              notifier.stageChange(_namePath, value),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Consumer)));
}

void main() {
  testWidgets('editing a name makes Apply available without losing focus', (
    tester,
  ) async {
    String? applied;
    final container = await _pumpSettings(
      tester,
      onApply: (value) => applied = value,
    );
    final field = find.byType(TextField);
    final inputState = tester.state(find.byType(SettingsTextInput));

    await tester.enterText(field, 'Kitchen');
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).getEffective(_namePath), 'Kitchen');
    expect(tester.state(find.byType(SettingsTextInput)), same(inputState));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(find.text('APPLY'), findsOneWidget);

    await tester.enterText(field, 'Kitchen Pi');
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPLY'));
    await tester.pump();
    expect(applied, 'Kitchen Pi');
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a focused name edit and returning does not throw', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    await tester.enterText(find.byType(TextField), 'Kitchen');
    await tester.pump();
    await tester.tap(find.text('Back to queue'));
    await tester.pumpAndSettle();
    final closingError = tester.takeException();
    expect(container.read(settingsProvider).getEffective(_namePath), 'Kitchen');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final reopeningError = tester.takeException();
    expect(closingError, isNull);
    expect(reopeningError, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Kitchen',
    );
  });

  testWidgets('discard restores the name even while the field has focus', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    final inputState = tester.state(find.byType(SettingsTextInput));
    await tester.enterText(find.byType(TextField), 'Kitchen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).hasPendingChanges, isFalse);
    expect(tester.state(find.byType(SettingsTextInput)), same(inputState));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Living Room',
    );
    await tester.tap(find.text('Back to queue'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(container.read(settingsProvider).hasPendingChanges, isFalse);
  });
}
