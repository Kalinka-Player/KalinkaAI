import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/widgets/column_separator.dart';
import 'package:kalinka/widgets/search_cards/browse_item_rows.dart';
import 'package:kalinka/widgets/search_cards/row_columns.dart';

BrowseItem _album(String id, {int? trackCount}) => BrowseItem(
  id: 'kalinka:x:album:$id',
  name: 'Album $id',
  canBrowse: true,
  canAdd: true,
  album: Album(
    id: id,
    title: 'Album $id',
    trackCount: trackCount,
    artist: Artist(id: 'r', name: 'Someone'),
  ),
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpRows(
    WidgetTester tester,
    List<BrowseItem> items, {
    required double width,
  }) async {
    tester.view.physicalSize = Size(width + 100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: BrowseItemRows(items: items),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('albums with their facts fill a Details column', (tester) async {
    await pumpRows(tester, [
      _album('a', trackCount: 12),
      _album('b'),
    ], width: 700);

    expect(find.byType(RowColumnsHeader), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('12 tracks'), findsOneWidget);
  });

  testWidgets('albums with none keep no empty Details column', (tester) async {
    await pumpRows(tester, [_album('a'), _album('b')], width: 700);

    // Nothing else to show yet: the plain rows, unnamed.
    expect(find.text('DETAILS'), findsNothing);
    expect(find.byType(ColumnSeparator), findsNothing);

    await pumpRows(tester, [_album('a'), _album('b')], width: 900);
    // The artist still earns its column; the details never take one.
    expect(find.text('ARTIST'), findsOneWidget);
    expect(find.text('DETAILS'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(RowColumnCells),
        matching: find.byType(ColumnSeparator),
      ),
      findsNWidgets(2),
    );
  });
}
