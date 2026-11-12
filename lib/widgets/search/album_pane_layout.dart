import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Measures the album bar before laying out the body in the same frame.
/// When the full bar leaves too little track space, only the bar is laid out
/// again with its metadata moved into the scrollable body. No post-frame
/// correction or body rebuild is needed to choose the final arrangement.
class AlbumPaneLayout extends StatelessWidget {
  final Widget Function(BuildContext context, bool metadataInTracks)?
  headerBuilder;
  final Widget Function(
    BuildContext context,
    double headerHeight,
    bool metadataInTracks,
  )
  builder;
  final double minimumBodyHeight;

  const AlbumPaneLayout({
    super.key,
    this.headerBuilder,
    required this.builder,
    required this.minimumBodyHeight,
  });

  @override
  Widget build(BuildContext context) => _AlbumLayout(
    minimumBodyHeight: minimumBodyHeight,
    children: [
      // Keep the body at the same element location when switching to phone.
      LayoutBuilder(
        builder: (context, constraints) {
          final body = constraints as _BodyConstraints;
          return builder(context, body.headerHeight, body.metadataInTracks);
        },
      ),
      if (headerBuilder != null)
        LayoutBuilder(
          builder: (context, constraints) => headerBuilder!(
            context,
            (constraints as _HeaderConstraints).metadataInTracks,
          ),
        ),
    ],
  );
}

class _AlbumLayout extends MultiChildRenderObjectWidget {
  final double minimumBodyHeight;

  const _AlbumLayout({
    required this.minimumBodyHeight,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAlbumLayout(minimumBodyHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlbumLayout renderObject,
  ) {
    renderObject.minimumBodyHeight = minimumBodyHeight;
  }
}

class _AlbumParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAlbumLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AlbumParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AlbumParentData> {
  _RenderAlbumLayout(this._minimumBodyHeight);

  double _minimumBodyHeight;
  set minimumBodyHeight(double value) {
    if (_minimumBodyHeight == value) return;
    _minimumBodyHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AlbumParentData) {
      child.parentData = _AlbumParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final body = firstChild!;
    final header = childAfter(body);
    var headerHeight = 0.0;
    var metadataInTracks = false;
    if (header != null) {
      // Always reconsider the full header using current text and constraints,
      // so resizing taller restores the details without a feedback loop.
      header.layout(
        _HeaderConstraints(size.width, false),
        parentUsesSize: true,
      );
      if (size.height - header.size.height < _minimumBodyHeight) {
        metadataInTracks = true;
        header.layout(
          _HeaderConstraints(size.width, true),
          parentUsesSize: true,
        );
      }
      headerHeight = header.size.height;
    }
    // The tracks still occupy the whole pane and fade underneath the bar.
    body.layout(_BodyConstraints(size, headerHeight, metadataInTracks));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _HeaderConstraints extends BoxConstraints {
  final bool metadataInTracks;

  const _HeaderConstraints(double width, this.metadataInTracks)
    : super.tightFor(width: width);

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is _HeaderConstraints &&
      metadataInTracks == other.metadataInTracks;

  @override
  int get hashCode => Object.hash(super.hashCode, metadataInTracks);
}

class _BodyConstraints extends BoxConstraints {
  final double headerHeight;
  final bool metadataInTracks;

  _BodyConstraints(Size size, this.headerHeight, this.metadataInTracks)
    : super.tightFor(width: size.width, height: size.height);

  // A bar can change height without the pane changing size (metadata, text
  // scale, safe-area insets). In that case its body must be laid out again.
  @override
  bool operator ==(Object other) =>
      super == other &&
      other is _BodyConstraints &&
      headerHeight == other.headerHeight &&
      metadataInTracks == other.metadataInTracks;

  @override
  int get hashCode =>
      Object.hash(super.hashCode, headerHeight, metadataInTracks);
}
