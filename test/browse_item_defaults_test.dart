import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';

void main() {
  test('album tracks accept unset SDK action defaults', () {
    final list = BrowseItemsList.fromJson({
      'offset': 0,
      'limit': 30,
      'total': 1,
      'items': [
        {
          'id': 'kalinka:tidal:track:11',
          'name': 'A Song',
          'can_add': true,
          'track': {
            'id': 'kalinka:tidal:track:11',
            'title': 'A Song',
            'duration': 200,
            'album': {'id': 'kalinka:tidal:album:10', 'title': 'An Album'},
          },
        },
      ],
    });
    expect(list.items.single.track!.title, 'A Song');
    expect(list.items.single.canBrowse, isFalse);
    expect(list.items.single.canAdd, isTrue);
  });

  test('artist search hits accept omitted can_add', () {
    final item = BrowseItem.fromJson({
      'id': 'kalinka:tidal:artist:7',
      'name': 'An Artist',
      'can_browse': true,
      'artist': {'id': 'kalinka:tidal:artist:7', 'name': 'An Artist'},
    });
    expect(item.canBrowse, isTrue);
    expect(item.canAdd, isFalse);
  });
}
