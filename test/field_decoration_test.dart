import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/theme/field_decoration.dart';

import 'support/field_text.dart';

void main() {
  test('a field draws in primary text, dimmed while it is off', () {
    final on = kalinkaFieldText().resolve(const {});
    final off = kalinkaFieldText().resolve(const {WidgetState.disabled});
    expect(on.color, KalinkaColors.textPrimary);
    expect(on.fontFamily, KalinkaFonts.sansFamily);
    expect(on.fontSize, kalinkaFieldTextStyle.fontSize);
    expect(off.color, KalinkaColors.textPrimary.withValues(alpha: 0.38));
    expect(off.fontSize, on.fontSize);
  });

  test('a field keeps the face it asks for', () {
    final style = kalinkaFieldText(
      KalinkaTextStyles.textFieldInput.copyWith(color: KalinkaColors.accent),
    ).resolve(const {});
    expect(style.fontFamily, KalinkaFonts.monoFamily);
    expect(style.fontSize, KalinkaTextStyles.textFieldInput.fontSize);
    expect(style.color, KalinkaColors.textPrimary);
  });

  testWidgets('a disabled TextField takes the dimmed colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const ValueKey('on'),
                style: kalinkaFieldText(),
                decoration: kalinkaFieldDecoration(hint: 'On'),
              ),
              TextField(
                key: const ValueKey('off'),
                enabled: false,
                style: kalinkaFieldText(),
                decoration: kalinkaFieldDecoration(hint: 'Off'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      fieldTextColor(tester, find.byKey(const ValueKey('on'))),
      KalinkaColors.textPrimary,
    );
    expect(
      fieldTextColor(tester, find.byKey(const ValueKey('off'))),
      KalinkaColors.textPrimary.withValues(alpha: 0.38),
    );
  });
}
