/// The server's volumes, where a Drives folder is on them (API 0.21), and
/// the drives and shares it could mount (API 0.22).
library;

import 'dart:convert';

enum VolumeKind { removable, mount, internal }

enum VolumeState { mounted, mounting, failed, unmounted }

T _named<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

/// What the library makes of a whole volume.
class VolumeLibrary {
  final String module;
  final String title;
  final bool holds;
  final bool libraryEmpty;

  const VolumeLibrary({
    required this.module,
    required this.title,
    required this.holds,
    required this.libraryEmpty,
  });

  factory VolumeLibrary.fromJson(Map<String, dynamic> json) => VolumeLibrary(
    module: json['module'] as String? ?? '',
    title: json['title'] as String? ?? '',
    holds: json['holds'] as bool? ?? false,
    libraryEmpty: json['library_empty'] as bool? ?? false,
  );
}

/// One volume: the server's music folder, a drive, or a mounted share.
class StorageVolume {
  final String id;
  final VolumeKind kind;
  final String label;
  final String mountPoint;
  final VolumeState state;
  final String? fsType;
  final int? sizeBytes;
  final int? freeBytes;
  final String? bus;
  final String? error;
  final VolumeLibrary? library;

  /// What to show under the label: its kind and size, "USB drive · 31 GB".
  final String? summary;

  const StorageVolume({
    required this.id,
    required this.kind,
    required this.label,
    required this.mountPoint,
    this.state = VolumeState.mounted,
    this.fsType,
    this.sizeBytes,
    this.freeBytes,
    this.bus,
    this.error,
    this.library,
    this.summary,
  });

  bool get isRemovable => kind == VolumeKind.removable;
  bool get isMounted => state == VolumeState.mounted;

  factory StorageVolume.fromJson(Map<String, dynamic> json) => StorageVolume(
    id: json['id'] as String,
    kind: _named(VolumeKind.values, json['kind'], VolumeKind.mount),
    label: json['label'] as String? ?? json['id'] as String,
    mountPoint: json['mount_point'] as String? ?? '',
    state: _named(VolumeState.values, json['state'], VolumeState.mounted),
    fsType: json['fs_type'] as String?,
    sizeBytes: _int(json['size_bytes']),
    freeBytes: _int(json['free_bytes']),
    bus: json['bus'] as String?,
    error: json['error'] as String?,
    summary: json['summary'] as String?,
    library: json['library'] is Map
        ? VolumeLibrary.fromJson(Map<String, dynamic>.from(json['library']))
        : null,
  );

  static List<StorageVolume> listFromJson(Object? json) => [
    for (final v in (json as List?) ?? const [])
      StorageVolume.fromJson(Map<String, dynamic>.from(v as Map)),
  ];
}

/// The library that answers for a location, and what it makes of it.
class LocationLibrary {
  final String module;
  final String title;
  final bool holds;
  final bool libraryEmpty;

  /// One of the library's sources is exactly this folder, which taking it
  /// out removes; false when it is held through a folder above it.
  final bool removable;

  /// Whether the library reads a folder added to it, or stops reading one
  /// taken out, only after a restart.
  final bool restartRequired;

  const LocationLibrary({
    required this.module,
    required this.title,
    required this.holds,
    required this.libraryEmpty,
    this.removable = false,
    this.restartRequired = false,
  });

  factory LocationLibrary.fromJson(Map<String, dynamic> json) =>
      LocationLibrary(
        module: json['module'] as String? ?? '',
        title: json['title'] as String? ?? '',
        holds: json['holds'] as bool? ?? false,
        libraryEmpty: json['library_empty'] as bool? ?? false,
        removable: json['removable'] as bool? ?? false,
        restartRequired: json['restart_required'] as bool? ?? false,
      );
}

/// Where a Drives page is: which volume, and what a library makes of it.
class StorageLocation {
  final String? volumeId;
  final String subpath;
  final String label;
  final String path;
  final LocationLibrary? library;

  const StorageLocation({
    this.volumeId,
    this.subpath = '',
    this.label = '',
    required this.path,
    this.library,
  });

  factory StorageLocation.fromJson(Map<String, dynamic> json) =>
      StorageLocation(
        volumeId: json['volume_id'] as String?,
        subpath: json['subpath'] as String? ?? '',
        label: json['label'] as String? ?? '',
        path: json['path'] as String? ?? '',
        library: json['library'] is Map
            ? LocationLibrary.fromJson(
                Map<String, dynamic>.from(json['library']),
              )
            : null,
      );
}

