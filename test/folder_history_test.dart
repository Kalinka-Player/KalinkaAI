import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/folder_trail.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search_cards/search_folder_row.dart';

import 'support/home_shell.dart';

const _libraryId = 'kalinka:localfiles:catalog:files';

String _idOf(String name) => 'kalinka:localfiles:catalog:folder.$name';

BrowseItem _folder(String name) => BrowseItem(
  id: _idOf(name),
  name: name,
  canBrowse: true,
  canAdd: true,
  catalog: Catalog(
    id: _idOf(name),
    title: name,
    previewConfig: Preview(type: PreviewType.folder),
  ),
);

/// The library holds 60 folders, each of which holds three more.
class _Api extends HomeApi {
  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = id == _libraryId
        ? [for (var i = 0; i < 60; i++) _folder('Folder $i')]
        : [for (var i = 0; i < 3; i++) _folder('${id.split('.').last} $i')];
    final end = (offset + limit).clamp(0, items.length);
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      offset >= items.length ? const [] : items.sublist(offset, end),
    );
  }
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = await pumpHomeShell(
    tester,
    queue: SettableQueue(queueOf(0)),
    api: _Api(),
    size: const Size(1200, 800),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SearchSessionView())),
    ),
  );
  container
      .read(searchSessionProvider.notifier)
      .openCatalog(id: _libraryId, title: 'My Library', folderLayout: true);
  await tester.pumpAndSettle();
  return container;
}

ScrollPosition _list(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CatalogPageView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

String? _shown(ProviderContainer container) =>
    container.read(searchSessionProvider).shownListing.title;

void main() {
  testWidgets('Back from a folder returns to the one it was opened from, '
      'where it was left', (tester) async {
    final container = await _pump(tester);
    _list(tester).jumpTo(1500);
    await tester.pumpAndSettle();
    final row = find.byType(SearchFolderRow).hitTestable().first;
    final name = tester.widget<SearchFolderRow>(row).item.name!;

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(_shown(container), name);
    expect(_list(tester).pixels, 0);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(_shown(container), 'My Library');
    expect(_list(tester).pixels, 1500);
    expect(find.text(name).hitTestable(), findsOneWidget);
  });

  testWidgets('the way up from a folder just opened goes back to it', (
    tester,
  ) async {
    final container = await _pump(tester);
    SearchSessionState session() => container.read(searchSessionProvider);
    final library = session().visitId;
    final depth = session().previousVisits.length;

    await tester.tap(find.text('Folder 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folder 0 1'));
    await tester.pumpAndSettle();
    expect(_shown(container), 'Folder 0 1');

    final up = find.byIcon(Icons.drive_folder_upload_outlined);
    await tester.tap(up.hitTestable());
    await tester.pumpAndSettle();
    expect(_shown(container), 'Folder 0');
    await tester.tap(up.hitTestable());
    await tester.pumpAndSettle();
    expect(_shown(container), 'My Library');
    expect(session().visitId, library);
    expect(session().previousVisits, hasLength(depth));
  });

  testWidgets('a folder reached again by its crumb opens where it was left', (
    tester,
  ) async {
    final container = await _pump(tester);
    final library = container.read(searchSessionProvider).visitId;
    _list(tester).jumpTo(1500);
    await tester.pumpAndSettle();
    final row = find.byType(SearchFolderRow).hitTestable().first;
    final name = tester.widget<SearchFolderRow>(row).item.name!;
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('$name 0'));
    await tester.pumpAndSettle();

    // Not the folder this one was opened from, so a visit of its own.
    await tester.tap(
      find.descendant(
        of: find.byType(FolderTrail),
        matching: find.byIcon(Icons.folder_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(_shown(container), 'My Library');
    expect(container.read(searchSessionProvider).visitId, isNot(library));
    expect(_list(tester).pixels, 1500);
  });
}
