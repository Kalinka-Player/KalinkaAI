import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/display_settings_provider.dart';

/// Gives [child] this device's chosen 12- or 24-hour clock as
/// [MediaQueryData.alwaysUse24HourFormat], so every time the app formats
/// follows it; with nothing chosen, the platform's preference stands.
class ClockFormatHost extends ConsumerWidget {
  final Widget child;

  const ClockFormatHost({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    // Always wrapped: a first choice must not move, and so remount, the app.
    return MediaQuery(
      data: media.copyWith(
        alwaysUse24HourFormat:
            ref.watch(use24HourClockProvider) ?? media.alwaysUse24HourFormat,
      ),
      child: child,
    );
  }
}
