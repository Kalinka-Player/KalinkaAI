import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Stable Tab order, independent of the shell's responsive widget order.
enum AppKeyboardArea { navigation, toolbar, content, playback, player }

/// Explicit navigation while a text editor owns the ordinary arrow keys.
class _AreaDirectionIntent extends Intent {
  const _AreaDirectionIntent(this.direction);
  final TraversalDirection direction;
}

/// Shares the visible areas between the shell and a player route beside its rail.
class AppKeyboardNavigationController {
  final _regions = <_KeyboardRegionState>{};
  final _lastRegion = <AppKeyboardArea, _KeyboardRegionState>{};
}

/// Tab selects an area; arrows select controls inside that area. Local focus
/// scopes (menus, editors and dialogs) retain their normal traversal.
class AppKeyboardNavigation extends StatefulWidget {
  const AppKeyboardNavigation({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final AppKeyboardNavigationController? controller;

  @override
  State<AppKeyboardNavigation> createState() => _AppKeyboardNavigationState();
}

class _AppKeyboardNavigationState extends State<AppKeyboardNavigation> {
  final _entry = FocusNode(
    debugLabel: 'App keyboard navigation',
    skipTraversal: true,
  );
  late final _controller =
      widget.controller ?? AppKeyboardNavigationController();
  Set<_KeyboardRegionState> get _regions => _controller._regions;
  Map<AppKeyboardArea, _KeyboardRegionState> get _lastRegion =>
      _controller._lastRegion;

  Iterable<FocusNode> _targets(AppKeyboardArea area) =>
      _regions.where((r) => r.widget.area == area).expand((r) => r.nodes);

  void _unregister(_KeyboardRegionState region) {
    _regions.remove(region);
    _lastRegion.removeWhere((_, value) => value == region);
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_rememberFocus);
  }

  _KeyboardRegionState? _regionOf(FocusNode? node) {
    for (final region in _regions) {
      if (node?.nearestScope == region.scope) return region;
    }
    return null;
  }

  void _rememberFocus() {
    final node = FocusManager.instance.primaryFocus;
    final region = _regionOf(node);
    if (region != null &&
        node != null &&
        node is! FocusScopeNode &&
        !node.skipTraversal) {
      region.lastFocus = node;
      _lastRegion[region.widget.area] = region;
    }
  }

  void _tab(bool forward) {
    final node = FocusManager.instance.primaryFocus;
    final current = _regionOf(node);
    if (current == null && node != _entry) {
      // An unregistered scope inside the shell belongs to a local overlay.
      if (forward) {
        node?.nextFocus();
      } else {
        node?.previousFocus();
      }
      return;
    }
    // One Tab stop per logical area, even when the fixed bar and scrolling
    // page header live in different focus scopes.
    const areas = AppKeyboardArea.values;
    var index = current?.widget.area.index ?? (forward ? -1 : 0);
    for (var i = 0; i < areas.length; i++) {
      index = (index + (forward ? 1 : -1)) % areas.length;
      final area = areas[index];
      final region = _lastRegion[area];
      final remembered = region?.lastFocus;
      if (region != null &&
          remembered != null &&
          region.nodes.contains(remembered)) {
        region._focus(remembered);
        return;
      }
      final candidates = _targets(area).toList();
      if (candidates.isEmpty) continue;
      final first = ReadingOrderTraversalPolicy()
          .sortDescendants(candidates, _entry.nearestScope!)
          .first;
      _regionOf(first)!._focus(first);
      return;
    }
  }

  void _arrow(TraversalDirection direction) {
    final node = FocusManager.instance.primaryFocus;
    final region = _regionOf(node);
    if (region != null) {
      region.move(node!, direction);
    } else if (node == _entry) {
      _tab(true);
    } else {
      node?.focusInDirection(direction);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_rememberFocus);
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _KeyboardHost(
    state: this,
    child: Shortcuts(
      // Explicit arrows also give macOS spatial navigation instead of its
      // default arrow-to-scroll bindings. EditableText's nearer shortcuts win.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.tab, shift: true):
            PreviousFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
        ),
        SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
          TraversalDirection.left,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
          TraversalDirection.right,
        ),
      },
      child: DefaultTextEditingShortcuts(
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                _AreaDirectionIntent(TraversalDirection.up),
            SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                _AreaDirectionIntent(TraversalDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                _AreaDirectionIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
                _AreaDirectionIntent(TraversalDirection.right),
          },
          child: Actions(
            actions: {
              _AreaDirectionIntent: CallbackAction<_AreaDirectionIntent>(
                onInvoke: (intent) => _arrow(intent.direction),
              ),
              NextFocusIntent: CallbackAction<NextFocusIntent>(
                onInvoke: (_) => _tab(true),
              ),
              PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
                onInvoke: (_) => _tab(false),
              ),
              DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
                onInvoke: (intent) => _arrow(intent.direction),
              ),
            },
            child: Focus(
              autofocus: true,
              focusNode: _entry,
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _KeyboardHost extends InheritedWidget {
  const _KeyboardHost({required this.state, required super.child});
  final _AppKeyboardNavigationState state;

  @override
  bool updateShouldNotify(_KeyboardHost oldWidget) => state != oldWidget.state;
}

/// Marks a shell area without changing its layout or focus decoration. It is
/// transparent outside [AppKeyboardNavigation], including standalone dialogs.
class AppKeyboardRegion extends StatelessWidget {
  const AppKeyboardRegion({
    super.key,
    required this.area,
    required this.child,
    this.bottomInset = 0,
  });

  final AppKeyboardArea area;
  final Widget child;

  /// Content may paint under a fixed bar, but focus must remain above it.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final host = context.dependOnInheritedWidgetOfExactType<_KeyboardHost>();
    final parent = context.dependOnInheritedWidgetOfExactType<_RegionMarker>();
    if (host == null || parent?.area == area) return child;
    return _KeyboardRegion(
      host: host.state,
      area: area,
      bottomInset: bottomInset,
      child: child,
    );
  }
}

class _RegionMarker extends InheritedWidget {
  const _RegionMarker({required this.area, required super.child});
  final AppKeyboardArea area;

  @override
  bool updateShouldNotify(_RegionMarker oldWidget) => area != oldWidget.area;
}

class _KeyboardRegion extends StatefulWidget {
  const _KeyboardRegion({
    required this.host,
    required this.area,
    required this.bottomInset,
    required this.child,
  });
  final _AppKeyboardNavigationState host;
  final AppKeyboardArea area;
  final double bottomInset;
  final Widget child;

  @override
  State<_KeyboardRegion> createState() => _KeyboardRegionState();
}

class _KeyboardRegionState extends State<_KeyboardRegion> {
  late final scope = FocusScopeNode(debugLabel: widget.area.name);
  FocusNode? lastFocus;

  Iterable<FocusNode> get nodes sync* {
    if (!scope.canRequestFocus || !scope.descendantsAreTraversable) return;
    // Parked visits, covered pages and nested areas can have entire lists of
    // mounted controls. Skip those branches before looking up any bounds.
    final pending = scope.children.toList().reversed.toList();
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node is FocusScopeNode) continue;
      if (node.descendantsAreFocusable && node.descendantsAreTraversable) {
        pending.addAll(node.children.toList().reversed);
      }
      if (node.skipTraversal || !node.canRequestFocus) continue;
      final render = node.context?.findRenderObject();
      if (render is RenderBox &&
          render.attached &&
          render.hasSize &&
          !render.size.isEmpty) {
        yield node;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    widget.host._regions.add(this);
  }

  @override
  void didUpdateWidget(_KeyboardRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      oldWidget.host._unregister(this);
      widget.host._regions.add(this);
    }
  }

  void _focus(FocusNode node) {
    lastFocus = node;
    node.requestFocus();
    // Reveal both edges, including when returning to an area after pointer
    // scrolling. Zero duration keeps held arrows responsive and respects
    // reduced motion. Flutter accounts for pinned slivers in this reveal.
    Scrollable.ensureVisible(
      node.context!,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    Scrollable.ensureVisible(
      node.context!,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    if (widget.bottomInset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !node.hasPrimaryFocus || node.context == null) return;
        final box = context.findRenderObject();
        final scroll = Scrollable.maybeOf(node.context!, axis: Axis.vertical);
        if (box is! RenderBox || scroll == null) return;
        final targetBottom = box.globalToLocal(node.rect.bottomCenter).dy;
        final overlap = targetBottom - (box.size.height - widget.bottomInset);
        if (overlap <= 0) return;
        final position = scroll.position;
        final offset =
            position.pixels +
            (axisDirectionIsReversed(position.axisDirection)
                ? -overlap
                : overlap);
        position.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      });
    }
  }

