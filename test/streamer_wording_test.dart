import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';

import 'support/discovery_fakes.dart';

final _box = RegExp(r'\bbox(es)?\b', caseSensitive: false);
final _wordChar = RegExp(r'[\w$]');

/// The text of each string literal in [source], by the offset it starts at.
/// Comments are left out, and an interpolation reads as a space; a literal
/// inside one is a literal of its own.
Map<int, String> stringLiterals(String source) {
  final found = <int, String>{};
  var i = 0;
  bool at(String s) => source.startsWith(s, i);
  bool word(int j) => j >= 0 && _wordChar.hasMatch(source[j]);

  void comment() {
    if (at('//')) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      return;
    }
    var depth = 0;
    do {
      if (at('/*')) {
        depth++;
        i += 2;
      } else if (at('*/')) {
        depth--;
        i += 2;
      } else {
        i++;
      }
    } while (depth > 0 && i < source.length);
  }

  late final void Function({bool nested}) code;

  void literal() {
    final start = i;
    final raw = i > 0 && source[i - 1] == 'r' && !word(i - 2);
    final quote = at("'''") || at('"""')
        ? source.substring(i, i + 3)
        : source[i];
    i += quote.length;
    final text = StringBuffer();
    while (i < source.length && !at(quote)) {
      if (!raw && at(r'\')) {
        text.write(' ');
        i += 2;
      } else if (!raw && at(r'${')) {
        text.write(' ');
        i += 2;
        code(nested: true);
      } else if (!raw && at(r'$')) {
        text.write(' ');
        i++;
        while (i < source.length && word(i)) {
          i++;
        }
      } else {
        text.write(source[i++]);
      }
    }
    i += quote.length;
    found[start] = text.toString();
  }

  code = ({bool nested = false}) {
    var depth = 0;
    while (i < source.length) {
      if (at('//') || at('/*')) {
        comment();
      } else if (at("'") || at('"')) {
        literal();
      } else if (at('{')) {
        depth++;
        i++;
      } else if (at('}')) {
        i++;
        if (nested && depth == 0) return;
        depth--;
      } else {
        i++;
      }
    }
  };

  code();
  return found;
}

void main() {
  test('reads literals, not comments or the code they interpolate', () {
    const source = r'''
// the box
/* a /* nested */ box */
final a = 'The ${box.noun} is back, $box';
final b = "Connect ${name ?? 'your box'} now";
final c = r'raw box $x';
final d = """
a box""";
final e = 'Kalinka\'s box';
''';
    expect(stringLiterals(source).values.where(_box.hasMatch), [
      'your box',
      r'raw box $x',
      '\na box',
      'Kalinka s box',
    ]);
  });

  test('no string in the app calls the device a box', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final literals = stringLiterals(source);
      for (final MapEntry(key: offset, value: text) in literals.entries) {
        if (!_box.hasMatch(text)) continue;
        final line = '\n'.allMatches(source.substring(0, offset)).length + 1;
        found.add('${file.path}:$line: $text');
      }
    }
    expect(found, isEmpty);
  });

  test('the Bluetooth permission prompt calls it a streamer', () {
    for (final path in ['ios/Runner/Info.plist', 'macos/Runner/Info.plist']) {
      final prompt = RegExp(
        r'<key>NSBluetoothAlwaysUsageDescription</key>\s*<string>([^<]*)<',
      ).firstMatch(File(path).readAsStringSync())?.group(1);
      expect(
        prompt,
        'Connect a nearby Kalinka streamer to your Wi-Fi.',
        reason: path,
      );
    }
  });

  group('the server list', () {
    setUpAll(() async {
      for (final (family, file) in [
        (KalinkaFonts.monoFamily, 'IBMPlexMono-SemiBold.ttf'),
        (KalinkaFonts.sansFamily, 'IBMPlexSans-Regular.ttf'),
      ]) {
        await (FontLoader(
          family,
        )..addFont(rootBundle.load('assets/fonts/$file'))).load();
      }
    });

    for (final (width, textScale, oneLine) in [
      (320.0, 1.0, true),
      (360.0, 1.0, true),
      (320.0, 2.0, false),
    ]) {
      testWidgets(
        'offers to set up a streamer at ${width}dp and ${textScale}x text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpEmptyDiscovery(tester);

          final finder = find.text('SET UP A STREAMER');
          final label = tester.renderObject<RenderParagraph>(finder);
          final shown = tester.getRect(finder).width / label.size.width;
          expect(shown, greaterThanOrEqualTo(0.9));
          expect(
            label.size.width >= label.getMaxIntrinsicWidth(double.infinity),
            oneLine,
          );
          expect(find.text('Cancel'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
