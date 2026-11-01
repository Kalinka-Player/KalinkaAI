import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/storage.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/storage_volumes_provider.dart';
import 'package:kalinka/widgets/search/drive_folder_actions.dart';
import 'package:kalinka/widgets/struck_icon.dart';

const _stick = StorageVolume(
  id: '3A1F',
  kind: VolumeKind.removable,
  label: 'SANDISK',
  mountPoint: '/media/kalinka/3A1F',
);

LocationLibrary _library({bool holds = false, bool removable = false}) =>
    LocationLibrary(
      module: 'localfiles',
      title: 'My Library',
      holds: holds,
      libraryEmpty: false,
      removable: removable,
      restartRequired: true,
    );

IconButton _libraryButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const ValueKey('drive-library')));

class _Volumes extends StorageVolumesNotifier {
  @override
  Future<List<StorageVolume>> build() async => const [_stick];
}

Future<void> _pump(WidgetTester tester, StorageLocation? location) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageVolumesProvider.overrideWith(_Volumes.new),
        driveLocationProvider.overrideWith((ref, id) async => location),
        demoModeProvider.overrideWithValue(false),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: DriveFolderActions(
            entityId: 'kalinka:drives:catalog:root',
            title: 'Jazz',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a folder the library lacks offers to be added', (tester) async {
    await _pump(
      tester,
      StorageLocation(
        volumeId: '3A1F',
        subpath: 'Jazz',
        path: '/media/kalinka/3A1F/Jazz',
        library: _library(),
      ),
    );

    expect(_libraryButton(tester).isSelected, isFalse);
    expect(_libraryButton(tester).tooltip, 'Add to My Library');
    expect(find.byKey(const ValueKey('drive-eject')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drive-library')));
    await tester.pumpAndSettle();
    expect(find.text('Add “Jazz” to My Library?'), findsOneWidget);
    expect(find.textContaining('The server restarts'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add “Jazz” to My Library?'), findsNothing);
  });

  testWidgets('a folder that is a library source is struck, to take it out', (
    tester,
  ) async {
    await _pump(
      tester,
      StorageLocation(
        volumeId: '3A1F',
        subpath: 'Jazz',
        path: '/x',
        library: _library(holds: true, removable: true),
      ),
    );

    expect(_libraryButton(tester).isSelected, isTrue);
    expect(find.byType(StruckIcon), findsOneWidget);
    expect(_libraryButton(tester).tooltip, 'Remove from My Library');

    await tester.tap(find.byKey(const ValueKey('drive-library')));
    await tester.pumpAndSettle();
    expect(find.text('Remove “Jazz” from My Library?'), findsOneWidget);
    expect(find.textContaining('stop reading it'), findsOneWidget);
  });

  testWidgets('a folder held through one above it cannot be taken out here', (
    tester,
  ) async {
    await _pump(
      tester,
      StorageLocation(
        volumeId: '3A1F',
        subpath: 'Jazz/Kind of Blue',
        path: '/x',
        library: _library(holds: true),
      ),
    );

    expect(_libraryButton(tester).isSelected, isTrue);
    expect(_libraryButton(tester).onPressed, isNull);
    expect(
      _libraryButton(tester).tooltip,
      'In My Library with a folder above it',
    );
  });

  testWidgets('the top of a removable drive can be ejected', (tester) async {
    await _pump(
      tester,
      StorageLocation(
        volumeId: '3A1F',
        path: '/media/kalinka/3A1F',
        library: _library(),
      ),
    );

    expect(find.byKey(const ValueKey('drive-eject')), findsOneWidget);
  });

  testWidgets('a page no library answers for has no drive actions', (
    tester,
  ) async {
    await _pump(
      tester,
      const StorageLocation(volumeId: '3A1F', subpath: 'Jazz', path: '/x'),
    );
    expect(find.byKey(const ValueKey('drive-library')), findsNothing);

    await _pump(tester, null);
    expect(find.byKey(const ValueKey('drive-eject')), findsNothing);
  });
}