/// What adding a folder to a library came to.
class AdoptResult {
  final String module;
  final bool restartRequired;

  const AdoptResult({required this.module, required this.restartRequired});

  factory AdoptResult.fromJson(Map<String, dynamic> json) => AdoptResult(
    module: json['module'] as String? ?? '',
    restartRequired: json['restart_required'] as bool? ?? false,
  );
}

/// A folder on the server, as Settings picks a music folder from them.
class ServerFolder {
  final String path;
  final String name;
  final String? subname;

  /// What to draw beside it, as a browse row's `icon` names it.
  final String? icon;

  const ServerFolder({
    required this.path,
    required this.name,
    this.subname,
    this.icon,
  });

  factory ServerFolder.fromJson(Map<String, dynamic> json) => ServerFolder(
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    subname: json['subname'] as String?,
    icon: json['icon'] as String?,
  );
}

/// One page of the folders in a folder, or of the places folders are in.
class ServerFolderList {
  final int total;
  final List<ServerFolder> folders;

  const ServerFolderList({required this.total, required this.folders});

  factory ServerFolderList.fromJson(Map<String, dynamic> json) =>
      ServerFolderList(
        total: _int(json['total']) ?? 0,
        folders: [
          for (final folder in (json['folders'] as List?) ?? const [])
            ServerFolder.fromJson(Map<String, dynamic>.from(folder as Map)),
        ],
      );
}

/// Where a device is: what Drives & shares groups it under, and draws it as.
enum StorageMedium {
  internal,
  disk,
  usb,
  network;

  /// The icon a browse row names for it, for `itemIcon`.
  String get iconName => switch (this) {
    internal => 'internal_storage',
    disk => 'disk',
    usb => 'usb_drive',
    network => 'network_share',
  };
}

/// The host and export of a share.
class NfsTarget {
  final String host;
  final String export;
  final String? version;

  const NfsTarget({required this.host, required this.export, this.version});

  /// Where a mount finds it: `host:/export`.
  String get address => '$host:$export';

  factory NfsTarget.fromJson(Map<String, dynamic> json) => NfsTarget(
    host: json['host'] as String? ?? '',
    export: json['export'] as String? ?? '',
    version: json['version'] as String?,
  );
}

/// One row of Drives & shares: a drive or share the server could play from,
/// mounted or not (API 0.22).
///
/// The `can*` flags are what the server allows now; the screen offers those
/// and works none out for itself.
class StorageDevice {
  final String id;
  final StorageMedium medium;
  final String label;
  final String summary;
  final VolumeState state;

  /// Why it failed to mount, in plain words.
  final String? error;

  /// What the mount itself said, where there is more to it than [error].
  final String? errorDetail;

  /// Mounted by the system, as an fstab entry or a desktop mounts it, and so
  /// not Kalinka's to mount or unmount.
  final bool bySystem;
  final bool saved;

  /// The Mount after restart switch, null where there is none.
  final bool? atStart;

  /// False for a saved drive that is not plugged in.
  final bool connected;

  /// For a share: whether the last search saw it.
  final bool? found;
  final bool? readOnly;
  final NfsTarget? nfs;

  /// What the host of a found share calls itself.
  final String? server;

  /// Who a found share lets in, as its host says.
  final List<String> clients;
  final VolumeLibrary? library;
  final bool canMount;
  final bool canUnmount;
  final bool canEject;
  final bool canSetAtStart;

  /// Whether it has settings to change: a name, read-only, a version.
  final bool canEdit;
  final bool canForget;

  /// A device not kept whose mount failed: the failure can be put away.
  final bool canDismiss;

  const StorageDevice({
    required this.id,
    required this.medium,
    required this.label,
    this.summary = '',
    this.state = VolumeState.unmounted,
    this.error,
    this.errorDetail,
    this.bySystem = false,
    this.saved = false,
    this.atStart,
    this.connected = true,
    this.found,
    this.readOnly,
    this.nfs,
    this.server,
    this.clients = const [],
    this.library,
    this.canMount = false,
    this.canUnmount = false,
    this.canEject = false,
    this.canSetAtStart = false,
    this.canEdit = false,
    this.canForget = false,
    this.canDismiss = false,
  });

