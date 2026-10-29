import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one thing worth doing about a toast, offered as a button on it.
class ToastAction {
  final String label;
  final VoidCallback onPressed;

  const ToastAction(this.label, this.onPressed);
}

/// A single in-app toast notification.
class ToastEntry {
  final String id;
  final String message;
  final bool isError;

  /// Spinner instead of a status dot, and no auto-dismiss. Used for the shared
  /// queue-activity toast while a request is in flight.
  final bool isLoading;

  /// Render as a compact right-aligned pill rather than a full-width toast.
  final bool compact;

  /// Raised by something that happened inside a panel — shown over the
  /// tablet layout's player pane — so the answer appears there rather
  /// than in the opposite corner of a wide window. Ignored on phone, which
  /// has one place to put a toast.
  final bool inPanel;

  /// A button on the toast. The only part of any toast that takes taps.
  final ToastAction? action;

  /// When true the [_ToastCard] widget plays its exit animation.
  /// The entry is removed from the list ~250 ms after this flips.
  final bool dismissing;

  const ToastEntry({
    required this.id,
    required this.message,
    required this.isError,
    this.isLoading = false,
    this.compact = false,
    this.inPanel = false,
    this.action,
    this.dismissing = false,
  });

  ToastEntry copyWith({
    String? message,
    bool? isError,
    bool? isLoading,
    bool? compact,
    bool? dismissing,
  }) => ToastEntry(
    id: id,
    message: message ?? this.message,
    isError: isError ?? this.isError,
    isLoading: isLoading ?? this.isLoading,
    compact: compact ?? this.compact,
    inPanel: inPanel,
    action: action,
    dismissing: dismissing ?? this.dismissing,
  );
}

class ToastNotifier extends Notifier<List<ToastEntry>> {
  static const _maxToasts = 3;
  static const _animationExtraMs = 250;
  static const _successDisplayMs = 2000;
  static const _errorDisplayMs = 5000;
  static const _actionDisplayMs = 8000;

  final Map<String, Timer> _timers = {};
  String? _trackDeletionToastId;
  final List<String> _deletedTrackTitles = [];
  int _counter = 0;
  bool _isDisposed = false;

  // Shared queue-activity toast: one spinner for all in-flight add/playback
  // requests, kept while _pendingQueueOps > 0, then morphed into the result.
  int _pendingQueueOps = 0;
  String? _queueActivityToastId;

