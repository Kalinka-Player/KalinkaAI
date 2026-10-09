import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/server_refusal.dart';

import 'support/queue_server.dart';

const _ids = ['kalinka:x:track:b', 'kalinka:x:album:a'];

void main() {
  test('a server with the route replaces the queue in one request', () async {
    final server = QueueServer(200, {'message': 'Queue replaced', 'count': 3});

    final replaced = await server.api().replace(_ids);

    expect(server.requests, ['POST /queue/replace']);
    expect(server.bodies['POST /queue/replace'], _ids);
    expect(replaced.count, 3);
  });

  test('a refused replacement is not followed by a clear', () async {
    final server = QueueServer(409, {
      'detail': {'code': 'demo_queue_full', 'message': 'The queue is full.'},
    });

    await expectLater(
      server.api().replace(_ids),
      throwsA(
        isA<ServerRefusalException>().having(
          (e) => '$e',
          'text',
          'The queue is full.',
        ),
      ),
    );
    expect(server.requests, ['POST /queue/replace']);
  });

  test(
    'a replacement that comes to no tracks reads as the server put it',
    () async {
      final server = QueueServer(422, {
        'detail': {'code': 'no_tracks', 'message': 'There are no tracks here.'},
      });

      await expectLater(
        server.api().replace(_ids),
        throwsA(
          isA<ServerRefusalException>().having(
            (e) => '$e',
            'text',
            'There are no tracks here.',
          ),
        ),
      );
      expect(server.requests, ['POST /queue/replace']);
    },
  );

  for (final (status, body, kind) in olderServers) {
    test('an older server $kind gets a clear then an add', () async {
      final server = QueueServer(status, body);

      final added = await server.api().replace(_ids);

      expect(server.requests, [
        'POST /queue/replace',
        'PUT /queue/clear',
        'POST /queue/add',
      ]);
      expect(server.bodies['POST /queue/add'], _ids);
      expect(added.count, QueueServer.count);
    });
  }

  test('a 404 the route gave for a missing source clears nothing', () async {
    final server = QueueServer(404, {'detail': "Source 'x' is not available"});

    await expectLater(server.api().replace(_ids), throwsA(isA<DioException>()));
    expect(server.requests, ['POST /queue/replace']);
  });
}
