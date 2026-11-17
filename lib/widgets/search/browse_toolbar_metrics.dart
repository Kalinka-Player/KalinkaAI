import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Keep browsing controls anchored to the pane when the page identity changes.
const browseToolbarPadding = EdgeInsets.fromLTRB(6, 2, 6, 2);
const browseToolbarTitleGap = 8.0;
const browseToolbarStatusWidth = 42.0;

/// Folder identity takes priority over an inline search field or action labels.
/// Grow this target with system text size; very narrow panes can fold further.
const browseFolderTrailMinWidth = 300.0;

/// Catalogues and wide albums share a control row, independently of any
/// metadata below it. Compact catalogues put their larger title in this row.
double browseToolbarHeight(
  BuildContext context, {
  required bool compactTitle,
}) => math.max(
  kKalinkaTopBarHeight,
  MediaQuery.textScalerOf(
            context,
          ).scale(compactTitle ? 30 : KalinkaTextStyles.trayTitle.fontSize!) *
          (compactTitle ? 1.1 : 1.5) +
      browseToolbarPadding.vertical,
);
