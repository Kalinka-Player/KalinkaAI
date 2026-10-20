import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data_model/data_model.dart' show ModuleState;
import '../data_model/plugin_catalog.dart';
import '../providers/plugin_catalog_provider.dart'
    show PluginFailure, PluginOperation;
import '../providers/plugin_state.dart';
import '../theme/app_theme.dart';
import '../utils/schema_icons.dart';
import 'configuration_appearance.dart';
import 'settings_controls/module_header_row.dart';
import 'kalinka_button.dart';
import 'settings_controls/settings_toggle.dart';
import 'settings_controls/inline_markdown.dart';

// Share settings typography; the catalog owns layout, not a separate type scale.
InputDecoration catalogSearchDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: KalinkaTextStyles.searchPlaceholder.copyWith(
    fontSize: KalinkaTypography.baseSize + 2,
    color: KalinkaColors.textSecondary,
  ),
  prefixIcon: const Icon(
    Icons.search,
    size: 20,
    color: KalinkaColors.textMuted,
  ),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
  filled: true,
  fillColor: KalinkaColors.surfaceInput,
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: KalinkaColors.borderDefault),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: KalinkaColors.accent),
  ),
);

/// What the overview and a plugin's pages do for it: open its pages, switch
/// it on or off, and the server's install, uninstall and update.
class PluginEntryActions {
  /// Stages its switch, where the settings schema has one.
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;
  final ValueChanged<PluginOperation> onOperation;

  /// Puts away what went wrong with its last install, removal or update.
  final VoidCallback onDismissFailure;

  /// The server installs, removes and updates plugins itself.
  final bool canManage;

  const PluginEntryActions({
    required this.onEnabledChanged,
    required this.onOpenSettings,
    required this.onOpenAbout,
    required this.onOperation,
    required this.onDismissFailure,
    required this.canManage,
  });
}

/// The icon its module declares, else one for what it is.
IconData pluginIcon(CatalogPlugin plugin, PluginState state) =>
    iconNamed(state.live?.icon) ??
    switch (plugin.id) {
      'localfiles' => Icons.folder_outlined,
      'qobuz' => Icons.headphones_outlined,
      'spotify' => Icons.speaker_phone_outlined,
      'upnp' => Icons.cast,
      _ => plugin.isDevice ? Icons.speaker_outlined : Icons.music_note_outlined,
    };

/// A plugin's state as Server settings words it — READY and the rest — or
/// what the server is busy doing to it. Null for a plugin it lacks, unless
/// [notInstalled] asks for that to be said too.
ModuleStatusBadge? pluginBadge(PluginState state, {bool notInstalled = false}) {
  const key = ValueKey('plugin-badge');
  if (state.operation case final operation?) {
    return ModuleStatusBadge(
      key: key,
      inline: true,
      label: switch (operation) {
        PluginOperation.install => 'INSTALLING',
        PluginOperation.uninstall => 'UNINSTALLING',
        PluginOperation.update => 'UPDATING',
      },
      color: KalinkaColors.statusPending,
    );
  }
  final live = state.live;
  if (live == null) {
    return notInstalled
        ? const ModuleStatusBadge(
            key: key,
            inline: true,
            label: 'NOT INSTALLED',
            color: KalinkaColors.textMuted,
          )
        : null;
  }
  // As it runs now; a switch waiting on the restart says so beside it.
  return ModuleStatusBadge.of(
    key: key,
    inline: true,
    !state.savedEnabled
        ? ModuleStatus.disabled
        : switch (live.state) {
            ModuleState.ready => ModuleStatus.ready,
            ModuleState.warning => ModuleStatus.warning,
            ModuleState.error => ModuleStatus.error,
            ModuleState.disabled => ModuleStatus.disabled,
          },
  );
}

/// A plugin's row on the overview, ruled off below, all of it one way in:
/// an installed plugin's opens its configuration page, any other's its About
/// page, with Add or Update before the chevron.
class PluginRow extends StatelessWidget {
  final CatalogPlugin plugin;
  final PluginState state;
  final String? summary;

  final PluginEntryActions actions;

