import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/discovery_provider.dart';
import 'package:kalinka/providers/discovery_types.dart';
import 'package:kalinka/widgets/discovery_screen.dart';

/// Discovery that never scans and finds nothing.
class NothingFound extends DiscoveryNotifier {
  @override
  DiscoveryState build() => const DiscoveryState();

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> rescan() async {}
}

/// The server list, faded in, with nothing found on the network.
Future<void> pumpEmptyDiscovery(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [discoveryProvider.overrideWith(NothingFound.new)],
      child: MaterialApp(
        home: Scaffold(body: DiscoveryScreen(onClose: () {})),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}
