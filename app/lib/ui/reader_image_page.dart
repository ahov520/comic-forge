import 'package:flutter/material.dart';

/// 翻页模式的单张漫画：双指缩放，放大后拖动，正常倍率保留三分点击区。
class ReaderImagePage extends StatefulWidget {
  const ReaderImagePage({
    super.key,
    required this.active,
    required this.child,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleChrome,
    required this.onZoomChanged,
  });

  final bool active;
  final Widget child;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleChrome;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<ReaderImagePage> createState() => _ReaderImagePageState();
}

class _ReaderImagePageState extends State<ReaderImagePage> {
  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    if (widget.active) widget.onZoomChanged(zoomed);
  }

  @override
  void didUpdateWidget(covariant ReaderImagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.active
          ? (details) {
              final fraction = details.localPosition.dx / constraints.maxWidth;
              if (_zoomed || (fraction >= 1 / 3 && fraction <= 2 / 3)) {
                widget.onToggleChrome();
              } else if (fraction < 1 / 3) {
                widget.onPrevious();
              } else {
                widget.onNext();
              }
            }
          : null,
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: widget.active && _zoomed,
        scaleEnabled: widget.active,
        minScale: 1,
        maxScale: 4,
        child: widget.child,
      ),
    ),
  );
}
