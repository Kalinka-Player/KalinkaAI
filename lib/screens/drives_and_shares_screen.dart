import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart' show OptionSpec;
import '../data_model/storage.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/search_session_provider.dart';
import '../providers/storage_devices_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../widgets/configuration_appearance.dart';
import '../widgets/configuration_page.dart';
import '../widgets/demo_read_only_dialog.dart';
import '../widgets/failure_note.dart';
import '../widgets/hover_text_action.dart';
import '../widgets/kalinka_button.dart';
import '../widgets/kalinka_dialog.dart';
import '../widgets/search_cards/track_row_support.dart' show itemIcon;
import '../widgets/settings_controls/module_status_badge.dart'
    show ModuleStatusBadge;
import '../widgets/settings_controls/settings_card.dart';
import '../widgets/settings_controls/settings_combo_input.dart';
import '../widgets/settings_controls/settings_enum_pills.dart';
import '../widgets/settings_controls/settings_row.dart';
import '../widgets/settings_controls/settings_text_input.dart';
import '../widgets/settings_controls/settings_toggle.dart';
import '../widgets/settings_controls/warning_note.dart';

const _nfsVersions = ['3', '4', '4.1', '4.2'];

/// The version a share not kept yet is mounted with, as the server keeps it.
const _firstNfsVersion = '4';

String _reason(Object error) => '$error'.replaceFirst('Exception: ', '');

/// A mount the server still had under way when it answered is let go after
/// this, by when the server has given up on it too.
const _givenUpAfter = Duration(minutes: 3);

/// How long Add network share waits for a server's name to be typed out
/// before asking that server which folders it shares.
const shareLookupDelay = Duration(milliseconds: 600);

enum _MountPhase {
  /// Asked, and not answered yet.
  asking,

  /// Answered as still under way.
  waiting,
}

/// The mounts asked for on this screen until they settle, by device id: a
/// share found moves to another group once it is kept, and its row with it.
class _MountWatch extends Notifier<Map<String, _MountPhase>> {
  final _timers = <String, Timer>{};

  @override
  Map<String, _MountPhase> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    ref.listen(storageDevicesProvider, (_, next) {
      if (next.value case final list?) _follow(list);
    });
    return const {};
  }

  void asking(String id) => _enter(id, _MountPhase.asking);

  /// What the server answered a mount with: Mounting… while it is still
  /// under way, the row's own state once it is not.
  void answered(DeviceAnswer answer) => answer.state == VolumeState.mounting
      ? _enter(answer.id, _MountPhase.waiting, _givenUpAfter)
      : settled(answer.id);

  void settled(String id) {
    _timers.remove(id)?.cancel();
    if (state.containsKey(id)) state = {...state}..remove(id);
  }

  void _enter(String id, _MountPhase phase, [Duration? until]) {
    _timers.remove(id)?.cancel();
    if (until != null) _timers[id] = Timer(until, () => settled(id));
    state = {...state, id: phase};
  }

  void _follow(StorageDeviceList list) {
    for (final device in list.devices) {
      if (state[device.id] == _MountPhase.waiting &&
          (device.state == VolumeState.mounted ||
              device.state == VolumeState.failed)) {
        settled(device.id);
      }
    }
  }
}

final _mountWatchProvider =
    NotifierProvider.autoDispose<_MountWatch, Map<String, _MountPhase>>(
      _MountWatch.new,
    );

/// Drives & shares: every drive and network share the streamer could play
/// from, mounted or not, with what can be done with each now.
///
/// Asks again every [storageDevicesPollInterval] while open, which is also
/// what keeps the server looking for shares.
class DrivesAndSharesScreen extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final bool handlesBack;

  const DrivesAndSharesScreen({
    super.key,
    required this.onClose,
    this.handlesBack = true,
  });

  @override
  ConsumerState<DrivesAndSharesScreen> createState() =>
      _DrivesAndSharesScreenState();
}