  const PluginRow({
    super.key,
    required this.plugin,
    required this.state,
    required this.actions,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final installed = state.installed;
    final primary = _primaryFor(plugin, state, actions.canManage, brief: true);
    final badge = pluginBadge(state);
    // Group headings distinguish added plugins; rows explain any restrictions.
    final detail = installed || state.operation != null
        ? state.detail
        : plugin.bundled
        ? 'Included with Kalinka Player'
        : actions.canManage
        ? primary?.reason
        : null;
    final badges = [
      if (plugin.unofficial) const _Badge('Unofficial'),
      if (plugin.maturity == 'experimental')
        const _Badge('Experimental', warm: true),
      if (plugin.maturity == 'deprecated') const _Badge('Deprecated'),
    ];
    final open = installed ? actions.onOpenSettings : actions.onOpenAbout;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationItemIcon(icon: pluginIcon(plugin, state)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(plugin.name, style: KalinkaTextStyles.trayRowLabel),
                  ?badge,
                ],
              ),
              if (summary != null && summary!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  summary!,
                  key: const ValueKey('plugin-summary'),
                  style: KalinkaTextStyles.trayRowSublabel,
                  softWrap: true,
                ),
              ],
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: badges),
              ],
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _StatusLine(
                    badge: null,
                    detail: detail,
                    detailColor: state.hasPendingChanges || state.staged
                        ? KalinkaColors.statusPendingLight
                        : installed || state.operation != null
                        ? KalinkaColors.textSecondary
                        : KalinkaColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KalinkaColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The row's own node, with Add inside it as a button of its
          // own.
          Semantics(
            key: ValueKey('plugin-${plugin.id}'),
            container: true,
            button: true,
            label: [
              plugin.name,
              for (final badge in badges) badge.label,
              if (badge != null) _spoken(badge.label),
              ?detail,
            ].map(_unstopped).join('. '),
            hint: installed ? 'Opens its settings' : 'Opens About',
            value: summary,
            onTap: open,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: open,
              excludeFromSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Beside the text where both fit; under it on a narrow
                    // phone or at large text sizes.
                    final beside =
                        primary == null ||
                        _buttonFitsBeside(
                          context,
                          constraints.maxWidth,
                          primary.operation,
                        );
                    final button = primary == null
                        ? null
                        : Semantics(
                            container: true,
                            button: true,
                            child: SizedBox(
                              height: 40,
                              child: KalinkaButton(
                                key: ValueKey(
                                  primary.operation == PluginOperation.update
                                      ? 'plugin-row-update-${plugin.id}'
                                      : 'plugin-install-${plugin.id}',
                                ),
                                label: primary.label,
                                size: KalinkaButtonSize.compact,
                                // Under the text it takes the width there,
                                // and cuts a long label short rather than
                                // overflow.
                                fullWidth: !beside,
                                leading: state.operation == primary.operation
                                    ? const SizedBox.square(
                                        dimension: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.6,
                                          color: KalinkaColors.textPrimary,
                                        ),
                                      )
                                    : null,
                                // Busy rather than dimmed while it runs;
                                // dimmed while another operation does.
                                enabled:
                                    primary.reason == null &&
                                    (state.operation == null ||
                                        state.operation == primary.operation),
                                onTap: state.operation == null
                                    ? () =>
                                          actions.onOperation(primary.operation)
                                    : null,
                              ),
                            ),
                          );
                    return Row(
                      children: [
                        Expanded(
                          child: beside
                              ? ExcludeSemantics(child: body)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ExcludeSemantics(child: body),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 52,
                                        top: 12,
                                      ),
                                      child: button,
                                    ),
                                  ],
                                ),
                        ),
                        if (beside && button != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: button,
                          ),
                        const SizedBox(width: 6),
                        const ExcludeSemantics(
                          child: Icon(
                            Icons.chevron_right,
                            key: ValueKey('plugin-chevron'),
                            size: 24,
                            color: KalinkaColors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (state.failure case final failure?)
            Padding(
              padding: const EdgeInsets.only(left: 52, bottom: 14),
              child: PluginFailureNote(
                failure: failure,
                onDismiss: actions.onDismissFailure,
              ),
            ),
        ],
      ),
    );
  }
}

