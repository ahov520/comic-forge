import 'dart:math' as math;
import 'dart:ui';

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 阅读器工具栏渐变遮罩：顶/底黑→透明渐变，保证白字工具栏在浅色漫画上可读。
/// [visible] 为 false 时整体收起（不渲染、不拦截）。
/// 独立组件便于单测（渐变容器随可见性出现/消失）。
class ReaderChromeOverlay extends StatelessWidget {
  const ReaderChromeOverlay({
    super.key,
    required this.visible,
    required this.topInset,
    required this.bottomInset,
    this.topHeight = 72,
    this.bottomHeight = 84,
  });

  final bool visible;
  final double topInset;
  final double bottomInset;
  final double topHeight;
  final double bottomHeight;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    // IgnorePointer：点击穿透到下层翻页点区
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              height: topInset + topHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: bottomInset + bottomHeight,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 毛玻璃条：对齐 six-screens ④ `backdrop-filter: blur(10px)`。
class ReaderFrostedBar extends StatelessWidget {
  const ReaderFrostedBar({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x8C0E171E),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

Duration _chromeAnim(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 200);

/// 顶栏：关闭 · 书名/章节 · 书签 · 更多。隐藏时不拦截点击。
class ReaderTopChrome extends StatelessWidget {
  const ReaderTopChrome({
    super.key,
    required this.visible,
    required this.title,
    this.onClose,
    this.onMore,
    this.onBookmark,
    this.bookmarked = false,
  });

  final bool visible;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onMore;
  final VoidCallback? onBookmark;
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _chromeAnim(context),
      child: IgnorePointer(
        ignoring: !visible,
        child: ReaderFrostedBar(
          // 将原有留白纳入按钮点击区域，保持图标与标题的位置。
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '关闭',
                color: const Color(0xFFEEEEEE),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Tooltip(
                  message: title,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEEEEEE),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              if (onBookmark != null)
                IconButton(
                  tooltip: bookmarked ? '移除书签' : '添加书签',
                  color: const Color(0xFFEEEEEE),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onBookmark,
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                ),
              IconButton(
                tooltip: '阅读设置',
                color: const Color(0xFFEEEEEE),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onMore,
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏渐变高度：有章内进度条时加高，避免浅色漫画顶到滑杆。
double readerChromeBottomHeight({required int pageCount}) =>
    pageCount > 1 ? 132 : 84;

/// 底栏：章内页进度（可选）· 上一话 · 目录 · 亮度 · 下一话。隐藏时不拦截点击。
class ReaderBottomChrome extends StatelessWidget {
  const ReaderBottomChrome({
    super.key,
    required this.visible,
    required this.progressLabel,
    required this.canPrev,
    required this.canNext,
    this.onPrev,
    this.onNext,
    this.onBrightness,
    this.onCatalog,
    this.pageIndex = 0,
    this.pageCount = 0,
    this.onPageChanged,
    this.onPickPage,
  });

  final bool visible;
  final String progressLabel;
  final bool canPrev;
  final bool canNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onBrightness;
  final VoidCallback? onCatalog;
  final int pageIndex;
  final int pageCount;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onPickPage;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _chromeAnim(context),
      child: IgnorePointer(
        ignoring: !visible,
        child: Material(
          color: const Color(0xFF161619),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pageCount > 0)
                    ReaderPageProgress(
                      pageIndex: pageIndex,
                      pageCount: pageCount,
                      onChanged: onPageChanged,
                      onPickPage: onPickPage,
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NavItem(
                        icon: Icons.chevron_left,
                        label: '上一话',
                        enabled: canPrev,
                        onTap: onPrev,
                      ),
                      _NavItem(
                        icon: Icons.menu,
                        label: progressLabel,
                        tooltip: '目录',
                        wrapLabel: true,
                        enabled: onCatalog != null,
                        onTap: onCatalog,
                      ),
                      _NavItem(
                        icon: Icons.wb_sunny_outlined,
                        label: '亮度',
                        onTap: onBrightness,
                      ),
                      _NavItem(
                        icon: Icons.chevron_right,
                        label: '下一话',
                        enabled: canNext,
                        onTap: onNext,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 章内页码 + 可拖进度条；点页码打开跳页。仅一页时只显示页码。
class ReaderPageProgress extends StatelessWidget {
  const ReaderPageProgress({
    super.key,
    required this.pageIndex,
    required this.pageCount,
    this.onChanged,
    this.onPickPage,
  });

  final int pageIndex;
  final int pageCount;
  final ValueChanged<int>? onChanged;
  final VoidCallback? onPickPage;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 0) return const SizedBox.shrink();
    final max = math.max(pageCount - 1, 0);
    final value = pageIndex.clamp(0, max).toDouble();
    final label = '${value.round() + 1}/$pageCount';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          Tooltip(
            message: '跳转页码',
            child: InkWell(
              onTap: onPickPage,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Center(
                  child: Text(
                    label,
                    key: const Key('reader-page-label'),
                    semanticsLabel: '第 ${value.round() + 1} 页，共 $pageCount 页',
                    style: const TextStyle(
                      color: Color(0xFFEEEEEE),
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (pageCount > 1)
            Expanded(
              child: Slider(
                key: const Key('reader-page-slider'),
                min: 0,
                max: max.toDouble(),
                divisions: max,
                value: value,
                label: '${value.round() + 1}',
                semanticFormatterCallback: (v) =>
                    '第 ${v.round() + 1} 页，共 $pageCount 页',
                onChanged: onChanged == null
                    ? null
                    : (v) => onChanged!(v.round()),
              ),
            ),
        ],
      ),
    );
  }
}

/// 沉浸态页码徽章：工具栏收起后仍显示章内进度，点按打开跳页。
class ReaderPageBadge extends StatelessWidget {
  const ReaderPageBadge({
    super.key,
    required this.visible,
    required this.label,
    this.progress = 0,
    this.onTap,
  });

  final bool visible;
  final String label;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible || label.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: '跳转页码',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ReaderFrostedBar(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                label,
                key: const Key('reader-page-badge'),
                semanticsLabel: '当前 $label 页',
                style: const TextStyle(
                  color: Color(0xFFEEEEEE),
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  key: const Key('reader-page-bar'),
                  minHeight: 2,
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: const Color(0x33FFFFFF),
                  color: const Color(0xFF169876),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 阅读器目录：深色列表，当前话高亮。
class ReaderCatalogSheet extends StatefulWidget {
  const ReaderCatalogSheet({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onPick,
    this.bookmarkedUrls = const {},
  });

  final List<Chapter> chapters;
  final int currentIndex;
  final ValueChanged<int> onPick;
  final Set<String> bookmarkedUrls;

  @override
  State<ReaderCatalogSheet> createState() => _ReaderCatalogSheetState();
}

class _ReaderCatalogSheetState extends State<ReaderCatalogSheet> {
  ScrollController? _controller;

  Future<void> _jumpToChapter() async {
    final index = await showDialog<int>(
      context: context,
      builder: (context) => ReaderIndexJumpDialog(
        currentIndex: widget.currentIndex,
        count: widget.chapters.length,
        title: '跳转章节',
        fieldLabel: '章节序号',
        helperText: '共 ${widget.chapters.length} 话',
        errorText: '请输入 1–${widget.chapters.length} 之间的序号',
      ),
    );
    if (mounted && index != null) widget.onPick(index);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rowExtent = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(14) / 14 * 48,
    );
    return Material(
      color: const Color(0xFF161619),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        '目录 · ${widget.chapters.length} 话',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.chapters.isEmpty ? null : _jumpToChapter,
                    child: const Text('跳转'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 首次展开直接定位当前话，长目录和大字号都无需从头滚动。
                  final maxOffset = math.max(
                    0.0,
                    widget.chapters.length * rowExtent - constraints.maxHeight,
                  );
                  final initialOffset =
                      (widget.currentIndex * rowExtent -
                              (constraints.maxHeight - rowExtent) / 2)
                          .clamp(0.0, maxOffset)
                          .toDouble();
                  _controller ??= ScrollController(
                    initialScrollOffset: initialOffset,
                  );
                  return ListView.builder(
                    controller: _controller,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemExtent: rowExtent,
                    itemCount: widget.chapters.length,
                    itemBuilder: (context, i) {
                      final current = i == widget.currentIndex;
                      final bookmarked = widget.bookmarkedUrls.contains(
                        widget.chapters[i].url,
                      );
                      return ListTile(
                        dense: true,
                        selected: current,
                        selectedTileColor: const Color(0x33169876),
                        leading: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: current ? Colors.white : Colors.white54,
                            fontWeight: current ? FontWeight.w700 : null,
                          ),
                        ),
                        title: Text(
                          widget.chapters[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: current ? Colors.white : Colors.white70,
                            fontWeight: current ? FontWeight.w600 : null,
                          ),
                        ),
                        trailing: bookmarked && !current
                            ? const Icon(
                                Icons.bookmark_outline,
                                size: 16,
                                color: Colors.white54,
                              )
                            : null,
                        onTap: () => widget.onPick(i),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 阅读器序号跳转：章节目录与章内页码共用。
class ReaderIndexJumpDialog extends StatefulWidget {
  const ReaderIndexJumpDialog({
    super.key,
    required this.currentIndex,
    required this.count,
    required this.title,
    required this.fieldLabel,
    required this.helperText,
    required this.errorText,
  });

  final int currentIndex;
  final int count;
  final String title;
  final String fieldLabel;
  final String helperText;
  final String errorText;

  @override
  State<ReaderIndexJumpDialog> createState() => _ReaderIndexJumpDialogState();
}

class _ReaderIndexJumpDialogState extends State<ReaderIndexJumpDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = '${widget.currentIndex + 1}';
    _controller = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(int.parse(_controller.text) - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact =
        media.size.width >= 480 &&
        media.size.height - media.viewInsets.bottom - media.padding.vertical <
            260;
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('跳转')),
    ];
    return AlertDialog(
      backgroundColor: const Color(0xFF161619),
      scrollable: true,
      semanticLabel: widget.title,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 24 : 40,
        vertical: compact ? 8 : 24,
      ),
      contentPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
          : const EdgeInsets.fromLTRB(24, 20, 24, 24),
      title: compact ? null : Text(widget.title),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: compact ? 500 : null,
          child: Flex(
            direction: compact ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: compact ? FlexFit.tight : FlexFit.loose,
                child: TextFormField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: compact ? widget.title : widget.fieldLabel,
                    hintText: compact ? '1–${widget.count}' : null,
                    helperText: compact ? null : widget.helperText,
                    isDense: compact,
                    errorMaxLines: 2,
                  ),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    if (number == null || number < 1 || number > widget.count) {
                      return widget.errorText;
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
              ),
              if (compact) ...[const SizedBox(width: 12), ...actions],
            ],
          ),
        ),
      ),
      actions: compact ? null : actions,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
    this.enabled = true,
    this.wrapLabel = false,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool enabled;
  final bool wrapLabel;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && onTap != null;
    final color = canTap ? const Color(0xFF888888) : Colors.white24;
    return Expanded(
      child: Tooltip(
        message: tooltip ?? label,
        child: InkWell(
          onTap: canTap ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 3),
                  _buildLabel(context, color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, Color color) {
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    Widget text(String value) => Text(
      value,
      semanticsLabel: label,
      textAlign: TextAlign.center,
      maxLines: wrapLabel ? null : 1,
      overflow: wrapLabel ? TextOverflow.clip : TextOverflow.ellipsis,
      style: style,
    );
    if (!wrapLabel) return text(label);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout(maxWidth: constraints.maxWidth);
        // 只在一行放不下时从斜杠后换行，避免拆开总话数。
        final value = painter.didExceedMaxLines
            ? label.replaceFirst('/', '/\n')
            : label;
        painter.dispose();
        return text(value);
      },
    );
  }
}
