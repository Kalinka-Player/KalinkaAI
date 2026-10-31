import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/queue_section_header.dart';

void main() {
  testWidgets('a short label leaves the format suffix the rest of the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: QueueSectionHeader(
                label: 'NOW PLAYING',
                suffix: 'FLAC 24-bit · 192 kHz',
              ),
            ),
          ),
        ),
      ),
    );
    final paragraphs = tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byType(QueueSectionHeader),
        matching: find.byWidgetPredicate((w) => w is RichText),
      ),
    );
    expect(paragraphs, isNotEmpty);
    for (final p in paragraphs) {
      expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
    }
    expect(find.textContaining('192 kHz'), findsOneWidget);
  });
}
