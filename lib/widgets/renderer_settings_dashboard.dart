import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../data_model/presentation_schema.dart';
import '../data_model/renderer_config.dart';
import '../providers/app_state_provider.dart';
import '../providers/bit_perfect_provider.dart';
import '../providers/renderer_provider.dart';
import '../providers/renderer_settings_provider.dart';
import '../providers/source_modules_provider.dart';
import '../theme/app_theme.dart';
import 'audio_signal_path.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart' show showKalinkaDialog;
import 'playback_chain_diagram.dart';
import 'renderer_name_dialog.dart';
import 'room_eq/eq_card.dart';
import 'settings_controls/settings_jump_target.dart';
import 'settings_controls/settings_action_row.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_row.dart';
import 'settings_renderer.dart';

/// Groups fields from the selected renderer. A renderer with a different
/// schema can still expose its own sections through the full section editor.
class RendererSettingsDashboard extends ConsumerStatefulWidget {
  final RendererSettingsState state;
  final String rendererId, rendererName, firPath;
  final Set<String> roomEqFields;
  final ValueChanged<String> onSection;
  final ValueChanged<RoomEqSection?> onRoomEq;
  final ValueChanged<String> onExpertField;
  final VoidCallback onSpeakerTest;
  final Widget? soundcard;

  const RendererSettingsDashboard({
    super.key,
    required this.state,
    required this.rendererId,
    required this.rendererName,
    required this.onSection,
    required this.roomEqFields,
    required this.firPath,
    required this.onRoomEq,
    required this.onExpertField,
    required this.onSpeakerTest,
    this.soundcard,
  });

  String? optionLabel(String path) => state.options[path]
      ?.where((o) => o.value == state.values[path]?.toString())
      .firstOrNull
      ?.label;

  @override
  ConsumerState<RendererSettingsDashboard> createState() =>
      _RendererSettingsDashboardState();
}