  void move(
    FocusNode from,
    TraversalDirection direction, {
    bool afterScroll = false,
  }) {
    final vertical =
        direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    final forward =
        direction == TraversalDirection.down ||
        direction == TraversalDirection.right;
    final axis = vertical ? Axis.vertical : Axis.horizontal;
    // Keep distances in the same logical units as the scroll position.
    final host = widget.host.context.findRenderObject();
    // Sibling controls share the viewport's transform to the host.
    // Recompute it on the next keypress so scrolling and resizing stay exact.
    final transforms = <RenderAbstractViewport, Matrix4>{};
    Rect boundsOf(FocusNode node) {
      final render = node.context!.findRenderObject()!;
      final viewport = RenderAbstractViewport.maybeOf(render);
      final transform = viewport == null
          ? render.getTransformTo(host)
          : transforms
                .putIfAbsent(viewport, () => viewport.getTransformTo(host))
                .multiplied(render.getTransformTo(viewport));
      return MatrixUtils.transformRect(transform, render.semanticBounds);
    }

    final origin = boundsOf(from);
    final scrollable = Scrollable.maybeOf(from.context!, axis: axis);
    // Compare each target once. FocusNode.rect walks the render tree to
    // account for scroll and transforms, so keep it out of a sort comparator.
    FocusNode? best;
    var bestSameScroll = false;
    var bestGap = double.infinity;
    var bestAlong = double.infinity;
    var bestDistance = double.infinity;
    for (final node in widget.host._targets(widget.area)) {
      if (node == from) continue;
      final rect = boundsOf(node);
      final displacement = rect.center - origin.center;
      final delta = vertical ? displacement.dy : displacement.dx;
      final along = forward ? delta : -delta;
      if (along <= 1) continue;
      final sameScroll =
          scrollable == null ||
          Scrollable.maybeOf(node.context!, axis: axis) == scrollable;
      if (bestSameScroll && !sameScroll) continue;
      final horizontalGap = math.max(
        origin.left - rect.right,
        rect.left - origin.right,
      );
      final verticalGap = math.max(
        origin.top - rect.bottom,
        rect.top - origin.bottom,
      );
      final crossGap = vertical ? horizontalGap : verticalGap;
      final alongGap = vertical ? verticalGap : horizontalGap;
      // Touching edges belong to different rows or columns. A taller card
      // alongside this one is reachable with Left/Right even at the top row.
      if (crossGap > -1 && alongGap < -1) continue;
      final gap = math.max(0.0, crossGap + 1);
      final distance = displacement.distanceSquared;
      if (sameScroll == bestSameScroll &&
          (gap > bestGap ||
              (gap == bestGap &&
                  (along > bestAlong ||
                      (along == bestAlong && distance >= bestDistance))))) {
        continue;
      }
      best = node;
      bestSameScroll = sameScroll;
      bestGap = gap;
      bestAlong = along;
      bestDistance = distance;
    }

    if (best != null && bestSameScroll) {
      widget.host._regionOf(best)!._focus(best);
      return;
    }
    // Lazy lists may not have built the next row yet (especially with a zero
    // cache extent). Advance their viewport, then try the newly built controls
    // on the next frame before considering controls outside that scrollable.
    // A scrolling toolbar fragment shares its vertical viewport with the
    // listing. Its boundary should not scroll through unrelated content.
    final canPage = !vertical || widget.area != AppKeyboardArea.toolbar;
    if (canPage && scrollable != null && !afterScroll) {
      final position = scrollable.position;
      final increasing =
          forward != axisDirectionIsReversed(position.axisDirection);
      final step = math
          .max(48.0, vertical ? origin.height : origin.width)
          .clamp(1.0, math.max(1.0, position.viewportDimension / 2));
      final offset = (position.pixels + (increasing ? step : -step)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((offset - position.pixels).abs() > 0.5) {
        position.jumpTo(offset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && from.context != null && from.hasPrimaryFocus) {
            move(from, direction, afterScroll: true);
          }
        });
        return;
      }
    }
    if (best != null) {
      widget.host._regionOf(best)!._focus(best);
    }
    // At an area's edge keep focus in place; only Tab changes area.
  }

  @override
  void dispose() {
    widget.host._unregister(this);
    scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RegionMarker(
    area: widget.area,
    child: FocusScope(node: scope, child: widget.child),
  );
}

