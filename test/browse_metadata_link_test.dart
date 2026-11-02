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
    testWidgets('short $type names keep a 48dp tappable target', (
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
      final target = tester.getRect(find.byType(InkWell));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
      await tester.tapAt(target.bottomRight - const Offset(1, 1));
      expect(opened, same(item));
    });
  }
}
