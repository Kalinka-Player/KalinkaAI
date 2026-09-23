import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/log_export.dart';
import '../providers/log_export_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../utils/log_export_saver.dart';
import '../widgets/connection_banner.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/settings_controls/footer_note.dart';
import '../widgets/settings_controls/settings_card.dart';
import '../widgets/settings_controls/settings_enum_pills.dart';
import '../widgets/settings_controls/settings_row.dart';
import '../widgets/settings_controls/settings_toggle.dart';
import '../widgets/settings_controls/warning_note.dart';
import '../widgets/slide_in_panel.dart';

const _periods = {
  '1 hour': Duration(hours: 1),
  '24 hours': Duration(days: 1),
  '7 days': Duration(days: 7),
};

/// "Download server logs": asks the connected server to prepare an archive
/// of its recent logs, then saves it the way this platform saves files.
///
/// Hosted over the settings panel. Leaving it never cancels an export; the
/// server keeps preparing, and the screen picks it up again when reopened.
class LogExportScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;

  /// Chooses where a ready archive goes; the platform's own by default.
  final LogExportSaver Function() saver;

  const LogExportScreen({
    super.key,
    this.onClose,
    this.saver = platformLogExportSaver,
  });

  @override
  ConsumerState<LogExportScreen> createState() => _LogExportScreenState();
}

class _LogExportScreenState extends ConsumerState<LogExportScreen> {
  String _period = '24 hours';
  bool _includeRenderer = false;
  late final LogExportSaver _saver = widget.saver();

  LogExportController get _controller => ref.read(logExportProvider.notifier);

  void _prepare(LogExportStatus status) => _controller.prepare(
    lookback: _periods[_period]!,
    includeLocalRenderer: _includeRenderer && status.offersLocalRenderer,
  );

  Future<void> _save({bool share = false}) async {
    final toasts = ref.read(toastProvider.notifier);
    final outcome = await _controller.save(_saver, share: share);
    final message = switch (outcome) {
      SaveOutcome.saved => 'Logs saved',
      SaveOutcome.started => 'Download started',
      _ => null,
    };
    if (message != null) toasts.show(message, inPanel: true);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(logExportProvider);
    return SlideInPanel(
      onClose: widget.onClose,
      child: Material(
        color: KalinkaColors.background,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(),
              const ConnectionBanner(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 16, bottom: 32),
                  children: [..._notes(view), ..._body(view)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _notes(LogExportView view) => [
    if (view.waitingForServer)
      const WarningNote(
        message: 'Waiting for server…',
        severity: WarningNoteSeverity.warning,
      ),
    if (view.interrupted)
      const WarningNote(
        message: 'The server restarted while it was collecting logs.',
        severity: WarningNoteSeverity.warning,
      ),
    if (view.actionError != null) WarningNote(message: view.actionError!),
  ];

  List<Widget> _body(LogExportView view) {
    if (view.unsupported) {
      return const [
        WarningNote(
          message:
              'This server is too old to export its logs. Upgrade it, or '
              'read them with `journalctl -u kalinka` on the server.',
          severity: WarningNoteSeverity.warning,
        ),
      ];
    }
    final status = view.status;
    if (status == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(KalinkaColors.accent),
            ),
          ),
        ),
      ];
    }
    return [
      switch (status.state) {
        LogExportState.preparing => _preparing(view),
        LogExportState.ready => _ready(view, status),
        LogExportState.none || LogExportState.failed => _options(view, status),
      },
      for (final note in status.warnings)
        if (status.state == LogExportState.ready)
          WarningNote(
            message: note.message,
            severity: WarningNoteSeverity.warning,
          ),
      const FooterNote(
        text:
            'The archive may contain file and track names, listening times, '
            'device names and network addresses. It stays on the server for '
            '30 minutes once ready.',
      ),
    ];
  }

