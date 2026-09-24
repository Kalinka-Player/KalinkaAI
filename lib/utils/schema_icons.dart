import 'package:flutter/material.dart';

/// The icon for a material icon name the backend sends, or null for one this
/// app does not draw. Only names the backend actually emits need entries.
IconData? iconNamed(String? name) => switch (name) {
  'folder_outlined' => Icons.folder_outlined,
  'lan_outlined' => Icons.lan_outlined,
  'music_note_outlined' => Icons.music_note_outlined,
  'speaker_outlined' => Icons.speaker_outlined,
  'waves_outlined' => Icons.waves_outlined,
  'extension_outlined' => Icons.extension_outlined,
  _ => null,
};
