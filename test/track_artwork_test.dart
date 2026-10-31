import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';

Map<String, dynamic> _json({Map<String, dynamic>? image}) => {
  'id': 'localfiles:track:t1',
  'title': 'Stagger Lee',
  'duration': 315,
  'album': {
    'id': 'localfiles:album:a1',
    'title': 'Murder Ballads',
    'image': {'small': '/album_small.jpg', 'large': '/album_large.jpg'},
  },
  'image': ?image,
};

void main() {
  test('a track shows its own cover where the server sends one', () {
    final track = Track.fromJson(
      _json(image: {'small': '/track_small.jpg', 'large': '/track_large.jpg'}),
    );

    expect(track.artwork?.small, '/track_small.jpg');
    expect(track.album?.image?.small, '/album_small.jpg');
  });

  test('a track from an older server shows its album cover', () {
    final track = Track.fromJson(_json());

    expect(track.image, isNull);
    expect(track.artwork?.large, '/album_large.jpg');
  });

  test('an image with no size of its own stands aside for the album', () {
    final track = Track.fromJson(
      _json(image: {'small': '', 'thumbnail': '', 'large': ''}),
    );

    expect(track.artwork?.largest, '/album_large.jpg');
  });

  test('the album fills the sizes its own cover lacks', () {
    final track = Track.fromJson(
      _json(image: {'thumbnail': '/track_thumb.jpg'}),
    );

    expect(track.artwork?.thumbnail, '/track_thumb.jpg');
    expect(track.artwork?.small, '/album_small.jpg');
    expect(track.artwork?.large, '/album_large.jpg');
  });

  test('its own cover survives a round trip and a copy', () {
    final track = Track.fromJson(_json(image: {'large': '/track_large.jpg'}));

    final again = Track.fromJson(track.toJson());
    final copied = track.copyWith(unavailable: true);

    expect(again.artwork?.large, '/track_large.jpg');
    expect(copied.artwork?.large, '/track_large.jpg');
  });

  test('a listed track shows its own cover', () {
    final item = BrowseItem(
      id: 'localfiles:track:t1',
      canBrowse: false,
      canAdd: true,
      track: Track.fromJson(_json(image: {'small': '/track_small.jpg'})),
    );

    expect(item.image?.small, '/track_small.jpg');
  });
}
