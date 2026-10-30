import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/module_icons.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/module_icon_cache.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/module_artwork.dart';
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
      'wide attribution renders at 10/11 dp, $brightness, text scale $scale',
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
        expect(marks.map((mark) => mark.size), [11 * scale, 10 * scale]);
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
