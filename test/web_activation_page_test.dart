import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';

// `flutter build web` copies web/ into build/web as it is, and the pubspec's
// assets under build/web/assets/, which is where the supervisor serves both.
void main() {
  final page = File('web/activate.html').readAsStringSync();
  final sheet = File('web/activate.css').readAsStringSync();
  final index = File('web/index.html').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  String hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
          .toUpperCase();

  bool bundled(String path) {
    if (!path.startsWith('assets/')) return File('web/$path').existsSync();
    final asset = path.substring('assets/'.length);
    final declared = RegExp(
      '^\\s*-\\s*(asset:\\s*)?${RegExp.escape(asset)}\\s*\$',
      multiLine: true,
    );
    return File(asset).existsSync() && declared.hasMatch(pubspec);
  }

  Iterable<String> relativeLinks(String html) =>
      RegExp(r'(?:href|src)="([^"]+)"')
          .allMatches(html)
          .map((m) => m[1]!)
          .where(
            (url) => !url.startsWith(RegExp(r'[/$]')) && !url.contains(':'),
          );

  test('the activation page hands over to Network setup', () {
    expect(
      page,
      contains('<meta http-equiv="refresh" content="1;url=/?setup=network">'),
    );
    expect(page, contains('href="/?setup=network"'));
    expect(page, contains('Set up your Kalinka streamer'));
    expect(page, contains('http://192.168.4.1'));
  });

  test("the activation page keeps to the supervisor's CSP", () {
    expect(page, contains('<link rel="stylesheet" href="activate.css">'));
    expect(page, isNot(contains('<style')));
    expect(page, isNot(contains('style=')));
    expect(page, isNot(contains('<script')));
  });

  test('every file the pages load lands in build/web', () {
    final urls = [
      ...relativeLinks(page),
      ...relativeLinks(index),
      ...RegExp(r'url\("([^"]+)"\)').allMatches(sheet).map((m) => m[1]!),
    ];
    expect(
      urls,
      containsAll([
        'activate.css',
        'assets/assets/images/kalinka_icon.svg',
        'assets/assets/fonts/IBMPlexSans-Regular.ttf',
      ]),
    );
    for (final url in urls) {
      expect(bundled(url), isTrue, reason: url);
    }
  });

  test("the pages are drawn in the app's palette", () {
    final palette = {
      for (final color in [
        KalinkaColors.background,
        KalinkaColors.textPrimary,
        KalinkaColors.textSecondary,
        KalinkaColors.frost,
        KalinkaColors.accent,
        KalinkaColors.accentTint,
      ])
        hex(color),
    };
    final used = RegExp(r'#[0-9A-Fa-f]{3,8}\b')
        .allMatches(sheet)
        .map((m) => m[0]!.toUpperCase())
        .toSet();
    expect(used, contains(hex(KalinkaColors.background)));
    expect(palette, containsAll(used));
    expect(index, contains('background: ${hex(KalinkaColors.background)};'));
    expect(index, contains('"flutter-first-frame"'));
  });
}
