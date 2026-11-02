import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/theme/kalinka_icons.dart';
import 'package:kalinka/widgets/procedural_album_art.dart';
import 'package:kalinka/widgets/search_cards/track_row_support.dart';

BrowseItem _item(String? icon) => BrowseItem(
  id: 'kalinka:drives:track:eA',
  canBrowse: false,
  canAdd: true,
  icon: icon,
);

void main() {
  testWidgets('a row without art draws the icon its source names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final icon in ['track', 'usb_drive', null, 'robot'])
              ArtStandIn(item: _item(icon), size: 44),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byIcon(KalinkaIcons.usbFlashDrive), findsOneWidget);
    // Nothing named, or a name this app does not draw: art made up.
    expect(find.byType(ProceduralAlbumArt), findsNWidgets(2));
  });

  test('a row draws its icon only where it has no art to show', () {
    BrowseItem folder({AlbumImage? cover}) => BrowseItem(
      id: 'kalinka:drives:catalog:folder.eA',
      canBrowse: true,
      canAdd: true,
      icon: 'folder',
      catalog: Catalog(
        id: 'kalinka:drives:catalog:folder.eA',
        title: 'Jazz',
        image: cover,
      ),
    );

    expect(drawsItemIcon(folder()), isTrue);
    expect(
      drawsItemIcon(folder(cover: AlbumImage(small: '/cover.jpg'))),
      isFalse,
    );
    expect(drawsItemIcon(_item('robot')), isFalse);
    expect(drawsItemIcon(_item(null)), isFalse);
  });

  test('the icon comes with the item from the server', () {
    final item = BrowseItem.fromJson({
      'id': 'kalinka:drives:catalog:folder.eA',
      'icon': 'folder',
    });

    expect(item.icon, 'folder');
    expect(BrowseItem.fromJson(item.toJson()).icon, 'folder');
  });
}
