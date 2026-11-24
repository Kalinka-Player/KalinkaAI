import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/room_eq.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/room_eq/band_editor_header.dart';

void main() {
  testWidgets(
    'band controls fit the pane and keep the removal target accessible',
    (t) async {
      var removals = 0;
      final changes = <FilterShape>[];
      Future<void> show(
        double width, {
        double scale = 1,
        bool enabled = true,
      }) async {
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: width,
                    child: BandEditorHeader(
                      number: 10,
                      shape: FilterShape.highPass,
                      onShapeChanged: enabled ? changes.add : null,
                      onRemove: enabled ? () => removals++ : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      final menu = find.byType(DropdownButton<FilterShape>);
      final remove = find.byTooltip('Remove band 10');
      await show(720);
      expect(
        find.descendant(of: remove, matching: find.text('Remove')),
        findsOneWidget,
      );
      expect(t.getCenter(menu).dy, t.getCenter(remove).dy);
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(changes, isEmpty);

      await show(260, scale: 1.6);
      expect(find.text('Remove'), findsNothing);
      expect(find.bySemanticsLabel('Remove band 10'), findsOneWidget);
      expect(t.getSize(remove), const Size.square(48));
      expect(
        t.getTopLeft(menu).dy,
        greaterThanOrEqualTo(t.getBottomLeft(remove).dy),
      );
      await t.tap(remove);
      expect(removals, 1);
      await show(260, enabled: false);
      expect(t.widget<DropdownButton<FilterShape>>(menu).onChanged, isNull);
      expect(
        t
            .widget<OutlinedButton>(
              find.descendant(
                of: remove,
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
}