/// Arrow keys navigate past sliders until Enter/Space starts adjustment, in
/// both the shell and standalone routes/popups. Pointer adjustment stays direct.
class AppKeyboardSlider extends StatelessWidget {
  const AppKeyboardSlider({super.key, required Slider this.child})
    : onIncrease = null,
      onDecrease = null,
      inlineHint = false,
      _custom = false;

  /// Adds the same interaction to a painted slider with its own drag gestures.
  const AppKeyboardSlider.custom({
    super.key,
    required this.child,
    required this.onIncrease,
    required this.onDecrease,
    this.inlineHint = false,
  }) : _custom = true;

  final Widget child;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final bool _custom;

  /// Keep the hint inside a floating control positioned after layout.
  final bool inlineHint;

  @override
  Widget build(BuildContext context) => _KeyboardEditor(
    host: context.dependOnInheritedWidgetOfExactType<_KeyboardHost>()?.state,
    kind: _custom ? _EditorKind.customSlider : _EditorKind.slider,
    enabled: _custom
        ? onIncrease != null || onDecrease != null
        : (child as Slider).onChanged != null,
    onIncrease: onIncrease,
    onDecrease: onDecrease,
    inlineHint: inlineHint,
    child: child,
  );
}

/// A navigation target around an editable field. Keyboard traversal does not
/// start typing; Enter does. Pointer focus, autofocus and explicit focus
/// requests still enter the original editor without replacing its state.
class AppKeyboardTextEntry extends StatelessWidget {
  const AppKeyboardTextEntry({super.key, required this.child});
  final Widget child;