  /// A share the search found that is not saved yet.
  bool get isFoundShare =>
      medium == StorageMedium.network && !saved && !bySystem;

  factory StorageDevice.fromJson(Map<String, dynamic> json) => StorageDevice(
    id: json['id'] as String,
    medium: _named(StorageMedium.values, json['medium'], StorageMedium.disk),
    label: json['label'] as String? ?? json['id'] as String,
    summary: json['summary'] as String? ?? '',
    state: _named(VolumeState.values, json['state'], VolumeState.unmounted),
    error: json['error'] as String?,
    errorDetail: json['error_detail'] as String?,
    bySystem: json['managed_by'] == 'system',
    saved: json['saved'] as bool? ?? false,
    atStart: json['at_start'] as bool?,
    connected: json['connected'] as bool? ?? true,
    found: json['found'] as bool?,
    readOnly: json['read_only'] as bool?,
    nfs: json['nfs'] is Map
        ? NfsTarget.fromJson(Map<String, dynamic>.from(json['nfs']))
        : null,
    server: json['server'] as String?,
    clients: [
      for (final client in (json['clients'] as List?) ?? const [])
        client.toString(),
    ],
    library: json['library'] is Map
        ? VolumeLibrary.fromJson(Map<String, dynamic>.from(json['library']))
        : null,
    canMount: json['can_mount'] as bool? ?? false,
    canUnmount: json['can_unmount'] as bool? ?? false,
    canEject: json['can_eject'] as bool? ?? false,
    canSetAtStart: json['can_set_at_start'] as bool? ?? false,
    canEdit: json['can_edit'] as bool? ?? false,
    canForget: json['can_forget'] as bool? ?? false,
    canDismiss: json['can_dismiss'] as bool? ?? false,
  );
}

/// Where a device stands once the server answered a mount: [VolumeState.mounting]
/// while it is still under way, [VolumeState.failed] with the reason.
class DeviceAnswer {
  final String id;
  final VolumeState state;
  final String? error;

  /// What the mount itself said, where there is more to it than [error].
  final String? errorDetail;

  const DeviceAnswer({
    required this.id,
    required this.state,
    this.error,
    this.errorDetail,
  });

  factory DeviceAnswer.fromJson(Map<String, dynamic> json) => DeviceAnswer(
    id: json['id'] as String,
    state: _named(VolumeState.values, json['state'], VolumeState.mounting),
    error: json['error'] as String?,
    errorDetail: json['error_detail'] as String?,
  );
}

/// Every device, and whether the search for shares is still running.
///
/// Two lists read from the same answer are equal, so asking again rebuilds
/// nothing until something changed.
class StorageDeviceList {
  final List<StorageDevice> devices;
  final bool scanning;

  /// False where the server has no mount helper, and nothing can be mounted.
  final bool mountingAvailable;
  final String _answer;

  const StorageDeviceList({
    this.devices = const [],
    this.scanning = false,
    this.mountingAvailable = true,
  }) : _answer = '';

  StorageDeviceList._read(
    this.devices,
    this.scanning,
    this.mountingAvailable,
    this._answer,
  );

  factory StorageDeviceList.fromJson(Map<String, dynamic> json) =>
      StorageDeviceList._read(
        [
          for (final d in (json['devices'] as List?) ?? const [])
            StorageDevice.fromJson(Map<String, dynamic>.from(d as Map)),
        ],
        json['scan'] is Map && json['scan']['running'] == true,
        json['mounting_available'] != false,
        jsonEncode(json),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageDeviceList &&
          _answer.isNotEmpty &&
          _answer == other._answer;

  @override
  int get hashCode => _answer.hashCode;
}

/// What a host said when asked for its NFS exports.
class ShareProbe {
  final String host;
  final bool reachable;
  final String? error;
  final List<String> exports;

  const ShareProbe({
    required this.host,
    this.reachable = false,
    this.error,
    this.exports = const [],
  });

  factory ShareProbe.fromJson(Map<String, dynamic> json) => ShareProbe(
    host: json['host'] as String? ?? '',
    reachable: json['reachable'] as bool? ?? false,
    error: json['error'] as String?,
    exports: [
      for (final e in (json['exports'] as List?) ?? const [])
        if (e is Map && e['export'] is String) e['export'] as String,
    ],
  );
}
