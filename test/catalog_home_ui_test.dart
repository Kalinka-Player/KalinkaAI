import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';
import 'package:kalinka/providers/row_expansion_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/screens/customise_home_screen.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/home/pinned_catalogs_section.dart';
import 'package:kalinka/widgets/home/catalog_artwork.dart';
import 'package:kalinka/widgets/home/catalog_tile.dart';
import 'package:kalinka/widgets/home/preview_shelf.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/search/search_zero_state.dart';
import 'package:kalinka/widgets/search_cards/search_album_row.dart';
import 'package:kalinka/widgets/search_cards/expand_chevron_button.dart';
import 'package:kalinka/widgets/shelf_heading.dart';

import 'support/home_shell.dart';

BrowseItem catalog(
  String id,
  String title, {
  String? art,
  String? description,
}) => BrowseItem(
  id: 'kalinka:alpha:catalog:$id',
  name: title,
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(
    id: 'kalinka:alpha:catalog:$id',
    title: title,
    description: description,
    image: art == null ? null : AlbumImage(large: art),
    filters: const [
      FilterSpec(
        id: 'genre',
        kind: FilterKind.choice,
        label: 'Genre',
        ops: [FilterOp.any],
      ),
    ],
  ),
);
final album = BrowseItem(
  id: 'kalinka:alpha:album:1',
  name: 'An album',
  canBrowse: true,
  canAdd: false,
  album: Album(id: 'kalinka:alpha:album:1', title: 'An album'),
);

ModuleInfo module(String name, {bool catalogs = true}) => ModuleInfo(
  name: name,
  title: '$name music',
  icon: 'music_note_outlined',
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (catalogs) ModuleCapability.catalogs],
);

class CatalogHomeApi extends HomeApi {
  final List<BrowseItem>? editorialItems;
  final String? sourceDescription;
  CatalogHomeApi({this.editorialItems, this.sourceDescription});

  final calls = <({String id, String? filter, int limit})>[];
  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    calls.add((id: id, filter: filter, limit: limit));
    final items = switch (id) {
      '' => [catalog('root', 'alpha music', description: sourceDescription)],
      'kalinka:alpha:catalog:root' => [
        catalog(
          'editorial',
          'Editorial',
          description: 'Hand-picked releases from our editors.',
        ),
      ],
      'kalinka:alpha:catalog:editorial' => editorialItems ?? [album],
      _ => <BrowseItem>[],
    };
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      items.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<FilterValueList> getFilterValues(
    String catalogId,
    String field, {
    int offset = 0,
    int limit = 50,
    String query = '',
  }) async => const FilterValueList(
    offset: 0,
    limit: 50,
    total: 1,
    items: [FilterValue(id: 'jazz', name: 'Jazz')],
  );
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  Size size = const Size(375, 812),
  CatalogHomeApi? api,
}) => pumpHomeShell(
  tester,
  queue: SettableQueue(queueOf(0)),
  api: api ?? CatalogHomeApi(),
  size: size,
  sources: [module('alpha'), module('receiver', catalogs: false)],
);

class _QuietSettings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();

  @override
  Future<void> loadConfig() async {}
}