  /// Let the on-screen keyboard's early Escape handler finish this edit before
  /// it dismisses its input client and loses the field's navigation target.
  static bool finishEditing() {
    final editor = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<_KeyboardEditorState>();
    if (editor == null || !editor._editing) return false;
    editor._setEditing(false);
    return true;
  }

  @override
  Widget build(BuildContext context) => _KeyboardEditor(
    host: context.dependOnInheritedWidgetOfExactType<_KeyboardHost>()?.state,
    kind: _EditorKind.text,
    enabled: switch (child) {
      TextField(:final enabled, :final decoration) =>
        enabled ?? decoration?.enabled ?? true,
      TextFormField(:final enabled) => enabled,
      _ => true,
    },
    child: child,
  );
}

enum _EditorKind { text, slider, customSlider }

class _KeyboardEditor extends StatefulWidget {
  const _KeyboardEditor({
    required this.host,
    required this.kind,
    required this.child,
    required this.enabled,
    this.onIncrease,
    this.onDecrease,
    this.inlineHint = false,
  });
  final _AppKeyboardNavigationState? host;
  final _EditorKind kind;
  final Widget child;
  final bool enabled;
  final bool inlineHint;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  @override
  State<_KeyboardEditor> createState() => _KeyboardEditorState();
}

class _KeyboardEditorState extends State<_KeyboardEditor> {
  late final _navigationFocus = FocusNode(
    debugLabel: widget.kind == _EditorKind.text
        ? 'Text entry navigation'
        : 'Slider navigation',
  );
  final _hint = GlobalKey<TooltipState>();
  bool _editing = false;
  bool _pendingNativeFocus = false;
  // Desktop focus highlights also fire for mouse clicks. Only show this
  // wrapper's extra cues for keyboard traversal or explicit keyboard editing.
  bool _keyboardCues = false;

