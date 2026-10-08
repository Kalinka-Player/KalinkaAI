import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/restart_provider.dart';
import 'package:kalinka/providers/upgrade_provider.dart';
import 'package:kalinka/widgets/restart_overlay.dart';
import 'package:kalinka/widgets/upgrade_overlay.dart';

import 'support/haptic_recorder.dart';

class _Restart extends RestartNotifier {
  @override
  RestartState build() =>
      const RestartState(isRestarting: true, currentStep: RestartStep.saving);

  void emit(RestartState next) => state = next;
}

class _Upgrade extends UpgradeNotifier {
  @override
  UpgradeState build() => const UpgradeState(
    isUpgrading: true,
    currentStep: UpgradeStep.installing,
  );

  void emit(UpgradeState next) => state = next;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget overlay,
) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: overlay),
    ),
  );
}

void main() {
  testWidgets('a restart signals success once, at the end, not per step', (
    tester,
  ) async {
    final haptics = HapticRecorder.install();
    final container = ProviderContainer(
      overrides: [restartProvider.overrideWith(_Restart.new)],
    );
    await _pump(tester, container, RestartOverlay(onDismiss: () {}));
    final restart = container.read(restartProvider.notifier) as _Restart;

    final completed = <RestartStep>{};
    for (final step in RestartStep.values) {
      completed.add(step);
      restart.emit(
        RestartState(
          isRestarting: true,
          currentStep: step,
          completedSteps: {...completed},
        ),
      );
      await tester.pump();
    }
    expect(haptics.calls, isEmpty);

    restart.emit(
      RestartState(isRestarting: true, isDone: true, completedSteps: completed),
    );
    await tester.pump();
    expect(haptics.calls, ['successNotification']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an upgrade signals success once, at the end, not per step', (
    tester,
  ) async {
    final haptics = HapticRecorder.install();
    final container = ProviderContainer(
      overrides: [upgradeProvider.overrideWith(_Upgrade.new)],
    );
    await _pump(tester, container, UpgradeOverlay(onDismiss: () {}));
    final upgrade = container.read(upgradeProvider.notifier) as _Upgrade;

    upgrade.emit(
      const UpgradeState(
        isUpgrading: true,
        currentStep: UpgradeStep.reconnecting,
        completedSteps: {UpgradeStep.installing},
      ),
    );
    await tester.pump();
    expect(haptics.calls, isEmpty);

    upgrade.emit(
      const UpgradeState(
        isUpgrading: true,
        isDone: true,
        completedSteps: {UpgradeStep.installing, UpgradeStep.reconnecting},
      ),
    );
    await tester.pump();
    expect(haptics.calls, ['successNotification']);
    await tester.pump(const Duration(seconds: 3));
  });
}
