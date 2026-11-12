import 'package:flutter/widgets.dart';

/// Compact headers and denser content where the pane has enough width.
/// Text scaling increases the required room; window height is not a mode.
/// The player additionally checks that its metadata and controls fit vertically.
bool compactPaneLayout(double width, TextScaler textScaler) =>
    width >= 720 * (textScaler.scale(16) / 16).clamp(1.0, double.infinity);