class _DrivesAndSharesScreenState extends ConsumerState<DrivesAndSharesScreen> {
  late final Timer _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      storageDevicesPollInterval,
      (_) => ref.read(storageDevicesProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  Future<void> _addShare() async {
    if (await refusedAsDemo(context, ref) || !mounted) return;
    final devices = ref.read(storageDevicesProvider.notifier);
    await showKalinkaDialog<void>(
      context: context,
      builder: (_) => const _AddShareDialog(),
    );
    await devices.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(storageDevicesProvider);
    ref.watch(_mountWatchProvider);
    final gutter = ConfigurationAppearance.gutter(context);
    return ConfigurationPage(
      title: 'Drives & shares',
      onClose: widget.onClose,
      handlesBack: widget.handlesBack,
      action: listing.value?.mountingAvailable == true
          ? IconButton(
              key: const ValueKey('add-share'),
              tooltip: 'Add network share',
              onPressed: _addShare,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              color: KalinkaColors.textSecondary,
              icon: const Icon(Icons.add, size: 22),
            )
          : null,
      bodyBuilder: (heading) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the list, so it stays in view as the list scrolls.
          if (listing.value?.mountingAvailable == false)
            WarningNote(
              key: const ValueKey('no-mount-helper'),
              severity: WarningNoteSeverity.warning,
              fitsContent: true,
              margin: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
              message:
                  'This server cannot mount drives or shares: the mount '
                  'helper comes with the Kalinka package, and it runs '
                  'without it.',
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                heading,
                if (listing.value case final list?)
                  ..._groups(list)
                else if (listing.hasError)
                  _Unavailable(
                    onRetry: () => ref.invalidate(storageDevicesProvider),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _groups(StorageDeviceList list) {
    List<StorageDevice> where(bool Function(StorageDevice) test) => [
      for (final device in list.devices)
        if (test(device)) device,
    ];
    final streamer = where(
      (d) =>
          d.medium == StorageMedium.internal || d.medium == StorageMedium.disk,
    );
    final usb = where((d) => d.medium == StorageMedium.usb);
    final saved = where(
      (d) => d.medium == StorageMedium.network && !d.isFoundShare,
    );
    return [
      if (streamer.isNotEmpty)
        _Group(title: 'ON THIS STREAMER', devices: streamer),
      if (usb.isNotEmpty) _Group(title: 'USB', devices: usb),
      if (saved.isNotEmpty)
        _Group(title: 'SAVED NETWORK SHARES', devices: saved),
      _Group(
        title: 'FOUND ON YOUR NETWORK',
        devices: where((d) => d.isFoundShare),
        action: list.scanning
            ? Text('Looking…', style: KalinkaTextStyles.trayRowSublabel)
            : const _Refresh(),
        empty: list.scanning
            ? 'Looking for shares…'
            : 'No shares found on your network.',
      ),
    ];
  }
}

class _Unavailable extends StatelessWidget {
  final VoidCallback onRetry;

  const _Unavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(ConfigurationAppearance.gutter(context)),
    child: Column(
      children: [
        Text(
          'Could not list the drives and shares. Check that your player is '
          'connected and try again.',
          style: KalinkaTextStyles.trayRowSublabel,
        ),
        const SizedBox(height: 12),
        KalinkaButton(label: 'Retry', onTap: onRetry),
      ],
    ),
  );
}

class _Group extends StatelessWidget {
  final String title;
  final List<StorageDevice> devices;

  /// Beside the title, acting on the whole group.
  final Widget? action;

  /// Said in the card while it has no rows.
  final String? empty;

  const _Group({
    required this.title,
    required this.devices,
    this.action,
    this.empty,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: ConfigurationAppearance.sectionPadding(context),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: KalinkaTextStyles.sectionHeaderMuted),
            ),
            ?action,
          ],
        ),
      ),
      SettingsCard(
        children: [
          for (final device in devices)
            _DeviceRow(key: ValueKey('device-${device.id}'), device: device),
          if (devices.isEmpty && empty != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(empty!, style: KalinkaTextStyles.trayRowSublabel),
            ),
        ],
      ),
    ],
  );
}

/// Asks every host on the network for its shares again.
class _Refresh extends ConsumerWidget {
  const _Refresh();

