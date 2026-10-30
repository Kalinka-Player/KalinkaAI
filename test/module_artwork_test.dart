import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/module_icons.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/module_icon_cache.dart';
import 'package:kalinka/providers/plugin_state.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/module_artwork.dart';
import 'package:kalinka/widgets/plugin_catalog_entry.dart';
import 'package:kalinka/widgets/source_badge.dart';

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
      'wide attribution renders at 18/20 dp without padding, $brightness, text scale $scale',
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
        expect(marks.map((mark) => mark.size), [20 * scale, 18 * scale]);
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
          images.every(
            (image) =>
                image.color ==
                (brightness == Brightness.dark ? Colors.white : Colors.black),
          ),
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