void main() {
  for (final size in [const Size(375, 812), const Size(1200, 800)]) {
    testWidgets('Music sources gear opens Configuration and returns at $size', (
      tester,
    ) async {
      await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: CatalogHomeApi(),
        size: size,
        sources: [module('alpha')],
        overrides: [
          serverInfoProvider.overrideWith(
            (ref) async => const ServerInfo(
              version: '5.8.0',
              latencyMs: 2,
              pluginCatalogEnabled: true,
            ),
          ),
          modulesStateProvider.overrideWith(
            (ref) async => ModulesAndDevices(
              inputModules: [module('alpha')],
              devices: const [],
            ),
          ),
          pluginCatalogProvider.overrideWith(
            (ref) async => const PluginCatalog(status: 'available'),
          ),
          serverUpdateProvider.overrideWith((ref) async => null),
          settingsProvider.overrideWith(_QuietSettings.new),
        ],
      );

      expect(find.text('MUSIC SOURCES'), findsOneWidget);
      expect(find.text('BROWSE SOURCES'), findsNothing);
      expect(find.text('LISTENING ON'), findsNothing);
      final gear = find.byTooltip('Configure music sources');
      await tester.ensureVisible(gear);
      await tester.pumpAndSettle();
      final homeRect = tester.getRect(find.byType(SearchZeroState));
      final gearRect = tester.getRect(gear);
      expect(gearRect.size.shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(gear);
      await tester.pumpAndSettle();

      final settings = find.byType(PluginCatalogScreen);
      expect(settings, findsOneWidget);
      expect(find.text('Configuration'), findsOneWidget);
      final sourceTab = find
          .descendant(
            of: find.byKey(const ValueKey('catalog-tab-sources')),
            matching: find.byType(Semantics),
          )
          .first;
      expect(tester.widget<Semantics>(sourceTab).properties.selected, isTrue);
      if (size.width >= 900) {
        expect(tester.getRect(settings).left, homeRect.left);
        expect(tester.getRect(settings).width, homeRect.width);
        expect(find.byType(NowPlayingContent), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(settings, findsNothing);
      expect(gear.hitTestable(), findsOneWidget);
      expect(tester.getRect(gear), gearRect);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Music sources stays browsable without Configuration support', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('MUSIC SOURCES'), findsOneWidget);
    expect(find.byTooltip('Configure music sources'), findsNothing);
    expect(find.byKey(const ValueKey('catalog-source-alpha')), findsOneWidget);
  });

  testWidgets(
    'browse, expand one level, pin a filtered catalog and return through parents',
    (tester) async {
      final container = await pump(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('catalog-source-alpha')),
      );
      await tester.tap(find.byKey(const ValueKey('catalog-source-alpha')));
      await tester.pumpAndSettle();
      expect(find.text('Editorial'), findsOneWidget);
      await tester.tap(find.text('Editorial'));
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        'kalinka:alpha:catalog:editorial',
      );
      await tester.tap(find.byType(ExpandChevronButton).first);
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        'kalinka:alpha:catalog:editorial',
      );
      await tester.tap(find.text('An album').first);
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).catalogPage.isAlbum, isTrue);
      expect(find.byTooltip('Pin catalog to Home'), findsNothing);
      container.read(searchSessionProvider.notifier).backFromCatalog();
      container
          .read(searchSessionProvider.notifier)
          .setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pin catalog to Home'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byIcon(Icons.view_carousel_outlined), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
      expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
      await tester.tap(find.text('Cards'));
      await tester.pumpAndSettle();
      final saved = container.read(pinnedCatalogsProvider).single;
      expect(saved.filter.genreIds, ['jazz']);
      expect(saved.preview, HomePreviewType.cards);
      expect(saved.genreNames['jazz'], 'Jazz');
      expect(find.byIcon(CupertinoIcons.pin_slash), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back').first);
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        'kalinka:alpha:catalog:root',
      );
      await tester.tap(find.bySemanticsLabel('Back').first);
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
      expect(find.byType(PinnedCatalogPreview), findsOneWidget);
      expect(find.textContaining('receiver music'), findsNothing);
      final heading = find.descendant(
        of: find.byType(PinnedCatalogPreview),
        matching: find.byType(ShelfHeading),
      );
      expect(
        find.text(
          'alpha music · Jazz · Hand-picked releases from our editors.',
        ),
        findsOneWidget,
      );
      expect(find.text('From alpha music · Jazz'), findsNothing);
      expect(
        tester.widget<ShelfHeading>(heading).iconColor,
        container.read(sourceDisplayInfoProvider)['alpha']!.color,
      );
      expect(
        find.descendant(of: heading, matching: find.byType(Divider)),
        findsNothing,
      );
      final sourceIcon = find.descendant(
        of: heading,
        matching: find.byIcon(CupertinoIcons.pin),
      );
      expect(
        tester.getTopLeft(sourceIcon).dx,
        lessThan(tester.getTopLeft(find.text('EDITORIAL')).dx),
      );
      await tester.ensureVisible(find.text('VIEW ALL'));
      await tester.tap(find.text('VIEW ALL'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unpin catalog'));
      await tester.pumpAndSettle();
      expect(container.read(pinnedCatalogsProvider), isEmpty);
      expect(find.byTooltip('Pin catalog to Home'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.pin_slash), findsNothing);
      container.read(searchSessionProvider.notifier).backFromCatalog();
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
      expect(find.text('Customise Home'), findsNothing);
      expect(
        find.byKey(const ValueKey('catalog-source-alpha')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customise changes layout, orders pins, and unpins without previews',
    (tester) async {
      final container = await pump(tester);
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      for (final id in ['first', 'second']) {
        await notifier.pin(
          PinnedCatalog(
            page: CatalogPage.fromItem(
              catalog(id, id),
              provider: 'alpha music',
            ),
            filter: const BrowseFilterQuery(),
            preview: HomePreviewType.artwork,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Customise'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Customise Home'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SearchZeroState),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Customise Home'), findsOneWidget);
      await tester.ensureVisible(find.text('Customise Home'));
      final button = find.byKey(const ValueKey('customise-home-button'));
      final buttonRect = tester.getRect(button);
      expect(buttonRect.height, greaterThanOrEqualTo(48));
      expect(
        buttonRect.center.dx,
        tester.getRect(find.byType(SearchZeroState)).center.dx,
      );
      Focus.of(tester.element(find.text('Customise Home'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(CustomiseHomeScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CustomiseHomeScreen),
          matching: find.byType(PreviewShelf),
        ),
        findsNothing,
      );
      expect(
        find.byType(DropdownButtonFormField<HomePreviewType>),
        findsNothing,
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CustomiseHomeScreen),
          matching: find.byIcon(Icons.more_horiz),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byTooltip('Unpin first'),
          matching: find.byIcon(CupertinoIcons.pin_slash),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Unpin first'));
      await tester.pumpAndSettle();
      expect(find.byType(KalinkaDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.getCenter(find.byKey(KalinkaDialog.cardKey)),
        const Offset(187.5, 406),
      );
      expect(find.text('Remove “first” from Home?'), findsOneWidget);
      expect(container.read(pinnedCatalogsProvider), hasLength(2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(KalinkaDialog), findsNothing);
      expect(container.read(pinnedCatalogsProvider), hasLength(2));
      expect(
        container.read(pinnedCatalogsProvider).first.preview,
        HomePreviewType.artwork,
      );
      final previewAction = find.ancestor(
        of: find.byTooltip('Preview for first'),
        matching: find.byType(IconButton),
      );
      Material actionSurface(Finder action) => tester.widget<Material>(
        find.descendant(of: action, matching: find.byType(Material)).first,
      );
      void expectRoundAction(Finder action) {
        final shape = actionSurface(action).shape;
        expect(shape, isA<CircleBorder>());
        expect((shape! as CircleBorder).side, BorderSide.none);
      }

      final press = await tester.startGesture(tester.getCenter(previewAction));
      await tester.pump(const Duration(milliseconds: 150));
      expectRoundAction(previewAction);
      final ink = tester.widget<InkWell>(
        find.descendant(of: previewAction, matching: find.byType(InkWell)),
      );
      expect(ink.statesController!.value, contains(WidgetState.pressed));
      final highlight = ink.overlayColor!.resolve({WidgetState.pressed})!;
      expect(highlight.a, greaterThan(0));
      expect(highlight.a, lessThan(0.2));
      await press.up();
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('home-preview-switch-menu'));
      expect(menu, findsOneWidget);
      // MenuAnchor focuses its trigger even after touch. This must not paint
      // the settings header's persistent white focus border.
      expect(
        tester.widget<IconButton>(previewAction).focusNode!.hasFocus,
        isTrue,
      );
      expectRoundAction(previewAction);
      expect(ink.statesController!.value, isNot(contains(WidgetState.pressed)));
      expectRoundAction(
        find.ancestor(
          of: find.byTooltip('Unpin first'),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        tester.getTopLeft(find.byTooltip('Preview for first')).dx,
        lessThan(tester.getTopLeft(find.byTooltip('Unpin first')).dx),
      );
      final artworkButton = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip('Artwork'),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(artworkButton.isSelected, isTrue);
      expectRoundAction(
        find.ancestor(
          of: find.byTooltip('Artwork'),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        artworkButton.style!.backgroundColor!.resolve({WidgetState.selected}),
        KalinkaColors.accent,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Cards'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        container.read(pinnedCatalogsProvider).first.preview,
        HomePreviewType.cards,
      );
      expect(find.text('Cards: Horizontally scrolling cards'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(menu, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expectRoundAction(previewAction);
      await tester.tap(find.byTooltip('Preview for first'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(find.byType(CustomiseHomeScreen), findsOneWidget);
      tester.widget<IconButton>(previewAction).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      final handle = find.byType(ReorderableDragStartListener).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 100));
      for (var step = 0; step < 12; step++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 32));
      }
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(pinnedCatalogsProvider).last.page.title, 'first');
      await tester.tap(find.byTooltip('Unpin second'));
      await tester.pumpAndSettle();
      expect(find.text('Remove “second” from Home?'), findsOneWidget);
      expect(container.read(pinnedCatalogsProvider), hasLength(2));
      await tester.ensureVisible(find.text('Unpin'));
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(container.read(pinnedCatalogsProvider), hasLength(1));
      expect(container.read(pinnedCatalogsProvider).single.page.title, 'first');
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomiseHomeScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(1100, 900),
  ]) {
    testWidgets('source tiles and customisation fit $size at large text', (
      tester,
    ) async {
      const sourceDescription =
          'Browse albums, playlists and artists from across your music library.';
      final container = await pump(
        tester,
        size: size,
        api: CatalogHomeApi(sourceDescription: '  $sourceDescription  '),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: SearchZeroState(onOpenCatalog: (_, _, {focusItemId}) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('alpha music'), findsOneWidget);
      expect(find.textContaining(sourceDescription), findsNothing);
      expect(
        tester.widget<CatalogTile>(find.byType(CatalogTile)).subtitle,
        isNull,
      );
      expect(find.text('Customise Home'), findsNothing);
      expect(tester.takeException(), isNull);
      await container
          .read(pinnedCatalogsProvider.notifier)
          .pin(
            PinnedCatalog(
              page: CatalogPage.fromItem(
                catalog(
                  'editorial',
                  'Editorial albums and selected new releases',
                  description: 'Hand-picked releases from our editors.',
                ),
                provider: 'alpha music',
              ),
              filter: const BrowseFilterQuery(),
              preview: HomePreviewType.compact,
            ),
          );
      await tester.pumpAndSettle();
      final compactTile = find.descendant(
        of: find.byType(PinnedCatalogPreview),
        matching: find.byType(CatalogTile),
      );
      await tester.scrollUntilVisible(
        compactTile,
        150,
        scrollable: find
            .descendant(
              of: find.byType(SearchZeroState),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(compactTile, findsOneWidget);
      expect(find.text('Customise Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final pin = container.read(pinnedCatalogsProvider).single;
      await container
          .read(pinnedCatalogsProvider.notifier)
          .setPreview(pin.key, HomePreviewType.artwork);
      await tester.pumpAndSettle();
      expect(
        find.text('Hand-picked releases from our editors.'),
        findsOneWidget,
      );
      expect(find.text('From alpha music'), findsNothing);
      final artworkCard = find.bySemanticsLabel(
        'Open Editorial albums and selected new releases',
      );
      final captionTitle = find.text(
        'Editorial albums and selected new releases',
      );
      final captionDescription = find.text(
        'Hand-picked releases from our editors.',
      );
      final cardRect = tester.getRect(artworkCard);
      for (final text in [captionTitle, captionDescription]) {
        final textRect = tester.getRect(text);
        expect(cardRect.contains(textRect.topLeft), isTrue);
        expect(cardRect.contains(textRect.bottomRight), isTrue);
      }
      expect(
        find.descendant(
          of: find.byType(PinnedCatalogPreview),
          matching: find.byType(ShelfHeading),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: const CustomiseHomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final unpin = find.byTooltip(
        'Unpin Editorial albums and selected new releases',
      );
      final previewSwitch = find.byTooltip(
        'Preview for Editorial albums and selected new releases',
      );
      await tester.scrollUntilVisible(
        previewSwitch,
        150,
        scrollable: find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(previewSwitch);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-preview-switch-menu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Compact'));
      await tester.pumpAndSettle();
      expect(
        container.read(pinnedCatalogsProvider).single.preview,
        HomePreviewType.compact,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.ensureVisible(unpin);
      await tester.pumpAndSettle();
      await tester.tap(unpin);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Unpin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(find.text('No pinned catalogs yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'customisation occupies the tablet right panel and follows resizing',
    (tester) async {
      final container = await pump(tester, size: const Size(1200, 900));
      await container
          .read(pinnedCatalogsProvider.notifier)
          .pin(
            PinnedCatalog(
              page: CatalogPage.fromItem(
                catalog('editorial', 'Editorial'),
                provider: 'alpha',
              ),
              filter: const BrowseFilterQuery(),
              preview: HomePreviewType.compact,
            ),
          );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Customise Home'));
      await tester.tap(find.text('Customise Home'));
      await tester.pumpAndSettle();
      final panel = find.byType(CustomiseHomeScreen);
      expect(tester.getRect(panel).left, 600.5);
      expect(tester.getSize(panel).width, 599.5);
      expect(find.byType(NowPlayingContent), findsOneWidget);
      await tester.tap(find.byTooltip('Preview for Editorial'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const ValueKey('home-preview-switch-menu')))
            .left,
        greaterThanOrEqualTo(600.5),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unpin Editorial'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(KalinkaDialog.cardKey)).left,
        greaterThanOrEqualTo(600.5),
      );
      expect(
        tester.getCenter(find.byKey(KalinkaDialog.cardKey)),
        const Offset(900, 450),
      );
      tester.view.physicalSize = const Size(375, 812);
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(KalinkaDialog.cardKey)),
        const Offset(187.5, 406),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(KalinkaDialog), findsNothing);
      expect(container.read(pinnedCatalogsProvider), hasLength(1));
      expect(tester.getRect(panel).left, 0);
      expect(tester.getSize(panel).width, 375);
      expect(container.read(homeCustomisationProvider), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(container.read(homeCustomisationProvider), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compact tiles use source tint, preserve mixed order and open saved filters without fetching previews',
    (tester) async {
      final api = CatalogHomeApi();
      final container = await pump(
        tester,
        api: api,
        size: const Size(812, 700),
      );
      final pins = [
        for (final (id, preview) in [
          ('first', HomePreviewType.compact),
          ('second', HomePreviewType.compact),
          ('art', HomePreviewType.artwork),
          ('last', HomePreviewType.compact),
        ])
          PinnedCatalog(
            page: CatalogPage.fromItem(
              catalog(id, id),
              provider: 'alpha music',
            ),
            filter: const BrowseFilterQuery(genreIds: ['jazz']),
            genreNames: const {'jazz': 'Jazz'},
            preview: preview,
          ),
      ];
      api.calls.clear();
      for (final pin in pins) {
        await container.read(pinnedCatalogsProvider.notifier).pin(pin);
      }
      await tester.pumpAndSettle();
      expect(
        api.calls.where((call) => pins.any((pin) => pin.page.id == call.id)),
        isEmpty,
      );
      final tiles = find.descendant(
        of: find.byType(PinnedCatalogsSection),
        matching: find.byType(CatalogTile),
      );
      expect(tiles, findsNWidgets(3));
      expect(
        tester.widget<CatalogTile>(tiles.first).tint,
        container.read(sourceDisplayInfoProvider)['alpha']!.color,
      );
      expect(
        tester.widget<CatalogTile>(tiles.first).subtitle,
        'alpha music · Jazz',
      );
      final surface = tester.widget<Material>(
        find.descendant(of: tiles.first, matching: find.byType(Material)).first,
      );
      expect(surface.color, isNot(KalinkaColors.surfaceRaised));
      expect(find.byType(PreviewShelf), findsNothing);
      final first = tester.getTopLeft(tiles.at(0));
      final second = tester.getTopLeft(tiles.at(1));
      expect(first.dy, second.dy);
      expect(second.dx, greaterThan(first.dx));
      expect(tester.getTopLeft(find.text('art')).dy, greaterThan(first.dy));
      expect(
        tester.getTopLeft(tiles.last).dy,
        greaterThan(tester.getTopLeft(find.text('art')).dy),
      );
      final sourceTile = find.byKey(const ValueKey('catalog-source-alpha'));
      expect(
        tester.getSize(tiles.first).width,
        tester.getSize(sourceTile).width,
      );
      await tester.ensureVisible(tiles.first);
      await tester.pumpAndSettle();
      await tester.tap(tiles.first);
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        pins.first.page.id,
      );
      expect(container.read(searchSessionProvider).catalogFilter.genreIds, [
        'jazz',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in ['album', 'artist', 'playlist', 'collection']) {
    testWidgets('pinned List $kind opens from the row and right chevron', (
      tester,
    ) async {
      final id = 'kalinka:alpha:${kind == 'collection' ? 'playlist' : kind}:1';
      final item = BrowseItem(
        id: id,
        name: 'Preview $kind',
        canBrowse: true,
        canAdd: false,
        canEdit: kind == 'collection',
        album: kind == 'album' ? Album(id: id, title: 'Preview $kind') : null,
        artist: kind == 'artist' ? Artist(id: id, name: 'Preview $kind') : null,
        playlist: kind == 'playlist' || kind == 'collection'
            ? Playlist(id: id, name: 'Preview $kind')
            : null,
      );
      final container = await pump(
        tester,
        api: CatalogHomeApi(editorialItems: [item]),
      );
      await container
          .read(pinnedCatalogsProvider.notifier)
          .pin(
            PinnedCatalog(
              page: CatalogPage.fromItem(catalog('editorial', 'Editorial')),
              filter: const BrowseFilterQuery(),
              preview: HomePreviewType.list,
            ),
          );
      await tester.pumpAndSettle();

      for (final viaChevron in [true, false]) {
        final preview = find.byType(PreviewShelf);
        expect(
          find.descendant(of: preview, matching: find.byTooltip('Expand')),
          findsNothing,
        );
        final chevron = find.descendant(
          of: preview,
          matching: find.byIcon(Icons.chevron_right),
        );
        expect(chevron, findsOneWidget);
        final target = viaChevron
            ? chevron
            : find.descendant(
                of: preview,
                matching: find.text('Preview $kind'),
              );
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();

        expect(container.read(searchSessionProvider).catalogPage.id, id);
        expect(container.read(rowExpansionProvider).unrolled, isEmpty);
        expect(container.read(rowExpansionProvider).artists, isEmpty);
        expect(find.byType(PreviewShelf), findsNothing);

        await tester.tap(find.bySemanticsLabel('Back').first);
        await tester.pumpAndSettle();
        expect(
          container.read(searchSessionProvider).catalogPage.isRoot,
          isTrue,
        );
        expect(find.byType(PreviewShelf), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'List shows five rows and Cards scroll horizontally with saved filters',
    (tester) async {
      final api = CatalogHomeApi(
        editorialItems: List.generate(
          9,
          (index) => BrowseItem(
            id: 'kalinka:alpha:album:$index',
            name: 'Album $index',
            canBrowse: true,
            canAdd: false,
            album: Album(
              id: 'kalinka:alpha:album:$index',
              title: 'Album $index',
            ),
          ),
        ),
      );
      final container = await pump(tester, api: api);
      final saved = PinnedCatalog(
        page: CatalogPage.fromItem(
          catalog('editorial', 'Editorial'),
          provider: 'alpha music',
        ),
        filter: const BrowseFilterQuery(genreIds: ['jazz']),
        preview: HomePreviewType.list,
      );
      await container.read(pinnedCatalogsProvider.notifier).pin(saved);
      await tester.pumpAndSettle();
      expect(
        api.calls.any(
          (c) =>
              c.id == saved.page.id &&
              c.filter == '{"genre":{"any":["jazz"]}}' &&
              c.limit == 5,
        ),
        isTrue,
      );
      expect(find.byType(SearchAlbumRow), findsNWidgets(5));
      expect(
        tester.getTopLeft(find.text('Album 1')).dy,
        greaterThan(tester.getTopLeft(find.text('Album 0')).dy),
      );
      expect(find.text('EDITORIAL'), findsOneWidget);
      await container
          .read(pinnedCatalogsProvider.notifier)
          .setPreview(saved.key, HomePreviewType.cards);
      await tester.pumpAndSettle();
      expect(find.byType(SearchAlbumRow), findsNothing);
      expect(
        tester.widget<PreviewShelf>(find.byType(PreviewShelf)).items,
        hasLength(8),
      );
      expect(
        api.calls.any(
          (c) =>
              c.id == saved.page.id &&
              c.filter == '{"genre":{"any":["jazz"]}}' &&
              c.limit == 8,
        ),
        isTrue,
      );
      final rail = find.descendant(
        of: find.byType(PreviewShelf),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(rail, findsOneWidget);
      await tester.ensureVisible(rail);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: rail, matching: find.byType(Scrollable)),
      );
      await tester.drag(rail, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      await tester.ensureVisible(find.text('VIEW ALL'));
      await tester.tap(find.text('VIEW ALL'));
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).catalogFilter.genreIds, [
        'jazz',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final art in [null, 'https://images.example.test/catalog.jpg']) {
    testWidgets(
      'Artwork uses the catalog image without browsing children ($art)',
      (tester) async {
        final api = CatalogHomeApi();
        final container = await pump(tester, api: api);
        final saved = PinnedCatalog(
          page: CatalogPage.fromItem(
            catalog(
              'editorial',
              'Editorial',
              art: art,
              description: art == null ? '  EDITORIAL  ' : null,
            ),
            // A stale display label must not override the actual source.
            provider: 'Editorial',
          ),
          filter: const BrowseFilterQuery(genreIds: ['jazz']),
          preview: HomePreviewType.artwork,
        );
        api.calls.clear();
        await container.read(pinnedCatalogsProvider.notifier).pin(saved);
        await tester.pumpAndSettle();
        expect(api.calls.where((call) => call.id == saved.page.id), isEmpty);
        expect(find.byType(PreviewShelf), findsNothing);
        expect(find.byType(SearchAlbumRow), findsNothing);
        expect(
          find.descendant(
            of: find.byType(PinnedCatalogPreview),
            matching: find.byType(ShelfHeading),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(PinnedCatalogPreview),
            matching: find.text('VIEW ALL'),
          ),
          findsNothing,
        );
        final card = tester.widget<CatalogArtwork>(find.byType(CatalogArtwork));
        expect(card.description, isNull);
        expect(find.text('From alpha music · jazz'), findsNothing);
        final artwork = find.bySemanticsLabel('Open Editorial');
        expect(artwork, findsOneWidget);
        expect(
          find.descendant(of: artwork, matching: find.text('Editorial')),
          findsOneWidget,
        );
        final sourceIcon = find.descendant(
          of: artwork,
          matching: find.byIcon(Icons.music_note_outlined),
        );
        expect(sourceIcon, findsOneWidget);
        expect(
          tester.widget<Icon>(sourceIcon).color,
          container.read(sourceDisplayInfoProvider)['alpha']!.color,
        );
        expect(
          tester.getTopLeft(sourceIcon).dx,
          lessThan(tester.getTopLeft(find.text('Editorial')).dx),
        );
        if (art == null) {
          expect(find.byTooltip('No artwork available'), findsOneWidget);
        } else {
          final image = tester.widget<Image>(
            find.descendant(of: artwork, matching: find.byType(Image)),
          );
          final provider =
              (image.image as ResizeImage).imageProvider as NetworkImage;
          expect(provider.url, art);
        }
        await tester.ensureVisible(artwork);
        await tester.pumpAndSettle();
        await tester.tap(artwork);
        await tester.pumpAndSettle();
        expect(
          container.read(searchSessionProvider).catalogPage.id,
          saved.page.id,
        );
        expect(container.read(searchSessionProvider).catalogFilter.genreIds, [
          'jazz',
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