  @override
  Widget build(BuildContext context, WidgetRef ref) => HoverTextAction(
    key: const ValueKey('refresh-shares'),
    label: 'REFRESH',
    semanticsLabel: 'Look for shares again',
    color: KalinkaColors.textSecondary,
    hoverColor: KalinkaColors.textPrimary,
    onTap: () async {
      final toast = ref.read(toastProvider.notifier);
      final devices = ref.read(storageDevicesProvider.notifier);
      try {
        await ref.read(kalinkaProxyProvider).rescanShares();
      } catch (e) {
        toast.show(_reason(e), isError: true);
      }
      await devices.refresh();
    },
  );
}

/// Where a device stands, beside its name: null where its button says it.
ModuleStatusBadge? _badge(
  StorageDevice device, {
  required bool mounting,
  String? busy,
}) {
  ModuleStatusBadge badge(String label, Color color, IconData icon) =>
      ModuleStatusBadge(
        key: ValueKey('status-${device.id}'),
        inline: true,
        label: label,
        color: color,
        icon: icon,
      );
  final working = busy ?? (mounting ? 'MOUNTING…' : null);
  if (working != null) {
    return badge(working, KalinkaColors.statusPending, Icons.sync);
  }
  // A share found has a state only once a mount of it was asked for.
  if (device.medium == StorageMedium.internal ||
      device.isFoundShare && device.state == VolumeState.unmounted) {
    return null;
  }
  const mountedIcon = Icons.check_circle_outline;
  if (device.bySystem) {
    return badge(
      'MOUNTED BY THE SYSTEM',
      KalinkaColors.statusOnline,
      mountedIcon,
    );
  }
  if (!device.connected) {
    return badge('NOT CONNECTED', KalinkaColors.textMuted, Icons.link_off);
  }
  return switch (device.state) {
    VolumeState.mounted => badge(
      'MOUNTED',
      KalinkaColors.statusOnline,
      mountedIcon,
    ),
    VolumeState.mounting => badge(
      'MOUNTING…',
      KalinkaColors.statusPending,
      Icons.sync,
    ),
    VolumeState.failed => badge(
      'FAILED',
      KalinkaColors.statusError,
      Icons.error_outline,
    ),
    VolumeState.unmounted =>
      device.canMount
          ? null
          : badge(
              'NOT MOUNTED',
              KalinkaColors.textMuted,
              Icons.radio_button_unchecked,
            ),
  };
}

/// What a device's dialog changed, each null where it did not.
class _Changes {
  final String? label;
  final bool? atStart;
  final bool? readOnly;
  final String? version;

  const _Changes({this.label, this.atStart, this.readOnly, this.version});

  bool get isEmpty =>
      label == null && atStart == null && readOnly == null && version == null;
}

/// A device as it is now. A mounted one has its Unmount or Eject button;
/// tapping one Kalinka mounts opens its dialog, to mount it with the
/// settings there or, once mounted, to change them.
class _DeviceRow extends ConsumerStatefulWidget {
  final StorageDevice device;

  const _DeviceRow({super.key, required this.device});

