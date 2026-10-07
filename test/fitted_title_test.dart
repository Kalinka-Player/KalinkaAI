import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/widgets/fitted_title.dart';

const _full = TextStyle(fontSize: 30);
const _width = 300.0;

Future<void> _pump(WidgetTester tester, String text) => tester.pumpWidget(
  MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _width,
        child: FittedTitle(text, style: _full, minFontSize: 12),
      ),
    ),
  ),
);

double _lineHeightAt(double size) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'A',
      style: _full.copyWith(fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final height = painter.preferredLineHeight;
  painter.dispose();
  return height;
}

double _fontSizeOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.fontSize!;

RenderParagraph _paragraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.byType(RichText));

void main() {
  final budget = 2 * _lineHeightAt(30);

  testWidgets('a title that fits keeps its full size', (tester) async {
    await _pump(tester, 'Music');

    expect(_fontSizeOf(tester, 'Music'), 30);
  });

  testWidgets(
    'a long title is set smaller, over more lines, in the same height',
    (tester) async {
      const text = 'Pink Floyd The Dark Side Of The Moon Remastered';
      await _pump(tester, text);

      final size = _fontSizeOf(tester, text);
      final height = tester.getSize(find.byType(FittedTitle)).height;
      expect(size, lessThan(30));
      expect(size, greaterThan(12));
      expect(height, lessThanOrEqualTo(budget));
      expect(height / _lineHeightAt(size), greaterThan(2));
      expect(_paragraph(tester).didExceedMaxLines, isFalse);
    },
  );

  testWidgets('a title too long even at the smallest size is cut short', (
    tester,
  ) async {
    final text = List.filled(40, 'Remastered').join(' ');
    await _pump(tester, text);

    expect(_fontSizeOf(tester, text), closeTo(12, 0.1));
    expect(
      tester.getSize(find.byType(FittedTitle)).height,
      lessThanOrEqualTo(budget),
    );
    expect(_paragraph(tester).didExceedMaxLines, isTrue);
  });
}
