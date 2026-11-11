import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/data_model/renderer_config_adapter.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/configuration_appearance.dart';
import 'package:kalinka/widgets/expert_field_list.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/settings_controls/settings_binding.dart';
import 'package:kalinka/widgets/settings_controls/settings_card.dart';
import 'package:kalinka/widgets/settings_controls/settings_help_button.dart';
import 'package:kalinka/widgets/settings_controls/settings_row.dart';
import 'package:kalinka/widgets/settings_renderer.dart';

const _details =
    'A larger buffer can help with an unreliable connection, '
    'but uses more memory.';
const _field = FieldSpec(
  path: 'buffers.network_stream',
  label: 'Network buffer',
  widget: WidgetKind.numberSlider,
  type: 'int',
  defaultValue: 50,
  help: 'Memory used to buffer streamed audio.',
  helpDetails: _details,
);

class _Binding implements SettingsBinding {
  final staged = <String, dynamic>{};
  @override
  dynamic effectiveValue(String path) => staged[path];
  @override
  bool isStaged(String path) => staged.containsKey(path);
  @override
  bool hasHiddenSecret(String path) => false;
  @override
  List<ConfigIssue> issuesFor(String path) => [];
  @override
  List<OptionSpec>? optionsFor(String path) => null;
  @override
  Future<void> refreshOptions() async {}
  @override
  void stage(String path, dynamic value) => staged[path] = value;
}