  @override
  ConsumerState<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends ConsumerState<_DeviceRow> {
  /// What the row is doing, while it unmounts or ejects.
  String? _busy;

  StorageDevice get _device => widget.device;

  Future<void> _act(
    String busy,
    Future<void> Function(KalinkaPlayerProxy api) action, {
    String? done,
  }) async {
    final toast = ref.read(toastProvider.notifier);
    final devices = ref.read(storageDevicesProvider.notifier);
    final session = ref.read(searchSessionProvider.notifier);
    setState(() => _busy = busy);
    try {
      await action(ref.read(kalinkaProxyProvider));
      // Pages open on the volume list what went with it.
      session.closeStorageSources();
      if (done != null) toast.show(done);
    } catch (e) {
      toast.show(_reason(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    await devices.refresh();
  }

  /// Opens the device's dialog, and mounts it as the dialog says where it
  /// was opened [toMount] and closed with Mount.
  Future<void> _open({required bool toMount}) async {
    if (await refusedAsDemo(context, ref) || !mounted) return;
    final toast = ref.read(toastProvider.notifier);
    final devices = ref.read(storageDevicesProvider.notifier);
    final watch = ref.read(_mountWatchProvider.notifier);
    final api = ref.read(kalinkaProxyProvider);
    // The row may be rebuilt elsewhere meanwhile, as a share found is once kept.
    final id = _device.id;
    final mount = await showKalinkaDialog<_Changes>(
      context: context,
      builder: (_) => _DeviceDialog(device: _device, toMount: toMount),
    );
    if (mount != null) {
      watch.asking(id);
      try {
        watch.answered(
          await api.mountStorageDevice(
            id,
            label: mount.label,
            atStart: mount.atStart,
            readOnly: mount.readOnly,
            version: mount.version,
          ),
        );
      } catch (e) {
        watch.settled(id);
        toast.show(_reason(e), isError: true);
      }
    }
    await devices.refresh();
  }

  Future<void> _unmount() async {
    if (await refusedAsDemo(context, ref) || !mounted) return;
    final device = _device;
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => _UnmountDialog(device: device),
    );
    if (confirmed != true || !mounted) return;
    await _act('UNMOUNTING…', (api) => api.unmountStorageDevice(device.id));
  }

  Future<void> _eject() async {
    if (await refusedAsDemo(context, ref) || !mounted) return;
    final device = _device;
    await _act(
      'EJECTING…',
      (api) => api.ejectVolume(device.id),
      done: '${device.label} can be unplugged',
    );
  }

  Future<void> _dismiss() async {
    if (await refusedAsDemo(context, ref) || !mounted) return;
    final toast = ref.read(toastProvider.notifier);
    final devices = ref.read(storageDevicesProvider.notifier);
    try {
      await ref.read(kalinkaProxyProvider).dismissStorageFailure(_device.id);
    } catch (e) {
      toast.show(_reason(e), isError: true);
    }
    await devices.refresh();
  }

  KalinkaButton? _button({required bool enabled}) {
    final device = _device;
    KalinkaButton button(String key, String label, VoidCallback onTap) =>
        KalinkaButton(
          key: ValueKey('$key-${device.id}'),
          label: label,
          size: KalinkaButtonSize.compact,
          variant: KalinkaButtonVariant.neutral,
          enabled: enabled,
          onTap: onTap,
        );
    // Ejecting is how a USB drive is let go.
    if (device.canEject) return button('eject', 'Eject', _eject);
    if (device.canUnmount) return button('unmount', 'Unmount', _unmount);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final phase = ref.watch(
      _mountWatchProvider.select((phases) => phases[device.id]),
    );
    final mounting = phase != null || device.state == VolumeState.mounting;
    final idle = !mounting && _busy == null;
    final badge = _badge(device, mounting: mounting, busy: _busy);
    final button = mounting ? null : _button(enabled: _busy == null);
    final error = device.error;
    final note = idle && device.state == VolumeState.failed && error != null
        ? _MountFailure(
            id: device.id,
            name: device.label,
            error: error,
            detail: device.errorDetail,
            onDismiss: device.canDismiss ? _dismiss : null,
          )
        : null;
    final toMount = !mounting && device.state != VolumeState.mounted;
    final settings = device.canEdit && _busy == null
        ? () => _open(toMount: toMount)
        : null;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(device.label, style: KalinkaTextStyles.trayRowLabel),
            ?badge,
          ],
        ),
        if (device.summary.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(device.summary, style: KalinkaTextStyles.trayRowSublabel),
        ],
      ],
    );
    final icon = ExcludeSemantics(
      child: Icon(
        itemIcon(device.medium.iconName),
        size: 24,
        color: KalinkaColors.textSecondary,
      ),
    );
    final chevron = ExcludeSemantics(
      child: Icon(
        Icons.chevron_right,
        key: ValueKey('settings-${device.id}'),
        size: 24,
        color: KalinkaColors.textSecondary,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: settings,
        mouseCursor: clickCursor(interactive: settings != null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Beside the text where both fit; under it on a narrow phone
              // or at large text sizes.
              final beside =
                  constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(400);
              if (beside) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                        if (button != null) ...[
                          const SizedBox(width: 12),
                          button,
                        ],
                        if (device.canEdit) ...[
                          const SizedBox(width: 6),
                          chevron,
                        ],
                      ],
                    ),
                    if (note != null)
                      Padding(
                        padding: EdgeInsets.only(
                          left: 36,
                          top: 10,
                          right: device.canEdit ? 30 : 0,
                        ),
                        child: note,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              text,
                              if (note != null) ...[
                                const SizedBox(height: 10),
                                note,
                              ],
                              if (button != null) ...[
                                const SizedBox(height: 12),
                                button,
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (device.canEdit) ...[const SizedBox(width: 6), chevron],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A mount of [name] that failed: what to do in plain words, with what the
/// mount itself said a tap away where there is more to it.
class _MountFailure extends StatelessWidget {
  final String id;
  final String name;
  final String error;
  final String? detail;
  final VoidCallback? onDismiss;

  const _MountFailure({
    required this.id,
    required this.name,
    required this.error,
    this.detail,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return FailureNote(
      key: ValueKey('failure-$id'),
      message: error,
      onDismiss: onDismiss,
      dismissKey: ValueKey('dismiss-$id'),
      footer: detail == null
          ? null
          // The note may be narrower than the link: beside a dismiss, or at
          // large text sizes.
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: HoverTextAction(
                key: ValueKey('details-$id'),
                label: 'Technical details',
                mono: false,
                trailingIcon: Icons.chevron_right,
                fontSize: KalinkaTypography.baseSize + 1,
                padding: const EdgeInsets.only(top: 6),
                color: KalinkaColors.textSecondary,
                hoverColor: KalinkaColors.textPrimary,
                onTap: () => showKalinkaDialog<void>(
                  context: context,
                  builder: (_) => _DetailsDialog(name: name, detail: detail),
                ),
              ),
            ),
    );
  }
}

class _DetailsDialog extends ConsumerWidget {
  final String name;
  final String detail;

  const _DetailsDialog({required this.name, required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KalinkaDialog(
      side: KalinkaDialogSide.browsing,
      centered: true,
      icon: Icons.info_outline,
      title: 'Technical details',
      message: 'What the mount said when $name failed.',
      content: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceInput,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KalinkaColors.borderDefault),
        ),
        child: SelectableText(
          detail,
          key: const ValueKey('technical-details'),
          style: KalinkaTextStyles.streamInfoValue,
        ),
      ),
      actions: [
        KalinkaButton(
          key: const ValueKey('copy-details'),
          label: 'Copy',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () async {
            final toast = ref.read(toastProvider.notifier);
            try {
              await Clipboard.setData(ClipboardData(text: detail));
              toast.show('Copied');
            } on PlatformException {
              toast.show('Could not copy', isError: true);
            }
          },
        ),
        KalinkaButton(
          label: 'Close',
          fullWidth: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// Asks before a drive or share is unmounted, saying what stays and whether
/// it comes back.
class _UnmountDialog extends StatelessWidget {
  final StorageDevice device;

  const _UnmountDialog({required this.device});

  @override
  Widget build(BuildContext context) {
    final share = device.medium == StorageMedium.network;
    return KalinkaDialog(
      side: KalinkaDialogSide.browsing,
      centered: true,
      icon: Icons.eject_outlined,
      title: 'Unmount “${device.label}”?',
      message: [
        'Music from this ${share ? 'share' : 'drive'} will be unavailable.',
        share
            ? 'Your files and saved connection will be kept.'
            : 'Your files will be kept.',
        if (device.atStart == true)
          'It will mount again after the streamer restarts.',
      ].join(' '),
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          key: const ValueKey('confirm-unmount'),
          label: 'Unmount',
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// A form field in a dialog, on the dialog's own gutter.
Widget _field(String label, Widget control, {String? sublabel}) => SettingsRow(
  label: label,
  sublabel: sublabel,
  isVertical: true,
  gutter: 0,
  control: control,
);

Widget _switch(
  String label,
  Key key,
  bool value,
  ValueChanged<bool> onChanged, {
  String? sublabel,
}) => SettingsRow(
  label: label,
  sublabel: sublabel,
  gutter: 0,
  control: SettingsToggle(key: key, value: value, onChanged: onChanged),
);

Widget _failure(String error) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Text(
    error,
    key: const ValueKey('dialog-error'),
    style: KalinkaTextStyles.trayRowSublabel.copyWith(
      color: KalinkaColors.statusError,
    ),
  ),
);

/// A row of a dialog that acts when tapped: [trailing] hints at how.
class _DialogAction extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _DialogAction({
    super.key,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.labelColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    mouseCursor: clickCursor(interactive: onTap != null),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: KalinkaTextStyles.trayRowLabel.copyWith(
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(sublabel, style: KalinkaTextStyles.trayRowSublabel),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

/// Read-only and the NFS version, folded under one row that says how they
/// are set: few need them, and only when a share will not mount.
class _AdvancedSettings extends StatefulWidget {
  final bool readOnly;
  final ValueChanged<bool> onReadOnly;

  /// Null for a drive, which has none.
  final String? version;
  final ValueChanged<String> onVersion;

  /// A drive pulled out while it is written to may lose what was written.
  final bool removable;

  /// Said under them, such as that a change mounts it again.
  final String? note;

  const _AdvancedSettings({
    required this.readOnly,
    required this.onReadOnly,
    required this.version,
    required this.onVersion,
    this.removable = false,
    this.note,
  });

  @override
  State<_AdvancedSettings> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<_AdvancedSettings> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DialogAction(
          key: const ValueKey('advanced-settings'),
          label: 'Advanced settings',
          sublabel: [
            widget.readOnly ? 'Read-only' : 'Writable',
            if (version != null) 'NFS $version',
          ].join(' · '),
          trailing: Icon(
            _open ? Icons.expand_less : Icons.expand_more,
            color: KalinkaColors.textSecondary,
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open) ...[
          _switch(
            'Read-only',
            const ValueKey('read-only'),
            widget.readOnly,
            widget.onReadOnly,
            sublabel: widget.readOnly
                ? 'Kalinka never writes to it.'
                : widget.removable
                ? 'Kalinka may write to it. Eject it before pulling it out.'
                : 'Kalinka may write to it.',
          ),
          if (version != null)
            _field(
              'NFS version',
              SettingsEnumPills(
                key: const ValueKey('nfs-version'),
                options: _nfsVersions,
                selected: version,
                onChanged: widget.onVersion,
              ),
              sublabel: 'Change it only if the share will not mount.',
            ),
          if (widget.note case final note?)
            Text(note, style: KalinkaTextStyles.trayRowSublabel),
        ],
      ],
    );
  }
}

/// A device's name, Mount after restart and advanced settings, and Forget
/// for one kept. Opened [toMount], it closes with what changed for the row
/// to mount it with; otherwise it saves the changes itself, so a device is
/// never kept by it without being mounted.
class _DeviceDialog extends ConsumerStatefulWidget {
  final StorageDevice device;
  final bool toMount;

  const _DeviceDialog({required this.device, required this.toMount});

  @override
  ConsumerState<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends ConsumerState<_DeviceDialog> {
  StorageDevice get _device => widget.device;

  late String _name = _device.label;
  late bool? _atStart = _device.atStart;
  late bool _readOnly = _savedReadOnly;
  late String? _version = _savedVersion;
  String? _error;
  bool _busy = false;

  bool get _savedReadOnly => _device.readOnly ?? true;

  String? get _savedVersion =>
      _device.nfs == null ? null : _device.nfs!.version ?? _firstNfsVersion;

  bool get _share => _device.medium == StorageMedium.network;

  _Changes get _changes {
    final name = _name.trim();
    return _Changes(
      label: name.isNotEmpty && name != _device.label ? name : null,
      atStart: _atStart != _device.atStart ? _atStart : null,
      readOnly: _readOnly != _savedReadOnly ? _readOnly : null,
      version: _version != _savedVersion ? _version : null,
    );
  }

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(kalinkaProxyProvider)
          .updateStorageDevice(
            _device.id,
            label: changes.label,
            atStart: changes.atStart,
            readOnly: changes.readOnly,
            version: changes.version,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reason(e);
        });
      }
    }
  }

  Future<void> _forget() async {
    final navigator = Navigator.of(context);
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (dialog) => KalinkaDialog(
        side: KalinkaDialogSide.browsing,
        centered: true,
        icon: Icons.delete_outline,
        iconColor: KalinkaColors.actionDelete,
        title: 'Forget “${_device.label}”?',
        message: _share
            ? 'Kalinka unmounts it and removes the saved connection. Your '
                  'files stay untouched.'
            : 'Kalinka unmounts it and stops keeping it. Your files stay '
                  'untouched.',
        actions: [
          KalinkaButton(
            label: 'Cancel',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            onTap: () => Navigator.pop(dialog, false),
          ),
          KalinkaButton(
            key: const ValueKey('confirm-forget'),
            label: 'Forget',
            fullWidth: true,
            onTap: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = ref.read(searchSessionProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(kalinkaProxyProvider).forgetStorageDevice(_device.id);
      session.closeStorageSources();
      if (navigator.mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reason(e);
        });
      }
    }
  }

  /// What switching Mount after restart off leaves a library holding.
  String? get _libraryNote {
    final library = _device.library;
    if (_atStart != false || library == null || !library.holds) return null;
    return '${library.title} keeps its music from here, and finds the folder '
        'missing after a restart until this is mounted again.';
  }

  /// Why Mount is off, where it is.
  String? get _cannotMount {
    if (!widget.toMount || _device.canMount) return null;
    return _device.connected
        ? 'It cannot be mounted now.'
        : 'Plug it in to mount it.';
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final atStart = _atStart;
    return KalinkaDialog(
      side: KalinkaDialogSide.browsing,
      centered: true,
      iconBeside: true,
      icon: itemIcon(device.medium.iconName),
      title: device.label,
      message: [
        device.summary,
        ?device.nfs?.address,
      ].where((line) => line.isNotEmpty).join('\n'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(
            'Name',
            SettingsTextInput(
              key: const ValueKey('device-name'),
              value: device.label,
              onChanged: (name) => _name = name,
            ),
          ),
          if (device.canSetAtStart && atStart != null)
            _switch(
              device.medium == StorageMedium.usb
                  ? 'Mount when plugged in'
                  : 'Mount after restart',
              const ValueKey('at-start'),
              atStart,
              (on) => setState(() => _atStart = on),
              sublabel: _libraryNote,
            ),
          _AdvancedSettings(
            readOnly: _readOnly,
            onReadOnly: (on) => setState(() => _readOnly = on),
            version: _version,
            onVersion: (version) => setState(() => _version = version),
            removable: device.medium == StorageMedium.usb,
            note: device.state == VolumeState.mounted
                ? 'A change here mounts it again.'
                : null,
          ),
          if (device.canForget) ...[
            const Divider(height: 17, color: KalinkaColors.borderSubtle),
            _DialogAction(
              key: const ValueKey('device-forget'),
              label: _share ? 'Forget share' : 'Forget drive',
              labelColor: KalinkaColors.actionDelete,
              sublabel: _share
                  ? 'Remove the saved connection. Files stay untouched.'
                  : 'Kalinka stops keeping it. Files stay untouched.',
              onTap: _busy ? null : _forget,
            ),
          ],
          if (_error case final error?) _failure(error),
          if (_cannotMount case final reason?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(reason, style: KalinkaTextStyles.trayRowSublabel),
            ),
        ],
      ),
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context),
        ),
        if (widget.toMount)
          KalinkaButton(
            key: const ValueKey('device-mount'),
            label: 'Mount',
            fullWidth: true,
            enabled: device.canMount && !_busy,
            onTap: () => Navigator.pop(context, _changes),
          )
        else
          KalinkaButton(
            key: const ValueKey('device-save'),
            label: _busy ? 'Saving…' : 'Save',
            fullWidth: true,
            enabled: !_busy,
            onTap: _save,
          ),
      ],
    );
  }
}

/// An NFS share typed in by its server and folder, mounted at once as set
/// here; the folders the server shares are offered as it is typed. A mount
/// that fails says why here, to be put right, and is put away with the
/// dialog; one still under way says how it went in its row.
class _AddShareDialog extends ConsumerStatefulWidget {
  const _AddShareDialog();

  @override
  ConsumerState<_AddShareDialog> createState() => _AddShareDialogState();
}

class _AddShareDialogState extends ConsumerState<_AddShareDialog> {
  String _host = '';
  String _export = '';
  bool _atStart = true;
  bool _readOnly = true;
  String _version = _firstNfsVersion;
  List<String> _offered = const [];
  Timer? _lookup;
  String? _error;
  DeviceAnswer? _failed;
  bool _busy = false;

  /// The shares this dialog failed to mount, for the server to stop
  /// listing as it closes.
  final _tried = <String>{};

  @override
  void dispose() {
    _lookup?.cancel();
    super.dispose();
  }

  void _hostTyped(String host) {
    setState(() {
      _host = host;
      _offered = const [];
    });
    _lookup?.cancel();
    final name = host.trim();
    if (name.isNotEmpty) {
      _lookup = Timer(shareLookupDelay, () => _lookUp(name));
    }
  }

  Future<void> _lookUp(String host) async {
    try {
      final probe = await ref.read(kalinkaProxyProvider).probeShareHost(host);
      if (mounted && _host.trim() == host) {
        setState(() => _offered = probe.exports);
      }
    } catch (_) {
      // The folder can still be typed; asking only saves typing it.
    }
  }

  Future<void> _putAwayFailures() {
    final api = ref.read(kalinkaProxyProvider);
    final tried = [..._tried];
    _tried.clear();
    return Future.wait([
      for (final id in tried)
        // One tried again since, and mounted, has nothing to put away.
        api.dismissStorageFailure(id).catchError((_) {}),
    ]);
  }

  Future<void> _mount() async {
    final host = _host.trim();
    final export = _export.trim();
    setState(() {
      _busy = true;
      _error = null;
      _failed = null;
    });
    final watch = ref.read(_mountWatchProvider.notifier);
    try {
      await _putAwayFailures();
      final answer = await ref
          .read(kalinkaProxyProvider)
          .addShare(
            host: host,
            export: export,
            version: _version,
            atStart: _atStart,
            readOnly: _readOnly,
          );
      if (answer.state == VolumeState.failed) {
        _tried.add(answer.id);
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = answer;
          });
        }
        return;
      }
      watch.answered(answer);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reason(e);
        });
      }
    }
  }

  String? get _offeredNote => switch (_offered.length) {
    0 => null,
    1 => 'It shares one folder: Browse to pick it.',
    final count => 'It shares $count folders: Browse to pick one.',
  };

  @override
  Widget build(BuildContext context) {
    final ready = _host.trim().isNotEmpty && _export.trim().isNotEmpty;
    final failed = _failed;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_putAwayFailures());
      },
      child: KalinkaDialog(
        side: KalinkaDialogSide.browsing,
        centered: true,
        iconBeside: true,
        icon: Icons.lan_outlined,
        title: 'Add network share',
        message: 'An NFS share on a NAS or another computer.',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(
              'Server',
              SettingsTextInput(
                key: const ValueKey('share-host'),
                value: '',
                hintText: 'nas.local or 192.168.1.20',
                autofocus: true,
                onChanged: _hostTyped,
              ),
            ),
            _field(
              'Folder',
              SettingsComboInput(
                key: const ValueKey('share-export'),
                value: _export,
                hintText: '/volume1/music',
                options: [
                  for (final export in _offered)
                    OptionSpec(value: export, label: export),
                ],
                onChanged: (export) => setState(() => _export = export),
              ),
              sublabel: _offeredNote,
            ),
            _switch(
              'Mount after restart',
              const ValueKey('share-at-start'),
              _atStart,
              (on) => setState(() => _atStart = on),
            ),
            _AdvancedSettings(
              readOnly: _readOnly,
              onReadOnly: (on) => setState(() => _readOnly = on),
              version: _version,
              onVersion: (version) => setState(() => _version = version),
            ),
            if (_error case final error?) _failure(error),
            if (failed != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _MountFailure(
                  id: failed.id,
                  name: '${_host.trim()}:${_export.trim()}',
                  error: failed.error ?? 'It could not be mounted.',
                  detail: failed.errorDetail,
                ),
              ),
          ],
        ),
        actions: [
          KalinkaButton(
            label: 'Cancel',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            onTap: () => Navigator.pop(context),
          ),
          KalinkaButton(
            key: const ValueKey('share-go'),
            label: _busy ? 'Mounting…' : 'Mount',
            fullWidth: true,
            enabled: ready && !_busy,
            onTap: _mount,
          ),
        ],
      ),
    );
  }
}