  void _setKeyboardCues(bool visible) {
    if (_keyboardCues == visible) return;
    setState(() => _keyboardCues = visible);
    if (visible) _showHint();
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_syncFocus);
  }

  void _showHint() {
    if (widget.inlineHint) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboardCues) _hint.currentState?.ensureTooltipVisible();
    });
  }

  void _updateEditing(bool editing) {
    if (_editing == editing) return;
    // In ordinary dialog Tab traversal, omit the outer target while its native
    // editor is focused so Tab goes straight to the next control.
    _navigationFocus.skipTraversal =
        editing && widget.kind != _EditorKind.customSlider;
    setState(() => _editing = editing);
    _showHint();
  }

  void _setEditing(bool editing) {
    if (!widget.enabled || _editing == editing) return;
    _setKeyboardCues(true);
    if (!editing) _navigationFocus.requestFocus();
    _pendingNativeFocus = editing && widget.kind != _EditorKind.customSlider;
    _updateEditing(editing);
    if (_pendingNativeFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editing && _navigationFocus.hasFocus) {
          final candidates = _navigationFocus.descendants.where(
            (node) => node.canRequestFocus && node is! FocusScopeNode,
          );
          // TextFormField may contain a suffix button. Enter the editor itself.
          final target = widget.kind == _EditorKind.text
              ? candidates
                    .where(
                      (node) =>
                          node.context
                              ?.findAncestorWidgetOfExactType<EditableText>() !=
                          null,
                    )
                    .firstOrNull
              : candidates.firstOrNull;
          target?.requestFocus();
        }
        _pendingNativeFocus = false;
      });
    }
  }

  void _syncFocus() {
    if (!mounted) return;
    if (_navigationFocus.hasFocus) {
      if (_navigationFocus.hasPrimaryFocus) {
        _setKeyboardCues(true);
      } else if (!_editing) {
        // Direct focus (a tap, autofocus or requestFocus) enters the native
        // editor without first activating the keyboard navigation target.
        _setKeyboardCues(false);
      }
      if (widget.kind != _EditorKind.customSlider && !_pendingNativeFocus) {
        _updateEditing(!_navigationFocus.hasPrimaryFocus);
      }
      return;
    }
    _setKeyboardCues(false);
    if (!_editing) return;
    _updateEditing(false);
    final region = widget.host?._regionOf(_navigationFocus);
    if (region != null &&
        _navigationFocus.descendants.contains(region.lastFocus)) {
      region.lastFocus = _navigationFocus;
    }
  }

  void _arrow(TraversalDirection direction) {
    if (_editing &&
        widget.kind == _EditorKind.customSlider &&
        (direction == TraversalDirection.left ||
            direction == TraversalDirection.right)) {
      final increase =
          (direction == TraversalDirection.right) ==
          (Directionality.of(context) == TextDirection.ltr);
      (increase ? widget.onIncrease : widget.onDecrease)?.call();
      return;
    }
    final host = widget.host;
    if (host != null) {
      host._arrow(direction);
    } else {
      FocusManager.instance.primaryFocus?.focusInDirection(direction);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncFocus);
    _navigationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.kind == _EditorKind.text;
    final hint = text
        ? (_editing ? 'Esc to finish editing' : 'Enter to edit')
        : (_editing
              ? 'Left/Right to adjust · Enter or Esc to finish'
              : 'Enter or Space to adjust');
    final control = widget.inlineHint
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              widget.child,
              if (_keyboardCues)
                ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: KalinkaColors.textPrimary),
                    ),
                  ),
                ),
            ],
          )
        : widget.child;
    return ExcludeFocus(
      excluding: !widget.enabled,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(navigationMode: NavigationMode.directional),
        child: CallbackShortcuts(
          bindings: {
            // Once typing, preserve spaces, newlines and each field's Submit/Done.
            if (!_editing || !text) ...{
              const SingleActivator(
                LogicalKeyboardKey.enter,
                includeRepeats: false,
              ): () =>
                  _setEditing(!_editing),
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                includeRepeats: false,
              ): () =>
                  _setEditing(!_editing),
            },
            if (!text)
              const SingleActivator(
                LogicalKeyboardKey.space,
                includeRepeats: false,
              ): () =>
                  _setEditing(!_editing),
            if (_editing)
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _setEditing(false),
            if (!_editing || !text) ...{
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _arrow(TraversalDirection.left),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _arrow(TraversalDirection.right),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _arrow(TraversalDirection.up),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _arrow(TraversalDirection.down),
            },
          },
          child: Focus(
            focusNode: _navigationFocus,
            canRequestFocus: widget.enabled,
            child: Listener(
              onPointerDown: (_) => _setKeyboardCues(false),
              child: Semantics(
                hint: hint,
                onIncrease: widget.onIncrease,
                onDecrease: widget.onDecrease,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _keyboardCues
                          ? KalinkaColors.textPrimary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      // Exclude traversal, not direct focus: a tap, autofocus or
                      // requestFocus still starts editing with the original field.
                      ExcludeFocusTraversal(
                        excluding: !_editing,
                        child: control,
                      ),
                      if (_keyboardCues && !widget.inlineHint)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Tooltip(
                              key: _hint,
                              message: hint,
                              excludeFromSemantics: true,
                              preferBelow: false,
                              triggerMode: TooltipTriggerMode.manual,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