Widget _app(
  Widget child, {
  double scale = 1,
  bool reducedMotion = false,
  GlobalKey? captureKey,
}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion,
      ),
      child: RepaintBoundary(key: captureKey, child: child!),
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final captures = Platform.environment['KALINKA_REVIEW_DIR'];
  setUpAll(() async {
    if (captures == null) return;
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Sans', 'IBMPlexSans-SemiBold.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });

  test('module and renderer fields preserve optional detailed help', () {
    for (final details in [null, '', _details]) {
      final module = FieldSpec.fromJson({
        'path': 'scan_interval',
        'label': 'Scan interval',
        'widget': 'number_input',
        'type': 'int',
        'help': 'Minutes between scans.',
        'help_details': ?details,
      });
      expect(module.helpDetails, details);
      expect(module.help, 'Minutes between scans.');
      final renderer = RendererConfigSnapshot.fromJson({
        'sections': [
          {
            'path': 'output',
            'fields': [
              {
                'path': 'output.device',
                'title': 'Output device',
                'type': 'enum',
                'description': 'Choose a sound card.',
                'help_details': ?details,
              },
            ],
          },
        ],
      });
      final view = adaptRendererConfig(renderer);
      expect(view.sections.single.fields.single.helpDetails, details);
      expect(view.expertFields.single.helpDetails, details);
      expect(view.expertFields.single.help, 'Choose a sound card.');
    }
  });

  testWidgets('absent and blank details have no info button', (tester) async {
    for (final details in [null, '', '  ']) {
      await tester.pumpWidget(
        _app(
          SettingsRow(
            label: 'Buffer',
            helpDetails: details,
            control: const SizedBox(),
          ),
        ),
      );
      expect(find.byType(SettingsHelpButton), findsNothing);
    }
  });

  testWidgets('keyboard opens help and returns focus after closing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SettingsRow(
          label: 'Network buffer',
          helpDetails: _details,
          control: const SizedBox(),
        ),
      ),
    );
    final info = find.byTooltip('About Network buffer');
    expect(tester.getSize(info), const Size(48, 48));
    final button = tester.widget<IconButton>(find.byType(IconButton));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(button.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(KalinkaDialog), findsOneWidget);
    expect(find.text(_details, findRichText: true), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(KalinkaDialog), findsNothing);
    expect(button.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(KalinkaDialog), findsNothing);
    expect(button.focusNode!.hasFocus, isTrue);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'pointer dismissal clears focus (reduced motion: $reducedMotion)',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const SettingsRow(
              label: 'Network buffer',
              helpDetails: _details,
              control: SizedBox(),
            ),
            reducedMotion: reducedMotion,
          ),
        );
        final info = find.byTooltip('About Network buffer');
        final button = tester.widget<IconButton>(find.byType(IconButton));
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer();
        addTearDown(mouse.removePointer);
        Future<void> click(Finder target) async {
          await mouse.moveTo(tester.getCenter(target));
          await mouse.down(tester.getCenter(target));
          await mouse.up();
          await tester.pumpAndSettle();
        }

        await click(info);
        expect(button.focusNode!.hasFocus, isFalse);
        await click(find.text('Close'));
        expect(button.focusNode!.hasFocus, isFalse);

        await click(info);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(button.focusNode!.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await mouse.down(const Offset(2, 2));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.byType(KalinkaDialog), findsNothing);
        expect(button.focusNode!.hasFocus, isFalse);
      },
    );
  }

  testWidgets(
    'hover and press do not paint a background around the info icon',
    (tester) async {
      final surface = GlobalKey();
      await tester.pumpWidget(
        _app(
          Center(
            child: RepaintBoundary(
              key: surface,
              child: const ColoredBox(
                color: KalinkaColors.surfaceRaised,
                child: SettingsHelpButton(
                  label: 'Network buffer',
                  details: _details,
                ),
              ),
            ),
          ),
        ),
      );
      final info = find.byType(SettingsHelpButton);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      Future<void> expectNoFill() async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (surface.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (24 * image.width + 6) * 4;
          final pixel = Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
          image.dispose();
          expect(pixel, KalinkaColors.surfaceRaised);
        });
      }

      await mouse.moveTo(tester.getCenter(info));
      await expectNoFill();
      await mouse.down(tester.getCenter(info));
      await expectNoFill();
      await mouse.cancel();
    },
  );

  testWidgets('section captions stay with the heading and clear the card', (
    tester,
  ) async {
    final view = adaptRendererConfig(
      RendererConfigSnapshot.fromJson({
        'sections': [
          {
            'path': 'buffers',
            'title': 'Buffering',
            'description': 'Audio held in memory during playback.',
            'fields': [
              {
                'path': 'buffers.network_stream',
                'title': 'Network buffer',
                'type': 'int',
                'value': '64000',
                'help_details': _details,
              },
            ],
          },
        ],
      }),
    );
    expect(view.sections.single.banners, isEmpty);
    await tester.pumpWidget(
      _app(
        ConfigurationAppearance(
          child: SettingsScope(
            binding: _Binding(),
            child: SchemaSectionRenderer(
              section: view.sections.single,
              isTopLevel: true,
            ),
          ),
        ),
      ),
    );
    final label = tester.getRect(find.text('BUFFERING'));
    final caption = tester.getRect(
      find.text('Audio held in memory during playback.', findRichText: true),
    );
    final card = tester.getRect(
      find
          .descendant(
            of: find.byType(SettingsCard),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(caption.top - label.bottom, 4);
    expect(card.top - caption.bottom, 10);
    expect(caption.left, label.left);
    expect(card.left, label.left);
  });

  testWidgets('nested feature keeps requirements beside its switch', (
    tester,
  ) async {
    final binding = _Binding();
    await tester.pumpWidget(
      _app(
        SettingsScope(
          binding: binding,
          child: const SchemaSectionRenderer(
            section: SectionSpec(
              id: 'ai_search',
              title: 'AI search',
              fields: [
                FieldSpec(
                  path: 'ai_search.enabled',
                  label: 'Enable AI search',
                  widget: WidgetKind.toggle,
                  type: 'bool',
                  defaultValue: false,
                  help: 'Needs about 500 MB of memory.',
                  helpDetails: _details,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Needs about 500 MB of memory.', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('About Enable AI search'));
    await tester.pumpAndSettle();
    expect(find.text('Enable AI search'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(binding.staged, isEmpty);
  });

  for (final mode in ['regular', 'slider', 'expert', 'readonly']) {
    testWidgets('$mode settings expose help without staging a change', (
      tester,
    ) async {
      final binding = _Binding()..staged[_field.path] = 70;
      Widget content = mode == 'expert'
          ? ExpertFieldList(fields: const [_field], binding: binding)
          : SingleChildScrollView(
              child: SchemaFieldRenderer(
                field: mode == 'readonly'
                    ? const FieldSpec(
                        path: 'core.output.replaygain',
                        label: 'ReplayGain',
                        widget: WidgetKind.text,
                        type: 'str',
                        readonly: true,
                        defaultValue: 'Disabled',
                        helpDetails: _details,
                      )
                    : _field,
              ),
            );
      if (mode == 'regular') content = ConfigurationAppearance(child: content);
      await tester.pumpWidget(
        _app(SettingsScope(binding: binding, child: content)),
      );
      expect(find.byType(SettingsHelpButton), findsOneWidget);
      await tester.tap(find.byType(SettingsHelpButton));
      await tester.pumpAndSettle();
      expect(find.text(_details, findRichText: true), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(binding.staged, {_field.path: 70});
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size, scale) in [
    ('phone', const Size(375, 812), 1.0),
    ('narrow', const Size(320, 640), 2.0),
    ('landscape', const Size(812, 375), 2.0),
    ('tablet', const Size(1000, 800), 3.0),
  ]) {
    testWidgets('$name help remains readable with reduced motion', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final captureKey = GlobalKey();
      final binding = _Binding();
      await tester.pumpWidget(
        _app(
          ConfigurationAppearance(
            child: SettingsScope(
              binding: binding,
              child: const SingleChildScrollView(
                child: SchemaSectionRenderer(
                  isTopLevel: true,
                  section: SectionSpec(
                    id: 'buffers',
                    title: 'Buffering',
                    help: 'Audio held in memory during playback.',
                    fields: [_field],
                  ),
                ),
              ),
            ),
          ),
          scale: scale,
          reducedMotion: true,
          captureKey: captureKey,
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String suffix) async {
        if (captures == null) return;
        await tester.runAsync(() async {
          final image =
              await (captureKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/settings-help-$name-$suffix.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('row');
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer();
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(SettingsHelpButton)));
      await tester.pumpAndSettle();
      await capture('hover');
      await tester.tap(find.byType(SettingsHelpButton));
      await tester.pumpAndSettle();
      expect(find.text(_details, findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('popup');
      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(KalinkaDialog), findsNothing);
      expect(binding.staged, isEmpty);
      expect(tester.takeException(), isNull);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pumpAndSettle();
      await capture('closed');
    });
  }
}
