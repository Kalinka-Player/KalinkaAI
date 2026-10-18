import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connection_settings_provider.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../configuration_appearance.dart';
import '../tap_highlight.dart';
import '../sheet_anchor.dart';
import 'catalog_pin_button.dart';
import 'home_preview_choices.dart';

/// An anchored visual layout picker; choices save immediately and restart its idle timer.
class HomePreviewSwitch extends ConsumerStatefulWidget {
  final PinnedCatalog pin;
  final ValueChanged<VoidCallback?> onMenuChanged;
  const HomePreviewSwitch({
    super.key,
    required this.pin,
    required this.onMenuChanged,
  });

  @override
  ConsumerState<HomePreviewSwitch> createState() => _HomePreviewSwitchState();
}

class _HomePreviewSwitchState extends ConsumerState<HomePreviewSwitch> {
  final _menu = MenuController();
  final _buttonFocus = FocusNode();
  Timer? _idle;
  Uri? _openedServer;

  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 3), () {
      if (mounted && _menu.isOpen) _menu.close();
    });
  }

  void _opened() {
    _openedServer = ref.read(connectionSettingsProvider).baseUrl;
    widget.onMenuChanged(_menu.close);
    _resetIdle();
  }

  void _closed() {
    _idle?.cancel();
    widget.onMenuChanged(null);
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.onMenuChanged(null);
    _buttonFocus.dispose();
    super.dispose();
  }

  void _select(HomePreviewType type) {
    if (ref.read(connectionSettingsProvider).baseUrl != _openedServer) {
      _menu.close();
      return;
    }
    _resetIdle();
    saveHomeChange(
      context,
      ref
          .read(pinnedCatalogsProvider.notifier)
          .setPreview(widget.pin.key, type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final insets = SheetAnchor.paddingFor(
      SheetAnchor.elementOf(context),
      viewport.width,
    );
    final menuWidth =
        (viewport.width -
                insets.horizontal -
                2 * ConfigurationAppearance.gutter(context))
            .clamp(0.0, 500.0);
    final sourceColor =
        ref
            .watch(sourceDisplayInfoProvider)[sourceOfId(widget.pin.page.id!)]
            ?.color ??
        KalinkaColors.accent;
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _buttonFocus,
      consumeOutsideTap: true,
      onOpen: _opened,
      onClose: _closed,
      // The menu origin is its leading edge. Align its trailing edge with the
      // row's Unpin action, keeping both edges inside the panel's gutters.
      alignmentOffset: Offset(48 - menuWidth, 8),
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(
          Size(menuWidth, viewport.height * .7),
        ),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(
          KalinkaColors.surfaceRaised,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: KalinkaColors.borderDefault),
          ),
        ),
        alignment: AlignmentDirectional.bottomEnd,
      ),
      menuChildren: [
        Listener(
          onPointerDown: (_) => _resetIdle(),
          onPointerSignal: (_) => _resetIdle(),
          child: MouseRegion(
            onHover: (_) => _resetIdle(),
            child: Focus(
              onKeyEvent: (_, _) {
                _resetIdle();
                return KeyEventResult.ignored;
              },
              child: SizedBox(
                key: const ValueKey('home-preview-switch-menu'),
                width: (menuWidth - 24).clamp(0.0, 476.0),
                child: HomePreviewGrid(
                  width: (menuWidth - 24).clamp(0.0, 476.0),
                  selected: widget.pin.preview,
                  sourceColor: sourceColor,
                  onSelected: _select,
                ),
              ),
            ),
          ),
        ),
      ],
      builder: (_, controller, _) => IconButton(
        focusNode: _buttonFocus,
        tooltip: 'Preview for ${widget.pin.page.title ?? 'Catalog'}',
        style: kalinkaIconButtonStyle.copyWith(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          // Returning null falls back to IconButton's focused overlay. MenuAnchor
          // restores focus after closing, so explicitly clear all idle states.
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => kalinkaOverlay.resolve(states) ?? Colors.transparent,
          ),
        ),
        icon: Icon(homePreviewIcon(widget.pin.preview), size: 22),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
