/// The server's volumes, and where a Drives folder is on them (API 0.21).
library;

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
