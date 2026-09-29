import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/data_model.dart';

void main() {
  test('a size sent as an empty string is no image at all', () {
    // What an SDK plugin sends when it only has one size (Spotify).
    final image = AlbumImage.fromJson({
      'small': '',
      'thumbnail': '',
      'large': 'https://i.scdn.co/image/abc',
    });

    expect(image.small, isNull);
    expect(image.thumbnail, isNull);
    expect(image.large, 'https://i.scdn.co/image/abc');
  });
}
