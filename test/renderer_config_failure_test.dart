import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';

void main() {
  test(
    'renderer settings distinguish validation from a lost connection',
    () async {
      const unsupported = 'Unsupported REW filter on line 1';
      for (final (status, body, expected) in [
        (422, {'detail': unsupported}, unsupported),
        (422, {'detail': []}, 'The Core rejected these settings.'),
        (409, null, 'That output isn’t connected'),
        (null, null, 'Couldn’t reach that output'),
      ]) {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  response: status == null
                      ? null
                      : Response(
                          requestOptions: options,
                          statusCode: status,
                          data: body,
                        ),
                ),
              ),
            ),
          );
        final api = KalinkaPlayerProxyImpl(client: dio);
        await expectLater(
          api.updateRendererConfig('pi', {'dsp.profile': 'test'}),
          throwsA(predicate((e) => e.toString() == expected)),
        );
        dio.close();
      }
    },
  );
}