/// Whether Add or Update, at its widest, leaves the text beside it room to
/// read. Measured at its widest so it stays put once the operation starts.
bool _buttonFitsBeside(
  BuildContext context,
  double width,
  PluginOperation operation,
) {
  final scaler = MediaQuery.textScalerOf(context);
  // KalinkaButton's compact label.
  final style = KalinkaTextStyles.trayRowLabel.copyWith(
    fontSize: KalinkaTypography.baseSize + 2,
  );
  double widthOf(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final (idle, busy) = operation == PluginOperation.update
      ? ('Update', 'Updating…')
      : ('Add', 'Adding…');
  // Padding and border, and the spinner beside the busy label.
  final button = math.max(widthOf(idle), widthOf(busy) + 20) + 30;
  // The gap before it, the chevron after it, the icon tile before the text.
  return width - 12 - button - 30 - 52 >= scaler.scale(100);
}

String _unstopped(String text) =>
    text.endsWith('.') ? text.substring(0, text.length - 1) : text;

/// A badge's word as it is said: NOT INSTALLED, "Not installed".
String _spoken(String badge) => badge[0] + badge.substring(1).toLowerCase();

/// The live status and any pending changes, wrapping where needed.
class _StatusLine extends StatelessWidget {
  final ModuleStatusBadge? badge;
  final String? detail;
  final Color detailColor;
  const _StatusLine({
    required this.badge,
    required this.detail,
    required this.detailColor,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ?badge,
      if (detail case final text?)
        Text(
          text,
          key: const ValueKey('plugin-status'),
          style: KalinkaTextStyles.trayRowSublabel.copyWith(color: detailColor),
        ),
    ],
  );
}

/// The plugin's current state and its explanation, kept together on its page.
class PluginStatusSummary extends StatelessWidget {
  final String pluginName;
  final PluginState state;
  const PluginStatusSummary({
    super.key,
    required this.pluginName,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final badge = pluginBadge(state, notInstalled: true)!;
    final detail = state.detail;
    final message = state.live?.message;
    final hasMessage = message != null && message.trim().isNotEmpty;
    final alert = badge.label == 'ERROR' || badge.label == 'WARNING';
    return Semantics(
      container: true,
      liveRegion: alert || state.operation != null,
      label: '$pluginName status',
      child: Container(
        padding: alert && hasMessage
            ? const EdgeInsets.all(12)
            : EdgeInsets.zero,
        decoration: alert && hasMessage
            ? BoxDecoration(
                color: badge.color.withValues(alpha: .07),
                border: Border(left: BorderSide(color: badge.color, width: 2)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusLine(
              badge: badge,
              detail: detail,
              detailColor: state.hasPendingChanges || state.staged
                  ? KalinkaColors.statusPendingLight
                  : KalinkaColors.textSecondary,
            ),
            if (hasMessage) ...[
              const SizedBox(height: 8),
              InlineMarkdown(
                text: message,
                style: KalinkaTextStyles.settingsDescription.copyWith(
                  color: KalinkaColors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Publisher and maturity metadata, below what a plugin does.
class _Badge extends StatelessWidget {
  final String label;

  /// Experimental: a caution in amber rather than a plain fact in grey.
  final bool warm;
  const _Badge(this.label, {this.warm = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: warm ? KalinkaColors.statusPendingSurface : null,
      border: Border.all(
        color: warm
            ? KalinkaColors.statusPending.withValues(alpha: .6)
            : KalinkaColors.textMuted.withValues(alpha: .6),
      ),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: KalinkaFonts.sans(
        fontSize: KalinkaTypography.baseSize,
        fontWeight: FontWeight.w500,
        color: warm
            ? KalinkaColors.statusPendingLight
            : KalinkaColors.textSecondary,
      ),
    ),
  );
}

/// A line on what the server or the catalog holds back, behind an info mark.
class PluginNote extends StatelessWidget {
  final String text;
  const PluginNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: KalinkaColors.textMuted,
        ),
      ),
      const SizedBox(width: 7),
      Expanded(child: Text(text, style: KalinkaTextStyles.trayRowSublabel)),
    ],
  );
}

/// Install for a plugin the server does not have, Update where it has an
/// older one, with why it is out of reach; null where neither applies.
/// [brief] leaves the version to the row's status line.
({PluginOperation operation, String label, String? reason})? _primaryFor(
  CatalogPlugin plugin,
  PluginState state,
  bool canManage, {
  bool brief = false,
}) {
  final PluginOperation operation;
  final String label;
  String? reason;
  if (!state.installed) {
    // Comes with the server, never as a package of its own.
    if (plugin.bundled) return null;
    operation = PluginOperation.install;
    label = state.operation == operation ? 'Adding…' : 'Add';
    if (plugin.compatibility?.status == 'blocked') {
      reason = 'No release meets this server\'s requirements.';
    }
  } else if (state.update case final update?) {
    operation = PluginOperation.update;
    label = state.operation == operation
        ? 'Updating…'
        : brief
        ? 'Update'
        : 'Update to ${update.version}';
  } else {
    return null;
  }
  if (!canManage) reason = 'This server cannot install or update plugins yet.';
  return (operation: operation, label: label, reason: reason);
}

/// What acts on an installed plugin, at the top of its configuration page:
/// its switch, and away from it Update where the server has a newer release
/// before a grey Uninstall; why any of it is out of reach, and what went
/// wrong.
class PluginControls extends StatelessWidget {
  final CatalogPlugin plugin;
  final PluginState state;
  final PluginEntryActions actions;
  const PluginControls({
    super.key,
    required this.plugin,
    required this.state,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final onChanged = state.operation == null && state.enabledPath != null
        ? actions.onEnabledChanged
        : null;
    final toggle = Semantics(
      key: ValueKey('plugin-enabled-${plugin.id}'),
      toggled: state.enabled,
      enabled: onChanged != null,
      label: '${plugin.name} enabled',
      onTap: onChanged == null ? null : () => onChanged(!state.enabled),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged(!state.enabled),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: onChanged == null ? 0.45 : 1,
                  child: IgnorePointer(
                    child: SettingsToggle(
                      value: state.enabled,
                      onChanged: (_) {},
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  state.enabled ? 'Enabled' : 'Disabled',
                  style: KalinkaTextStyles.trayRowLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final primary = _primaryFor(plugin, state, actions.canManage, brief: true);
    final update = primary?.operation == PluginOperation.update
        ? primary
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The buttons drop under the switch on a narrow phone.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            toggle,
            if (update != null || !plugin.bundled)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (update != null)
                    KalinkaButton(
                      key: ValueKey('plugin-update-${plugin.id}'),
                      label: update.label,
                      size: KalinkaButtonSize.compact,
                      enabled: update.reason == null && state.operation == null,
                      onTap: () => actions.onOperation(PluginOperation.update),
                    ),
                  // Part of the server install, so it goes with the server.
                  if (!plugin.bundled)
                    Tooltip(
                      message: actions.canManage
                          ? 'Remove ${plugin.name} from the server'
                          : 'This server cannot remove plugins yet',
                      child: KalinkaButton(
                        key: ValueKey('plugin-uninstall-${plugin.id}'),
                        label: state.operation == PluginOperation.uninstall
                            ? 'Uninstalling…'
                            : 'Uninstall',
                        variant: KalinkaButtonVariant.neutral,
                        size: KalinkaButtonSize.compact,
                        enabled: actions.canManage && state.operation == null,
                        onTap: () =>
                            actions.onOperation(PluginOperation.uninstall),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (!actions.canManage && (update != null || !plugin.bundled))
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: PluginNote(
              'This server cannot install, remove or update plugins yet.',
              key: ValueKey('plugin-manage-note'),
            ),
          ),
        if (state.failure case final failure?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: PluginFailureNote(
              failure: failure,
              onDismiss: actions.onDismissFailure,
            ),
          ),
      ],
    );
  }
}

/// Install or Uninstall, at the top right of the About page, as the row
/// offers them; none for a plugin that comes with the server.
Widget? pluginAboutAction(
  CatalogPlugin plugin,
  PluginState state,
  PluginEntryActions actions,
) {
  if (plugin.bundled) return null;
  if (state.installed) {
    return Tooltip(
      message: actions.canManage
          ? 'Remove ${plugin.name} from the server'
          : 'This server cannot remove plugins yet',
      child: KalinkaButton(
        key: ValueKey('about-uninstall-${plugin.id}'),
        label: state.operation == PluginOperation.uninstall
            ? 'Uninstalling…'
            : 'Uninstall',
        variant: KalinkaButtonVariant.neutral,
        size: KalinkaButtonSize.compact,
        enabled: actions.canManage && state.operation == null,
        onTap: () => actions.onOperation(PluginOperation.uninstall),
      ),
    );
  }
  final primary = _primaryFor(plugin, state, actions.canManage)!;
  return KalinkaButton(
    key: ValueKey('about-install-${plugin.id}'),
    label: primary.label,
    size: KalinkaButtonSize.compact,
    enabled: primary.reason == null && state.operation == null,
    onTap: () => actions.onOperation(PluginOperation.install),
  );
}

/// The foot of the About page: Update, where the server has a newer release.
class _UpdateAction extends StatelessWidget {
  final CatalogPlugin plugin;
  final PluginState state;
  final PluginEntryActions actions;
  const _UpdateAction({
    required this.plugin,
    required this.state,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final primary = _primaryFor(plugin, state, actions.canManage);
    if (primary?.operation != PluginOperation.update) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: KalinkaButton(
        key: ValueKey('about-update-${plugin.id}'),
        label: primary!.label,
        fullWidth: true,
        enabled: primary.reason == null && state.operation == null,
        onTap: () => actions.onOperation(PluginOperation.update),
      ),
    );
  }
}

/// Where an install, removal or update failed: the server's own words,
/// shown where it was asked for.
class PluginFailureNote extends StatelessWidget {
  final PluginFailure failure;
  final VoidCallback? onDismiss;
  const PluginFailureNote({super.key, required this.failure, this.onDismiss});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(10, 9, onDismiss == null ? 12 : 2, 9),
    decoration: BoxDecoration(
      color: KalinkaColors.statusOfflineSurface,
      border: Border.all(
        color: KalinkaColors.actionDelete.withValues(alpha: .25),
      ),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline,
          size: 17,
          color: KalinkaColors.actionDelete,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${failure.title}. ',
                  style: const TextStyle(color: KalinkaColors.textPrimary),
                ),
                TextSpan(text: failure.message),
              ],
            ),
            key: const ValueKey('plugin-failure'),
            style: KalinkaTextStyles.trayRowSublabel,
          ),
        ),
        if (onDismiss != null)
          IconButton(
            key: const ValueKey('plugin-failure-dismiss'),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            color: KalinkaColors.textSecondary,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    ),
  );
}

/// Everything the catalog says about a plugin, for its About page: what it
/// does, who made it, what it needs, with Install or Update at the foot.
class PluginAbout extends StatelessWidget {
  final CatalogPlugin plugin;
  final PluginState state;
  final PluginEntryActions actions;
  const PluginAbout({
    super.key,
    required this.plugin,
    required this.state,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Whether this server meets the plugin's requirements, said once, at
        // the top, with the server's reasons where it does not.
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _CompatibilityBanner(plugin: plugin),
        ),
        if (state.failure case final failure?)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PluginFailureNote(
              failure: failure,
              onDismiss: actions.onDismissFailure,
            ),
          ),
        if (!plugin.bundled && !actions.canManage)
          const Padding(
            key: ValueKey('about-reason'),
            padding: EdgeInsets.only(bottom: 14),
            child: PluginNote(
              'This server cannot install, remove or update plugins yet.',
            ),
          ),
        if (plugin.isDevice) ...[
          Text('HIFI CONTROL', style: KalinkaTextStyles.sectionHeaderMuted),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              plugin.isDevice
                  ? Icons.speaker_outlined
                  : Icons.music_note_outlined,
              size: 14,
              color: KalinkaColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                plugin.isDevice
                    ? 'Amplifier and AVR controls · Does not add a music source.'
                    : 'Adds a music source · No amplifier-specific support needed',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
            ),
          ],
        ),
        if (plugin.isDevice) ...[
          const SizedBox(height: 14),
          Text(
            'Controls and limitations',
            style: KalinkaTextStyles.trayRowLabel,
          ),
          for (final note in plugin.deviceNotes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(note, style: KalinkaTextStyles.trayRowSublabel),
            ),
          _ModelCoverage(plugin: plugin),
        ],
        _Facts(
          facts: [
            ('Created by', plugin.creator),
            (
              'Publisher and maturity',
              '${plugin.tierLabel} · ${plugin.maturityLabel}',
            ),
            ('License', plugin.license),
            (
              'Delivery',
              plugin.delivery == 'bundle'
                  ? 'Included with Kalinka Player'
                  : 'Independent package',
            ),
          ],
        ),
        for (final release in plugin.releases) ...[
          _Facts(
            facts: [
              (
                'Release',
                '${release.version} · ${release.channel}${release.withdrawn ? ' · Withdrawn' : ''}',
              ),
              ('Requires', _requires(release)),
              (
                'Server platforms',
                release.platforms
                    .map((p) => p == 'all' ? 'Cross-platform (all)' : p)
                    .join(', '),
              ),
              (
                'Architectures',
                release.architectures
                    .map(
                      (a) => a == 'all' ? 'Architecture-independent (all)' : a,
                    )
                    .join(', '),
              ),
            ],
          ),
          if (release.withdrawn)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Withdrawn: ${release.withdrawalReason ?? 'No reason supplied'}',
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  color: KalinkaColors.statusPendingLight,
                ),
              ),
            ),
          if (release.packages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Packages and platforms',
              style: KalinkaTextStyles.trayRowLabel,
            ),
            for (final package in release.packages)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(package, style: KalinkaTextStyles.trayRowSublabel),
              ),
          ],
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Requirements', style: KalinkaTextStyles.trayRowLabel),
            for (final note in release.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(note, style: KalinkaTextStyles.trayRowSublabel),
              ),
          ],
          if (release.releaseNotes != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _ExternalLink(
                label: 'Release notes for ${release.version}',
                uri: release.releaseNotes!,
              ),
            ),
        ],
        const SizedBox(height: 9),
        if (plugin.source != null)
          Align(
            alignment: Alignment.centerLeft,
            child: _ExternalLink(
              label: 'Source & license',
              uri: plugin.source!,
            ),
          ),
        Text(
          [
            if (!actions.canManage) 'Catalog signatures are not verified.',
            'Package dependencies and actual device support have not been checked.',
          ].join(' '),
          style: KalinkaTextStyles.trayRowSublabel,
        ),
        _UpdateAction(plugin: plugin, state: state, actions: actions),
      ],
    );
  }
}