class _RendererSettingsDashboardState
    extends ConsumerState<RendererSettingsDashboard> {
  final _targets = <String, GlobalKey<SettingsJumpTargetState>>{};

  static const _stageFields = <String, List<String>>{
    'output': ['output.device', 'output.driver'],
    'software_volume': ['output.volume_mode'],
    'replaygain': ['core.output.replaygain'],
    'sample_rate_change': ['output.sample_rate'],
    'dsd_to_pcm': [
      'output.dsd_pcm_rate',
      'output.dsd_filter',
      'output.dsd_mode',
    ],
    'dsd_native': ['output.dsd_mode'],
    'dop': ['output.dsd_mode'],
    'dsd_gain': ['output.dsd_gain_db'],
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final rendererId = widget.rendererId;
    final roomEqFields = widget.roomEqFields;
    final firPath = widget.firPath;
    final info = ref.watch(
      rendererListProvider.select(
        (s) => s.renderers.where((r) => r.rendererId == rendererId).firstOrNull,
      ),
    );
    final available = {
      for (final section in state.sections)
        section.id: section.fields
            .where((f) => !roomEqFields.contains(f.path))
            .toList(),
    };
    final nameFields = available['renderer'];
    final nameField = nameFields
        ?.where(
          (f) =>
              f.path == RendererConfigField.namePath &&
              !f.readonly &&
              f.widget == WidgetKind.text,
        )
        .firstOrNull;
    final output = available['output'] ?? const <FieldSpec>[];
    final inlineOutput = output.any(
      (f) => const {
        'output.device',
        'output.driver',
        'output.volume_mode',
        'core.output.replaygain',
        'output.session_start_volume_ceiling_percent',
        'output.bit_depth',
        'output.sample_rate',
      }.contains(f.path),
    );
    final limits = output
        .where(
          (f) =>
              f.readonly &&
              (f.path == 'output.bit_depth' ||
                  f.path == 'output.sample_rate') &&
              state.values[f.path]?.toString().trim().isNotEmpty == true,
        )
        .toList();
    final hasPeq = state.values.containsKey('dsp.profile');
    final hasFir = state.values.containsKey(firPath);
    // The renderer then keeps every sample out of room EQ's reach.
    final direct = state.values['output.direct_mode'] == true;
    final extra = state.sections.where(
      (s) => switch (s.id) {
        'renderer' => (nameFields ?? []).any((f) => f != nameField),
        'output' => !inlineOutput && output.isNotEmpty,
        'dsd' || 'core.output' => false,
        _ => available[s.id]!.isNotEmpty,
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final availableWidth = math.min(
          1000.0,
          constraints.maxWidth - 2 * gutter,
        );
        final inlineMinimum = MediaQuery.textScalerOf(context).scale(600);
        // Keep the phone gutters and a usable two-column form through tablet widths.
        final width = math.max(
          availableWidth * .75,
          math.min(availableWidth, inlineMinimum),
        );
        final writable = {
          for (final f in state.expertFields)
            if (!f.readonly) f.path,
        };
        final inlinePaths = {
          for (final f in [
            ...?available['dsd'],
            ...?available['core.output'],
            if (inlineOutput) ...output,
          ])
            if (writable.contains(f.path)) f.path,
        };
        final targetPaths = _stageFields.values
            .expand((paths) => paths)
            .toSet();
        Widget target(String path, Widget child) => SettingsJumpTarget(
          key: _targets.putIfAbsent(
            path,
            () => GlobalKey<SettingsJumpTargetState>(),
          ),
          child: child,
        );
        Widget field(FieldSpec f) {
          final row = SchemaFieldRenderer(key: ValueKey(f.path), field: f);
          return targetPaths.contains(f.path) && inlinePaths.contains(f.path)
              ? target(f.path, row)
              : row;
        }

        VoidCallback? shortcutFor(String kind) {
          final section = switch (kind) {
            'peq'
                when hasPeq &&
                    (writable.contains('dsp.profile') ||
                        writable.contains('dsp.enabled')) =>
              RoomEqSection.bands,
            'preamp'
                when writable.contains('dsp.preamp_enabled') ||
                    writable.contains('dsp.preamp') ||
                    writable.contains('dsp.preamp_db') =>
              RoomEqSection.preamp,
            'fir' when hasFir && writable.contains(firPath) =>
              RoomEqSection.fir,
            _ => null,
          };
          if (section != null) return () => widget.onRoomEq(section);
          final candidates = _stageFields[kind];
          if (candidates == null) return null;
          final path = candidates.where(inlinePaths.contains).firstOrNull;
          if (path != null) return () => _targets[path]?.currentState?.reveal();
          if (kind == 'output' && widget.soundcard != null) {
            return () => _targets['soundcard']?.currentState?.reveal();
          }
          final expert = candidates.where(writable.contains).firstOrNull;
          return expert == null ? null : () => widget.onExpertField(expert);
        }

        final audioRows = <Widget>[
          if (widget.soundcard case final card?) target('soundcard', card),
          if (inlineOutput)
            for (final f in output)
              if (limits.contains(f)) ...[
                if (f == limits.first)
                  _OutputLimits(fields: limits, values: state.values),
              ] else
                field(f),
        ];
        return _DashboardLayout(
          renderer: info,
          configuredOutput:
              widget.optionLabel('output.device') ??
              widget.optionLabel('output.driver'),
          shortcutFor: shortcutFor,
          availableWidth: availableWidth,
          settingsWidth: width,
          identity: _Identity(
            info: info,
            name:
                state.configuredName ??
                info?.friendlyName ??
                widget.rendererName,
            device: info?.audioBackend.isNotEmpty == true
                ? widget.optionLabel('output.device')
                : null,
            onRename: nameField == null
                ? null
                : () => showKalinkaDialog<void>(
                    context: context,
                    builder: (_) => RendererNameDialog(
                      rendererId: rendererId,
                      field: nameField,
                    ),
                  ),
          ),
          settings: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (audioRows.isNotEmpty)
                _Group(
                  title: 'Audio output',
                  icon: Icons.speaker_outlined,
                  rows: audioRows,
                ),
              if (roomEqFields.isNotEmpty)
                _Group(
                  title: 'Sound processing',
                  icon: Icons.graphic_eq_rounded,
                  rows: [
                    SettingsActionRow(
                      label: 'Room EQ',
                      leading: Icons.equalizer_rounded,
                      sublabel: [
                        if (direct) 'Off while Direct output is on',
                        if (!direct && state.values['dsp.bypass'] == true)
                          'DSP bypassed',
                        if (!hasPeq && !hasFir && state.hasHeadroom) 'Headroom',
                        if (!direct && hasPeq)
                          switch ((
                            state.values['dsp.bypass'],
                            state.values['dsp.enabled'],
                          )) {
                            (true, _) => 'Parametric EQ',
                            (_, true) => 'Parametric EQ on',
                            (_, false) => 'Parametric EQ off',
                            _ => 'Parametric EQ',
                          },
                        if (!direct && hasFir)
                          switch (widget.optionLabel(firPath)) {
                            final name? => 'FIR · $name',
                            null => 'FIR convolution',
                          },
                      ].join('  ·  '),
                      onTap: direct ? null : () => widget.onRoomEq(null),
                    ),
                  ],
                ),
              if (available['dsd'] case final dsd? when dsd.isNotEmpty)
                _Group(
                  title: 'DSD',
                  icon: Icons.waves_rounded,
                  rows: dsd.map(field).toList(),
                ),
              if (available['core.output'] case final connected?
                  when connected.isNotEmpty)
                _Group(
                  title: 'Connected device',
                  icon: Icons.power_settings_new_rounded,
                  rows: connected.map(field).toList(),
                ),
              if (extra.isNotEmpty)
                _Group(
                  title: 'Renderer settings',
                  icon: Icons.tune_rounded,
                  rows: [
                    for (final s in extra)
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          title: Text(s.title),
                          subtitle: Text(
                            available[s.id]!
                                .take(3)
                                .map((f) => f.label)
                                .join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => widget.onSection(s.id),
                        ),
                      ),
                  ],
                ),
              _Group(
                title: 'Tools',
                icon: Icons.build_outlined,
                rows: [
                  SettingsRow(
                    label: 'Speaker test',
                    sublabel: state.hasPendingChanges
                        ? 'Apply your changes first to test this output.'
                        : 'Play a tone through the left and right channels.',
                    control: KalinkaButton(
                      label: 'Test',
                      leading: const Icon(Icons.play_arrow_rounded, size: 18),
                      variant: KalinkaButtonVariant.neutral,
                      size: KalinkaButtonSize.compact,
                      enabled: !state.hasPendingChanges,
                      onTap: widget.onSpeakerTest,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OutputLimits extends StatelessWidget {
  final List<FieldSpec> fields;
  final Map<String, dynamic> values;
  const _OutputLimits({required this.fields, required this.values});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Output limits', style: KalinkaTextStyles.trayRowSublabel),
        for (final f in fields)
          Tooltip(
            message: f.label,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: KalinkaColors.surfaceElevated,
                border: Border.all(color: KalinkaColors.borderSubtle),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  values[f.path].toString(),
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Identity extends StatelessWidget {
  final RendererInfo? info;
  final String name;
  final String? device;
  final VoidCallback? onRename;
  const _Identity({
    required this.info,
    required this.name,
    this.device,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final renderer = info;
    final browser = renderer?.kind == 'web';
    final details = [
      if (browser) 'Browser playback',
      if (renderer != null && renderer.audioBackend.isNotEmpty)
        renderer.audioBackend.toUpperCase(),
      if (device?.isNotEmpty == true) device!,
      if (renderer != null && renderer.hostname.isNotEmpty) renderer.hostname,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [KalinkaColors.accentSubtle, KalinkaColors.surfaceRaised],
        ),
        border: Border.all(color: KalinkaColors.accentBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            browser ? Icons.web_asset_rounded : Icons.speaker_group_outlined,
            size: 34,
            color: KalinkaColors.textPrimary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: KalinkaTextStyles.cardTitle),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                if (renderer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: renderer.isConnected
                              ? KalinkaColors.statusOnline
                              : KalinkaColors.textMuted,
                        ),
                        Text(
                          [
                            renderer.isConnected ? 'Connected' : 'Offline',
                            if (renderer.softwareVersion.isNotEmpty)
                              'v${renderer.softwareVersion}',
                          ].join(' · '),
                          style: KalinkaTextStyles.trayRowSublabel,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (onRename != null) ...[
            const SizedBox(width: 8),
            KalinkaButton(
              label: 'Rename',
              leading: const Icon(Icons.edit_outlined, size: 16),
              size: KalinkaButtonSize.compact,
              variant: KalinkaButtonVariant.neutral,
              onTap: onRename,
            ),
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> rows;
  const _Group({required this.title, required this.icon, required this.rows});

  static Widget heading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Icon(icon, size: 18, color: KalinkaColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              semanticsLabel: title,
              style: KalinkaTextStyles.sectionHeaderMuted,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(title, icon),
      SettingsCard(gutter: 0, children: rows),
    ],
  );
}

class _DashboardLayout extends ConsumerWidget {
  final RendererInfo? renderer;
  final String? configuredOutput;
  final double availableWidth, settingsWidth;
  final VoidCallback? Function(String kind) shortcutFor;
  final Widget identity, settings;

  const _DashboardLayout({
    required this.renderer,
    required this.configuredOutput,
    required this.shortcutFor,
    required this.availableWidth,
    required this.settingsWidth,
    required this.identity,
    required this.settings,
  });

  List<SignalStage> _stages(WidgetRef ref) {
    final info = renderer;
    if (info == null || !info.active || !info.isConnected) return const [];
    final current = ref.watch(
      playQueueStateStoreProvider.select((s) => s.currentRendererId),
    );
    if (current != null && current != info.rendererId) {
      return const [];
    }
    final playback = ref.watch(playerStateProvider);
    final track = playback.currentTrack;
    if (track == null ||
        playback.state == PlayerStateType.stopped ||
        playback.state == PlayerStateType.error) {
      return [
        (
          kind: 'source',
          label: 'Source',
          detail: switch (playback.state) {
            PlayerStateType.stopped => 'No track playing',
            PlayerStateType.error => 'Playback error',
            _ => 'Waiting for track details',
          },
          icon: Icons.library_music_outlined,
          bitPerfect: null,
        ),
        (
          kind: 'output',
          label: 'Configured output',
          detail: configuredOutput ?? info.friendlyName,
          icon: Icons.speaker_outlined,
          bitPerfect: null,
        ),
      ];
    }
    final sourceId = sourceOfId(track.id);
    return signalStages(
      playback,
      ref.watch(volumeStateProvider),
      source: ref.watch(
        sourceDisplayInfoProvider.select((m) => m[sourceId]?.title),
      ),
      bitPerfect: ref.watch(bitPerfectProvider),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = _stages(ref);
    const gap = 24.0;
    final scaler = MediaQuery.textScalerOf(context);
    final railWidth = math.max(
      scaler.scale(180),
      availableWidth - settingsWidth - gap,
    );
    final beside =
        stages.isNotEmpty &&
        availableWidth - railWidth - gap >= scaler.scale(520);
    final chain = Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Group.heading('Playback chain', Icons.route_outlined),
          Semantics(
            container: true,
            child: PlaybackChainDiagram(
              stages: stages,
              vertical: beside,
              shortcutFor: shortcutFor,
            ),
          ),
        ],
      ),
    );
    return Center(
      child: SizedBox(
        width: beside ? availableWidth : settingsWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            if (stages.isNotEmpty && !beside) chain,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (beside) ...[
                  SizedBox(width: railWidth, child: chain),
                  const SizedBox(width: gap),
                ],
                Expanded(child: settings),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
