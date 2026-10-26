import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/widgets/search/library_activity.dart';

class _Api implements KalinkaPlayerProxy {
  final IndexerStatus status;

  _Api(this.status);

  @override
  Future<IndexerStatus> getIndexerStatus({List<String>? sources}) async =>
      status;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Fixed extends IndexerStatusNotifier {
  final IndexerStatusState fixed;

  _Fixed(this.fixed);

  @override
  IndexerStatusState build() => fixed;
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

void main() {
  test('stages group as the listener reads them', () async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'server.test',
      'Kalinka.port': 8000,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(
          _Api(
            IndexerStatus.fromJson({
              'localfiles': {
                'indexing': {'total': 0, 'scanning': true, 'available': true},
                'enrichment': {'total': 100, 'done': 100},
                'clap_audio': {'total': 50, 'done': 10, 'pending': 40},
                'clap_text': {'total': 50, 'done': 50},
              },
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(indexerStatusProvider.notifier).refresh();
    final stages = container.read(indexerStatusProvider).stages;
    expect([for (final s in stages) s.stage], IndexerDisplayStage.values);
    expect([for (final s in stages) s.active], [true, false, true]);
    expect([for (final s in stages) s.progressPct], [null, null, 60]);
    expect(container.read(indexerStatusProvider).caption, 'Finding music…');
  });

  Future<void> pump(WidgetTester tester, IndexerStatusState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          indexerStatusProvider.overrideWith(() => _Fixed(state)),
          connectionStateProvider.overrideWith(_Connected.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Column(children: [LibraryActivityLine()]),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Details lists each stage', (tester) async {
    await pump(
      tester,
      const IndexerStatusState(
        stages: [
          IndexerStageProgress(IndexerDisplayStage.findingMusic),
          IndexerStageProgress(
            IndexerDisplayStage.enrichment,
            active: true,
            progressPct: 68,
          ),
          IndexerStageProgress(
            IndexerDisplayStage.smartSearch,
            active: true,
            progressPct: 41,
          ),
        ],
      ),
    );
    expect(find.text('Updating library'), findsOneWidget);
    expect(find.text('Library activity'), findsNothing);
    await tester.tap(find.text('Updating library'));
    await tester.pump();
    expect(find.text('Library activity'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('41%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tapAt(const Offset(4, 590));
    await tester.pump();
    expect(find.text('Library activity'), findsNothing);
  });

  testWidgets('the ring asks for a frame per step, not per vsync', (
    tester,
  ) async {
    await pump(
      tester,
      const IndexerStatusState(
        stages: [
          IndexerStageProgress(IndexerDisplayStage.findingMusic, active: true),
        ],
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('an idle pipeline shows nothing', (tester) async {
    await pump(
      tester,
      const IndexerStatusState(
        stages: [IndexerStageProgress(IndexerDisplayStage.findingMusic)],
      ),
    );
    expect(find.text('Updating library'), findsNothing);
  });
}