  Widget _options(LogExportView view, LogExportStatus status) {
    final failed = status.state == LogExportState.failed;
    return SettingsCard(
      children: [
        SettingsRow(
          label: 'Period',
          sublabel: 'How far back to collect.',
          isVertical: true,
          control: SettingsEnumPills(
            options: _periods.keys.toList(),
            selected: _period,
            onChanged: (period) => setState(() => _period = period),
          ),
        ),
        if (status.offersLocalRenderer)
          SettingsRow(
            label: 'Include renderer logs from this server',
            sublabel:
                'The renderer installed on the server’s own machine, not '
                'renderers elsewhere or this app.',
            control: SettingsToggle(
              value: _includeRenderer,
              onChanged: (value) => setState(() => _includeRenderer = value),
            ),
          ),
        _Action(
          text: failed ? status.errorMessage : null,
          isError: failed,
          children: [
            KalinkaButton(
              label: failed ? 'Try again' : 'Prepare logs',
              fullWidth: true,
              enabled: !view.busy && !view.waitingForServer,
              onTap: () => _prepare(status),
            ),
          ],
        ),
      ],
    );
  }

  Widget _preparing(LogExportView view) {
    return SettingsCard(
      children: [
        _Action(
          text: 'Collecting logs…',
          progress: const _Progress(value: null),
          children: [
            KalinkaButton(
              label: 'Cancel',
              variant: KalinkaButtonVariant.neutral,
              fullWidth: true,
              enabled: !view.busy,
              onTap: _controller.withdraw,
            ),
          ],
        ),
      ],
    );
  }

  Widget _ready(LogExportView view, LogExportStatus status) {
    final download = status.download!;
    final until = TimeOfDay.fromDateTime(
      download.expiresAt.toLocal(),
    ).format(context);
    final transfer = view.transfer;
    return SettingsCard(
      children: [
        _Action(
          text: transfer == null
              ? 'Ready. Available until $until.'
              : 'Downloading ${formatByteSize(transfer.received)}…',
          progress: transfer == null
              ? null
              : _Progress(value: transfer.fraction),
          children: [
            KalinkaButton(
              label: 'Download ZIP · ${formatByteSize(download.sizeBytes)}',
              fullWidth: true,
              enabled: !view.busy,
              leading: const Icon(
                Icons.download_rounded,
                size: 16,
                color: KalinkaColors.surfaceBase,
              ),
              onTap: _save,
            ),
            if (_saver.canShare)
              KalinkaButton(
                label: 'Share',
                variant: KalinkaButtonVariant.neutral,
                fullWidth: true,
                enabled: !view.busy,
                leading: const Icon(
                  Icons.share_rounded,
                  size: 16,
                  color: KalinkaColors.textPrimary,
                ),
                onTap: () => _save(share: true),
              ),
            KalinkaButton(
              label: 'Discard',
              variant: KalinkaButtonVariant.neutral,
              size: KalinkaButtonSize.compact,
              fullWidth: true,
              enabled: !view.busy,
              onTap: _controller.withdraw,
            ),
          ],
        ),
      ],
    );
  }
}

/// `96 KB`, `1.4 MB` — the size a user reads on a download button.
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: kKalinkaTopBarDecoration,
      child: SizedBox(
        height: kKalinkaTopBarHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, right: 20),
          child: Row(
            children: [
              Semantics(
                label: 'Back',
                button: true,
                child: MouseRegion(
                  cursor: clickCursor(interactive: true),
                  child: GestureDetector(
                    onTap: () => SlideInPanel.closeOf(context),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.arrow_back,
                        size: 22,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Download server logs',
                      style: KalinkaTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'SUPPORT',
                      style: KalinkaTextStyles.sectionHeaderMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line of status, an optional progress bar, and the buttons that act on it.
class _Action extends StatelessWidget {
  final String? text;
  final bool isError;
  final Widget? progress;
  final List<Widget> children;

  const _Action({
    this.text,
    this.isError = false,
    this.progress,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (text != null) ...[
            Text(
              text!,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: isError ? KalinkaColors.statusOffline : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (progress != null) ...[progress!, const SizedBox(height: 12)],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  /// Null for an indeterminate bar.
  final double? value;

  const _Progress({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3,
        backgroundColor: KalinkaColors.borderSubtle,
        valueColor: const AlwaysStoppedAnimation<Color>(KalinkaColors.accent),
      ),
    );
  }
}
