import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';

BrowseItem _folder(String name, {bool canAdd = true, String? art}) =>
    BrowseItem(
      id: 'kalinka:localfiles:catalog:folder.$name',
      name: name,
      subname: '3 tracks',
      canBrowse: true,
      canAdd: canAdd,
      catalog: Catalog(
        id: 'kalinka:localfiles:catalog:folder.$name',
        title: name,
        description: '1 folder · 2 tracks · 9 min',
        image: art == null
            ? null
            : AlbumImage(large: art, small: art, thumbnail: art),
        previewConfig: Preview(type: PreviewType.folder),
      ),
    );

void openLibrary(ProviderContainer container) => container
    .read(searchSessionProvider.notifier)
    .openCatalog(
      id: 'kalinka:localfiles:catalog:files',
      title: 'My Library',
      provider: 'My Library',
      folderLayout: true,
    );

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  SearchSessionNotifier session() =>
      container.read(searchSessionProvider.notifier);
  SearchSessionState state() => container.read(searchSessionProvider);
  List<String?> shownPath() => [
    for (final folder in state().folderPath) folder.title,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    openLibrary(container);
  });

  test('a folder is told from a catalog by the layout it asks for', () {
    expect(_folder('music').browseType, BrowseType.folder);
    expect(PreviewTypeExtension.fromValue('folder'), PreviewType.folder);
    final plain = BrowseItem(
      id: 'kalinka:localfiles:catalog:albums',
      canBrowse: true,
      canAdd: false,
      catalog: Catalog(id: 'albums', title: 'Albums'),
    );
    expect(plain.browseType, BrowseType.catalog);
  });

  test('a folder shown carries what its row said about it', () {
    final folder = CatalogPage.fromItem(
      _folder('Jazz', canAdd: false, art: '/resource/folder/k_large.jpg'),
      provider: 'My Library',
    );

    expect(folder.folderLayout, isTrue);
    expect(folder.canAdd, isFalse);
    expect(folder.artPath, '/resource/folder/k_large.jpg');
    expect(folder.description, '1 folder · 2 tracks · 9 min');
    expect(folder.withoutFocus().folderLayout, isTrue);
  });

  test('a folder opens in place of the one it is listed in', () {
    session().openFolder(_folder('Jazz'));
    session().openFolder(_folder('Miles Davis'));

    expect(state().catalogPage.title, 'My Library');
    expect(shownPath(), ['Jazz', 'Miles Davis']);
    expect(state().shownListing.title, 'Miles Davis');
  });

  test('a crumb shows its folder and the home mark the page\'s top', () {
    session().openFolder(_folder('Jazz'));
    session().openFolder(_folder('Miles Davis'));
    session().openFolder(_folder('Kind of Blue'));

    session().showFolderAt(1);
    expect(shownPath(), ['Jazz']);

    session().showFolderAt(0);
    expect(shownPath(), isEmpty);
    expect(state().shownListing.title, 'My Library');
  });

  test('back leaves the page, not one folder', () {
    session().openFolder(_folder('Jazz'));
    session().openFolder(_folder('Miles Davis'));

    session().backToCatalogsRoot();

    expect(state().catalogPage.isRoot, isTrue);
    expect(state().folderPath, isEmpty);
  });

  test('opening the page again shows the folder it was left on', () {
    session().openFolder(_folder('Jazz'));
    session().openFolder(_folder('Miles Davis'));
    session().backToCatalogsRoot();

    openLibrary(container);

    expect(shownPath(), ['Jazz', 'Miles Davis']);
  });

  test('the folder left on outlives the app', () {
    session().openFolder(_folder('Jazz', art: '/resource/folder/k_large.jpg'));
    session().openFolder(_folder('Miles Davis', canAdd: false));

    final restarted = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(restarted.dispose);
    openLibrary(restarted);

    final path = restarted.read(searchSessionProvider).folderPath;
    expect([for (final folder in path) folder.title], ['Jazz', 'Miles Davis']);
    expect(path.first.artPath, '/resource/folder/k_large.jpg');
    expect(path.first.description, '1 folder · 2 tracks · 9 min');
    expect(path.first.provider, 'My Library');
    expect(path.last.canAdd, isFalse);
    expect(path.every((folder) => folder.folderLayout), isTrue);
  });

  test('a page left at its top opens at its top', () {
    session().openFolder(_folder('Jazz'));
    session().showFolderAt(0);
    session().backToCatalogsRoot();

    openLibrary(container);

    expect(state().folderPath, isEmpty);
  });

  test('another server\'s library opens at its top', () {
    session().openFolder(_folder('Jazz'));
    session().backToCatalogsRoot();
    container
        .read(connectionSettingsProvider.notifier)
        .setDeviceEphemeral('Other', 'other.local', 8000);

    openLibrary(container);

    expect(state().folderPath, isEmpty);
  });

  test('a page of another layout keeps no folder', () {
    session().openFolder(_folder('Jazz'));

    session().openCatalog(
      id: 'kalinka:localfiles:catalog:files',
      title: 'My Library',
    );

    expect(state().folderPath, isEmpty);
  });

  test('choosing Catalogs again leaves the folders too', () {
    session().openFolder(_folder('Jazz'));

    session().selectView(FindMusicView.catalogs);

    expect(state().catalogPage.isRoot, isTrue);
    expect(state().folderPath, isEmpty);
  });
}
