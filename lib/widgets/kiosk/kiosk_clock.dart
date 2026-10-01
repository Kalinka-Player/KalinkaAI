import 'dart:async';

import 'package:flutter/material.dart';

/// Wall-clock time, rebuilt on each minute boundary rather than on a
/// free-running tick.
class KioskClock extends StatefulWidget {
  final Widget Function(BuildContext context, DateTime now) builder;

  const KioskClock({super.key, required this.builder});

  /// `9:41 PM` or `21:41`, as the platform prefers.
  static String time(BuildContext context, DateTime now) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(now),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  @override
  State<KioskClock> createState() => _KioskClockState();
}

class _KioskClockState extends State<KioskClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
