import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/widgets/browse_filters/browse_filter_form.dart';
import 'package:kalinka/data_model/module_icons.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/module_icon_cache.dart';
import 'package:kalinka/providers/plugin_state.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/home/home_source_list.dart';
import 'package:kalinka/widgets/module_artwork.dart';
import 'package:kalinka/widgets/plugin_catalog_entry.dart';
import 'package:kalinka/widgets/source_badge.dart';

import 'support/receivers.dart';

const _icons = ModuleIcons(
  small: ModuleIconImage(
    url: '/small',
    mimeType: 'image/png',
    aspectRatio: 26 / 14,
  ),
  standard: ModuleIconImage(url: '/standard', mimeType: 'image/png'),
  monochrome: true,
);
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABoAAAAOCAYAAAAxDQxDAAAAH0lEQVR4nGNkYGD4z0AHwEQPS0YtGrVo1KJRi0aKRQAKwgEbDHguswAAAABJRU5ErkJggg==',
);

void main() {
  test(
    'module and settings metadata carry artwork, old payloads keep fallback',
    () {
      final json = {
        'name': 'upnp',
        'title': 'UPnP',
        'enabled': true,
        'state': 'ready',
        'icons': _icons.toJson(),
      };
      final module = ModuleInfo.fromJson(json);
      expect(module.icons!.small.aspectRatio, 26 / 14);
      expect(
        ModuleInfo.fromJson(module.toJson()).icons!.toJson(),
        _icons.toJson(),
      );
      final copied = ModulesAndDevices(
        inputModules: [module],
        devices: [module],
      ).copyWith();
      expect(copied.inputModules.single.icons!.toJson(), _icons.toJson());
      expect(copied.devices.single.icons!.toJson(), _icons.toJson());
      final spec = ModuleSpec.fromJson({
        'id': 'upnp',
        'kind': 'input_module',
        'title': 'UPnP',
        'icons': _icons.toJson(),
      });
      expect(spec.icons!.toJson(), _icons.toJson());
      json.remove('icons');
      expect(ModuleInfo.fromJson(json).icons, isNull);
      expect(
        ModuleIcons.tryParse({
          'small': {'url': '/x', 'mime_type': 'image/jpeg'},
        }),
        isNull,
      );
    },
  );

  for (final (brightness, scale) in [
    (Brightness.dark, 1.0),
    (Brightness.light, 3.0),
  ]) {
    testWidgets(
      'wide attribution renders at 14/20 dp without padding, $brightness, text scale $scale',
      (tester) async {
        final calls = <Uri>[];
        await tester.binding.setSurfaceSize(const Size(320, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cache = ModuleIconCache(
          client: MockClient((request) async {
            calls.add(request.url);
            return http.Response.bytes(_png, 200);
          }),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              urlResolverProvider.overrideWithValue(
                UrlResolver('http://server'),
              ),
              moduleIconCacheProvider.overrideWithValue(cache),
              sourceModulesProvider.overrideWith(
                (ref) => [
                  ModuleInfo(
                    name: 'upnp',
                    title: 'UPnP',
                    icons: _icons,
                    enabled: true,
                    state: ModuleState.ready,
                  ),
                  ModuleInfo(
                    name: 'other',
                    title: 'Other',
                    enabled: true,
                    state: ModuleState.ready,
                  ),
                ],
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: Column(
                  children: [
                    SourceBadge(entityId: 'kalinka:upnp:track:1'),
                    SourceBadge(
                      entityId: 'kalinka:upnp:track:2',
                      size: SourceBadgeSize.small,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final bytes = await cache.load(
            'http://server/small',
            _icons.small,
            small: true,
          );
          await precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(ModuleArtwork).first),
          );
        });
        await tester.pumpAndSettle();
        final marks = tester
            .widgetList<ModuleArtwork>(find.byType(ModuleArtwork))
            .toList();
        expect(marks.map((mark) => mark.size), [20 * scale, 14 * scale]);
        for (final element in find.byType(ModuleArtwork).evaluate()) {
          final mark = element.widget as ModuleArtwork;
          final size = tester.getSize(find.byWidget(mark));
          expect(size.height, mark.size);
          expect(size.width, closeTo(mark.size * 26 / 14, 0.001));
        }
        expect(calls, [Uri.parse('http://server/small')]);
        final images = tester.widgetList<Image>(find.byType(Image));
        expect(images, hasLength(2));
        expect(
          images.every((image) => image.color == KalinkaColors.textSecondary),
          isTrue,
        );
        final rendered = tester.widgetList<RawImage>(find.byType(RawImage));
        expect(rendered, hasLength(2));
        expect(rendered.every((image) => image.image != null), isTrue);
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(SourceBadge),
            matching: find.byType(Container),
          ),
        );
        expect(
          containers.every((container) => container.decoration == null),
          isTrue,
        );
        expect(
          containers.every((container) => container.padding == EdgeInsets.zero),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'minimum artwork height fits attribution and small source tiles',
    (tester) async {
      final icons = ModuleIcons.tryParse({
        'small': {
          'url': '/small',
          'mime_type': 'image/png',
          'min_height': 21,
          'aspect_ratio': 1.1,
        },
        'standard': {
          'url': '/standard',
          'mime_type': 'image/png',
          'min_height': 21,
          'aspect_ratio': 1.1,
        },
      })!;
      expect(icons.small.toJson()['min_height'], 21);
      for (final height in [-1, 65, double.nan, double.infinity]) {
        expect(
          ModuleIconImage.tryParse({
            'url': '/small',
            'mime_type': 'image/png',
            'min_height': height,
          }),
          isNull,
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            urlResolverProvider.overrideWithValue(UrlResolver('http://server')),
            moduleIconCacheProvider.overrideWithValue(
              ModuleIconCache(
                client: MockClient((_) async => http.Response.bytes(_png, 200)),
              ),
            ),
            sourceModulesProvider.overrideWith(
              (ref) => [
                ModuleInfo(
                  name: 'spotify',
                  title: 'Spotify',
                  icons: icons,
                  enabled: true,
                  state: ModuleState.ready,
                ),
                ModuleInfo(
                  name: 'other',
                  title: 'Other',
                  enabled: true,
                  state: ModuleState.ready,
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SourceBadge(
                    entityId: 'kalinka:spotify:track:1',
                    size: SourceBadgeSize.small,
                  ),
                  SourceTile(source: 'spotify', size: 18),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final element in find.byType(ModuleArtwork).evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.height, 21);
        expect(size.width, closeTo(23.1, 0.001));
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final installed in [false, true]) {
    testWidgets(
      'catalog row uses ${installed ? 'installed' : 'catalog'} artwork',
      (tester) async {
        final plugin = CatalogPlugin.fromJson({
          'id': 'example',
          'name': 'Example',
          'description': 'Music source',
          'type': 'input_module',
          'tier': 'official',
          'maturity': 'stable',
          'delivery': 'independent',
          'icons': {
            'small': {
              'url': 'https://catalog.example/icon.svg',
              'mime_type': 'image/svg+xml',
            },
            'standard': {
              'url': 'https://catalog.example/icon.svg',
              'mime_type': 'image/svg+xml',
            },
            'monochrome': true,
          },
        });
        final requests = <Uri>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              urlResolverProvider.overrideWithValue(
                UrlResolver('http://server'),
              ),
              moduleIconCacheProvider.overrideWithValue(
                ModuleIconCache(
                  client: MockClient((request) async {
                    requests.add(request.url);
                    return http.Response('', 404);
                  }),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: PluginRow(
                  plugin: plugin,
                  state: PluginState(
                    live: installed
                        ? ModuleInfo(
                            name: 'example',
                            title: 'Example',
                            icons: _icons,
                            enabled: false,
                            state: ModuleState.disabled,
                          )
                        : null,
                  ),
                  actions: PluginEntryActions(
                    onEnabledChanged: (_) {},
                    onOpenSettings: () {},
                    onOpenAbout: () {},
                    onOperation: (_) {},
                    onDismissFailure: () {},
                    canManage: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(requests, [
          Uri.parse(
            installed
                ? 'http://server/standard'
                : 'https://catalog.example/icon.svg',
          ),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final name in ['Qobuz', 'Tidal', 'Jamendo']) {
    testWidgets('$name artwork follows Home source hover, focus and press', (
      tester,
    ) async {
      final cache = ModuleIconCache(
        client: MockClient((_) async => http.Response.bytes(_png, 200)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            noReceivers,
            connectionStateProvider.overrideWithBuild(
              (ref, notifier) => ConnectionStatus.connected,
            ),
            catalogSourcesProvider.overrideWith(
              (ref) async => [
                (
                  module: ModuleInfo(
                    name: name,
                    title: name,
                    icons: _icons,
                    enabled: true,
                    state: ModuleState.ready,
                  ),
                  root: BrowseItem(
                    id: 'kalinka:$name:root',
                    canBrowse: true,
                    canAdd: false,
                  ),
                ),
              ],
            ),
            urlResolverProvider.overrideWithValue(UrlResolver('http://server')),
            moduleIconCacheProvider.overrideWithValue(cache),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: HomeSourceList(onOpen: (_) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final bytes = await cache.load(
          'http://server/small',
          _icons.small,
          small: true,
        );
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(ModuleArtwork)),
        );
      });
      await tester.pumpAndSettle();
      final button = find.byKey(ValueKey('home-source-$name'));
      Color? color() => tester
          .widget<Image>(
            find.descendant(of: button, matching: find.byType(Image)),
          )
          .color;
      expect(color(), KalinkaColors.textSecondary);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pumpAndSettle();
      expect(color(), KalinkaColors.textPrimary);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(color(), KalinkaColors.textSecondary);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(color(), KalinkaColors.textPrimary);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final touch = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(color(), KalinkaColors.textPrimary);
      await touch.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'source filter artwork stays primary while unselected labels are dim',
    (tester) async {
      final cache = ModuleIconCache(
        client: MockClient((_) async => http.Response.bytes(_png, 200)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            urlResolverProvider.overrideWithValue(UrlResolver('http://server')),
            moduleIconCacheProvider.overrideWithValue(cache),
            sourceModulesProvider.overrideWith(
              (ref) => [
                for (final name in ['qobuz', 'tidal', 'localfiles'])
                  ModuleInfo(
                    name: name,
                    title: name,
                    enabled: true,
                    state: ModuleState.ready,
                    icons: name == 'localfiles' ? null : _icons,
                    icon: name == 'localfiles' ? 'folder_outlined' : null,
                  ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: BrowseFilterForm(
                showSearch: false,
                capabilities: const BrowseFilterCapabilities(
                  source: FacetSupport.supported,
                  sources: [
                    (name: 'qobuz', title: 'Qobuz'),
                    (name: 'tidal', title: 'Tidal'),
                    (name: 'localfiles', title: 'My Library'),
                  ],
                ),
                query: const BrowseFilterQuery(),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final bytes = await cache.load(
          'http://server/standard',
          _icons.standard,
          small: false,
        );
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(ModuleArtwork).first),
        );
      });
      await tester.pumpAndSettle();
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images, hasLength(2));
      expect(
        images.map((image) => image.color),
        everyElement(KalinkaColors.textPrimary),
      );
      final library = find.byWidgetPredicate(
        (widget) => widget is SourceTile && widget.source == 'localfiles',
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: library, matching: find.byType(Icon)),
            )
            .color,
        KalinkaColors.textPrimary,
      );
      for (final title in ['Qobuz', 'Tidal', 'My Library']) {
        expect(
          tester.widget<Text>(find.text(title)).style!.color,
          KalinkaColors.textSecondary,
        );
      }
      expect(
        tester.widget<Text>(find.text('All sources')).style!.color,
        KalinkaColors.textPrimary,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached source badges paint immediately through rebuilds and navigation',
    (tester) async {
      var fetched = 0;
      final cache = ModuleIconCache(
        client: MockClient((_) async {
          fetched++;
          return http.Response.bytes(_png, 200);
        }),
      );
      final version = ValueNotifier(0);
      addTearDown(version.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            urlResolverProvider.overrideWithValue(UrlResolver('http://server')),
            moduleIconCacheProvider.overrideWithValue(cache),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: version,
                builder: (context, v, _) => v == 3
                    ? const SizedBox.shrink()
                    : ModuleArtwork(
                        key: ValueKey(v ~/ 2),
                        icons: ModuleIcons.tryParse(_icons.toJson()),
                        small: true,
                        size: v.isEven ? 20 : 24,
                        inheritIconColor: true,
                        fallback: const Icon(Icons.cast),
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final bytes = await cache.load(
          'http://server/small',
          _icons.small,
          small: true,
        );
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(ModuleArtwork)),
        );
      });
      await tester.pumpAndSettle();
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(image, isNotNull);
      for (final v in [1, 2, 3, 4, 5, 6]) {
        version.value = v;
        // Inspect the first rendered frame, not just the settled result.
        await tester.pump();
        if (v == 3) continue;
        expect(find.byIcon(Icons.cast), findsNothing);
        expect(
          tester
              .widget<RawImage>(find.byType(RawImage))
              .image!
              .isCloneOf(image!),
          isTrue,
        );
        expect(fetched, 1);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable artwork keeps the material fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          urlResolverProvider.overrideWithValue(UrlResolver('http://server')),
          moduleIconCacheProvider.overrideWithValue(
            ModuleIconCache(
              client: MockClient((_) async => http.Response('', 404)),
            ),
          ),
        ],
        child: const MaterialApp(
          home: ModuleArtwork(
            icons: _icons,
            size: 24,
            fallback: Icon(Icons.cast),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cast), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