/// What a release declares it needs, as one line of its facts.
String _requires(CatalogPluginRelease release) => [
  for (final version in release.versions.entries)
    '${switch (version.key) {
      'sdk' => 'SDK',
      'server' => 'Server',
      'python' => 'Python',
      _ => 'Renderer',
    }} ${version.value}',
  if (release.capabilities.isNotEmpty)
    'Capabilities: ${release.capabilities.join(', ')}',
].join(' · ');

String _bullets(Iterable<String> lines) =>
    lines.map((line) => '• $line').join('\n');

/// Whether this server meets the plugin's requirements, in the server's own
/// result: met, with the version that matches; not met, with its reasons for
/// the newest release; or not checked at all.
class _CompatibilityBanner extends StatelessWidget {
  final CatalogPlugin plugin;
  const _CompatibilityBanner({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final result = plugin.compatibility;
    // Bundled delivery describes how requirements are managed, not a locally
    // inferred compatibility or installed-plugin identity check.
    final status =
        result?.status ??
        (plugin.delivery == 'bundle'
            ? 'bundle_managed'
            : plugin.releases.isEmpty
            ? 'no_releases'
            : 'unknown');
    final blocked = result?.newerBlockedRelease ?? result?.releases.firstOrNull;
    final (title, text, met) = switch (status) {
      'bundle_managed' => (
        'Managed with Kalinka Player',
        'Requirements and updates follow the server bundle. This plugin is not checked as a separate package.',
        true,
      ),
      'no_releases' => (
        'No release available',
        'No independent catalog release has been published to check.',
        true,
      ),
      'metadata_compatible' => (
        'Requirements met',
        [
          result?.latestCompatibleVersion != null
              ? 'Version ${result!.latestCompatibleVersion} (${result.channel}) matches this server.'
              : 'The declared requirements match this server.',
          if (result?.newerBlockedRelease case final newer?)
            newer.explanations.isEmpty
                ? 'Version ${newer.version} does not.'
                : 'Version ${newer.version} does not:\n${_bullets(newer.explanations)}',
        ].join('\n\n'),
        true,
      ),
      'blocked' => (
        'Requirements not met',
        blocked != null && blocked.explanations.isNotEmpty
            ? _bullets(blocked.explanations)
            : 'No ${result!.channel} release matches this server.',
        false,
      ),
      _ => (
        'Requirements not checked',
        'This server has not reported a compatibility check for this plugin.',
        false,
      ),
    };
    return _RequirementsBanner(title: title, text: text, warning: !met);
  }
}

class _Facts extends StatelessWidget {
  final List<(String, String)> facts;
  const _Facts({required this.facts});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 280 &&
              MediaQuery.textScalerOf(context)
                      .scale(KalinkaTextStyles.trayRowSublabel.fontSize!) <
                  KalinkaTextStyles.trayRowSublabel.fontSize! * 1.5
          ? 2
          : 1;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Wrap(
          spacing: 20,
          runSpacing: 13,
          children: [
            for (final (label, value) in facts)
              SizedBox(
                width: (constraints.maxWidth - 20 * (columns - 1)) / columns,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KalinkaTextStyles.trayRowSublabel),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _RequirementsBanner extends StatelessWidget {
  final String title, text;
  final bool warning;
  const _RequirementsBanner({
    required this.title,
    required this.text,
    required this.warning,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning
          ? KalinkaColors.statusPendingSurface
          : KalinkaColors.surfaceBase,
      border: Border.all(
        color: warning
            ? KalinkaColors.statusPending.withValues(alpha: .2)
            : KalinkaColors.borderDefault,
      ),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: warning
              ? KalinkaColors.statusPendingLight
              : KalinkaColors.textSecondary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: KalinkaTextStyles.trayRowLabel.copyWith(
                  color: warning
                      ? KalinkaColors.statusPendingLight
                      : KalinkaColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(text, style: KalinkaTextStyles.trayRowSublabel),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ModelCoverage extends StatefulWidget {
  final CatalogPlugin plugin;
  const _ModelCoverage({required this.plugin});
  @override
  State<_ModelCoverage> createState() => _ModelCoverageState();
}

class _ModelCoverageState extends State<_ModelCoverage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final models = widget.plugin.models
        .where((s) => s.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final families = widget.plugin.families
        .where((s) => s.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceBase,
        border: Border.all(color: KalinkaColors.borderDefault),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Will it work with my device?',
            style: KalinkaTextStyles.trayRowLabel,
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('model-search-${widget.plugin.id}'),
            style: KalinkaTextStyles.textFieldInput,
            decoration: catalogSearchDecoration('Search a model or family'),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
          Text(
            _query.isNotEmpty && models.isEmpty && families.isEmpty
                ? 'No catalog match · Not verified'
                : 'Check your exact model',
            style: KalinkaTextStyles.trayRowLabel.copyWith(
              color: KalinkaColors.statusPendingLight,
            ),
          ),
          const SizedBox(height: 8),
          Text('Supported models', style: KalinkaTextStyles.trayRowSublabel),
          Text(
            models.isEmpty
                ? (widget.plugin.models.isEmpty
                      ? 'No exact models listed; see family coverage.'
                      : 'No matching model listed.')
                : models.join(', '),
            style: KalinkaTextStyles.trayRowSublabel,
          ),
          const SizedBox(height: 8),
          Text('Supported families', style: KalinkaTextStyles.trayRowSublabel),
          Text(
            families.isEmpty
                ? (widget.plugin.families.isEmpty
                      ? 'No family-wide claim.'
                      : 'No matching family listed.')
                : families.join(', '),
            style: KalinkaTextStyles.trayRowSublabel,
          ),
          const SizedBox(height: 10),
          Text(
            'Catalog declarations only · No connected-device check in this preview.',
            style: KalinkaTextStyles.trayRowSublabel,
          ),
        ],
      ),
    );
  }
}

class _ExternalLink extends StatelessWidget {
  final String label;
  final Uri uri;
  const _ExternalLink({required this.label, required this.uri});
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: KalinkaColors.textSecondary,
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.zero,
      textStyle: KalinkaTextStyles.trayRowSublabel,
    ),
    onPressed: () async {
      try {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('No browser');
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Could not open this link.')),
          );
        }
      }
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        const SizedBox(width: 8),
        const Icon(Icons.open_in_new, size: 14),
      ],
    ),
  );
}
