import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_metadata_link.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'IBM Plex Sans',
    )..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))).load();
  });

  for (final (type, label, style) in [
    ('artist', 'U2', KalinkaTextStyles.expandedArtist),
    ('album', 'A', KalinkaTextStyles.expandedAlbum),
  ]) {
    testWidgets('$type link keeps its line height and opens from the chevron', (
      tester,
    ) async {
      final item = BrowseItem(
        id: 'kalinka:localfiles:$type:short',
        name: label,
        canBrowse: true,
        canAdd: false,
      );
      BrowseItem? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: BrowseMetadataLink(
                label: label,
                style: style,
                item: item,
                onOpen: (item) => opened = item,
              ),
            ),
          ),
        ),
      );
      final text = find.text(label);
      expect(tester.widget<Text>(text).style?.decoration, isNull);
      expect(
        tester.getRect(find.byType(BrowseMetadataLink)).height,
        moreOrLessEquals(
          tester.getRect(text).height + 2 * BrowseMetadataLink.verticalPadding,
        ),
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(opened, same(item));
    });
  }
}