  @override
  List<ToastEntry> build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _trackDeletionToastId = null;
      _deletedTrackTitles.clear();
      _pendingQueueOps = 0;
      _queueActivityToastId = null;
    });
    return [];
  }

  /// Show a toast. Success toasts dismiss after 2 s; error toasts after 5 s;
  /// one with an [action] after 8 s, to leave time to reach it.
  ///
  /// Set [inPanel] when the action was taken inside a pane of the tablet
  /// layout, so the toast lands over the player's pane instead of browsing's
  /// corner.
  void show(
    String message, {
    bool isError = false,
    bool inPanel = false,
    ToastAction? action,
  }) {
    if (_isDisposed) return;
    final id = _appendToast(
      message: message,
      isError: isError,
      inPanel: inPanel,
      action: action,
    );
    final displayMs = action != null
        ? _actionDisplayMs
        : isError
        ? _errorDisplayMs
        : _successDisplayMs;
    _restartDisplayTimer(id, displayMs);
  }

  /// Takes the toast away now, as its display timer would.
  void dismiss(String id) {
    if (_isDisposed || !state.any((e) => e.id == id)) return;
    _timers.remove(id)?.cancel();
    _beginDismiss(id);
  }

  /// Aggregate sequential queue track deletions into a single toast.
  void showTrackRemoved(String title) {
    if (_isDisposed) return;
    _deletedTrackTitles.add(_shortenTitle(title));
    final message = _buildTrackDeletedMessage();

    final activeId = _trackDeletionToastId;
    if (activeId != null && state.any((entry) => entry.id == activeId)) {
      state = [
        for (final entry in state)
          if (entry.id == activeId)
            entry.copyWith(message: message, isError: false, dismissing: false)
          else
            entry,
      ];
      _restartDisplayTimer(activeId, _successDisplayMs);
      return;
    }

    final id = _appendToast(message: message, isError: false);
    _trackDeletionToastId = id;
    _restartDisplayTimer(id, _successDisplayMs);
  }

  /// Begin one add/playback operation: shows the shared spinner, reviving a
  /// still-visible result toast. Must be paired with [endQueueActivity].
  void beginQueueActivity(String message) {
    if (_isDisposed) return;
    _pendingQueueOps++;

    final activeId = _queueActivityToastId;
    if (activeId != null && state.any((e) => e.id == activeId)) {
      // Revive the existing toast as a spinner (handles result → spinner).
      _timers.remove(activeId)?.cancel();
      state = [
        for (final e in state)
          if (e.id == activeId)
            e.copyWith(
              message: message,
              isError: false,
              isLoading: true,
              dismissing: false,
            )
          else
            e,
      ];
      return;
    }

    _queueActivityToastId = _appendToast(
      message: message,
      isError: false,
      isLoading: true,
      compact: true,
    );
  }

  /// Complete one operation: the spinner stays while others are in flight, then
  /// the last to finish morphs it into [message] and auto-dismisses.
  void endQueueActivity(String message, {bool isError = false}) {
    if (_isDisposed) return;
    if (_pendingQueueOps > 0) _pendingQueueOps--;

    final activeId = _queueActivityToastId;
    if (activeId == null || !state.any((e) => e.id == activeId)) {
      // Spinner was evicted — show the result as a fresh toast.
      final id = _appendToast(
        message: message,
        isError: isError,
        compact: true,
      );
      _restartDisplayTimer(id, isError ? _errorDisplayMs : _successDisplayMs);
      return;
    }

    // Still more requests pending — keep the spinner.
    if (_pendingQueueOps > 0) return;

    state = [
      for (final e in state)
        if (e.id == activeId)
          e.copyWith(
            message: message,
            isError: isError,
            isLoading: false,
            dismissing: false,
          )
        else
          e,
    ];
    _restartDisplayTimer(
      activeId,
      isError ? _errorDisplayMs : _successDisplayMs,
    );
  }

  void _beginDismiss(String id) {
    if (_isDisposed) return;
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(dismissing: true) else e,
    ];
    _timers[id] = Timer(const Duration(milliseconds: _animationExtraMs), () {
      if (_isDisposed) return;
      _remove(id);
    });
  }

  void _remove(String id) {
    if (_isDisposed) return;
    _timers.remove(id)?.cancel();
    if (id == _trackDeletionToastId) {
      _trackDeletionToastId = null;
      _deletedTrackTitles.clear();
    }
    if (id == _queueActivityToastId) {
      _queueActivityToastId = null;
    }
    state = state.where((e) => e.id != id).toList();
  }

  String _appendToast({
    required String message,
    required bool isError,
    bool isLoading = false,
    bool compact = false,
    bool inPanel = false,
    ToastAction? action,
  }) {
    if (_isDisposed) return '';
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
    final entry = ToastEntry(
      id: id,
      message: message,
      isError: isError,
      isLoading: isLoading,
      compact: compact,
      inPanel: inPanel,
      action: action,
    );

    var list = [...state, entry];

    if (list.length > _maxToasts) {
      // Evict the oldest non-loading toast so the in-flight spinner survives a
      // burst of others (fall back to oldest if somehow all are spinners).
      final oldestNonLoading = list.indexWhere((t) => !t.isLoading);
      final removeIndex = oldestNonLoading == -1 ? 0 : oldestNonLoading;
      final removed = list[removeIndex];
      list = [
        ...list.sublist(0, removeIndex),
        ...list.sublist(removeIndex + 1),
      ];
      _timers.remove(removed.id)?.cancel();
      if (removed.id == _trackDeletionToastId) {
        _trackDeletionToastId = null;
        _deletedTrackTitles.clear();
      }
      if (removed.id == _queueActivityToastId) {
        _queueActivityToastId = null;
      }
    }

    state = list;
    return id;
  }

  void _restartDisplayTimer(String id, int displayMs) {
    if (_isDisposed || id.isEmpty) return;
    _timers.remove(id)?.cancel();
    _timers[id] = Timer(Duration(milliseconds: displayMs), () {
      if (_isDisposed) return;
      _beginDismiss(id);
    });
  }

  String _buildTrackDeletedMessage() {
    final count = _deletedTrackTitles.length;
    if (count == 0) return 'Track removed';
    if (count == 1) return 'Removed ${_deletedTrackTitles[0]}';
    if (count == 2) {
      return 'Removed ${_deletedTrackTitles[0]}, ${_deletedTrackTitles[1]}';
    }
    final others = count - 2;
    final noun = others == 1 ? 'other' : 'others';
    return 'Removed ${_deletedTrackTitles[0]}, ${_deletedTrackTitles[1]} and $others $noun';
  }

  String _shortenTitle(String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) return 'Untitled';
    if (normalized.length <= 28) return '"$normalized"';
    final shortened = '${normalized.substring(0, 27)}…';
    return '"$shortened"';
  }
}

final toastProvider = NotifierProvider<ToastNotifier, List<ToastEntry>>(
  ToastNotifier.new,
);

/// How far up from the bottom edge toasts sit, so they clear whatever the
/// screen underneath floats there — the mini-player, the search dock.
///
/// Published by the screen that owns that chrome; zero, which suits a screen
/// that docks nothing, until one says otherwise.
class ToastBottomInsetNotifier extends Notifier<double> {
  @override
  double build() => 0;

  void set(double inset) {
    if (state != inset) state = inset;
  }
}

final toastBottomInsetProvider =
    NotifierProvider<ToastBottomInsetNotifier, double>(
      ToastBottomInsetNotifier.new,
    );

extension ConsumerStateToastX<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  void showSafeToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(message, isError: isError);
  }

  /// Runs an add/playback request behind the shared spinner: [pending] while in
  /// flight, then [done]/[failed]. Concurrency-safe, and reports completion even
  /// if the widget is disposed mid-request (the notifier is captured up front).
  Future<void> runQueueActivity<R>({
    required String pending,
    required Future<R> Function() action,
    required String Function(R result) done,
    String Function(Object error)? failed,
  }) async {
    final toast = ref.read(toastProvider.notifier);
    toast.beginQueueActivity(pending);
    try {
      final result = await action();
      toast.endQueueActivity(done(result));
    } catch (e) {
      toast.endQueueActivity(failed?.call(e) ?? 'Failed: $e', isError: true);
    }
  }
}

void showToastIfMounted(
  BuildContext context,
  WidgetRef ref,
  String message, {
  bool isError = false,
}) {
  if (!context.mounted) return;
  ref.read(toastProvider.notifier).show(message, isError: isError);
}
