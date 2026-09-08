import 'dart:async';

import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/search_aggregator.dart';
import '../state/search_filters.dart';
import 'search_filter_sheet.dart';
import 'search_failure_panel.dart';
import 'skeleton.dart';
import 'source_screen.dart';
import 'widgets.dart';

/// 聚合搜索：并发查所有启用源；结果带源标识、同名去重、按源权重排序。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.state,
    this.sourceTimeout = const Duration(seconds: 12),
  });
  final AppState state;

  /// 单源搜索超时；超时计入聚合状态的「超时」而非笼统失败。
  final Duration sourceTimeout;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _searchPrompt = EmptyStateView(
    key: ValueKey('prompt'),
    icon: Icons.manage_search_outlined,
    title: '输入关键词开始聚合搜索',
    message: '输入书名或作者，跨源查找喜欢的漫画。',
  );

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final Map<String, List<Book>> _raw = {}; // 源id → 结果（到达序）
  AggregatedSearch? _agg;
  final _failed = ValueNotifier<Map<String, SearchSourceFailure>>({});
  bool _searching = false;
  String _query = '';
  int _searchGeneration = 0;
  int _sourceCount = 0;
  Map<String, ComicSource>? _searchedSources;
  bool _sourcesChanged = false;
  bool _filtersChanged = false;
  late SearchFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.state.searchFilters;
    _controller.addListener(_onQueryChanged);
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _filters = widget.state.searchFilters;
      if (_searchedSources != null) {
        _invalidateSearch(_searchableSources(ignoreHealth: true));
      }
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _failed.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Map<String, ComicSource> _searchableSources({bool ignoreHealth = false}) => {
    for (final source in widget.state.sources)
      if (widget.state.searchFilters.accepts(
        source,
        ignoreHealth: ignoreHealth,
      ))
        source.id: source,
  };

  void _onStateChanged() {
    setState(() {
      final filtersChanged = _filters != widget.state.searchFilters;
      _filters = widget.state.searchFilters;
      final searched = _searchedSources;
      if (searched == null) return;
      // 健康回报仅影响下一次搜索，避免本次失败达到阈值时清空成功结果。
      final current = _searchableSources(ignoreHealth: true);
      if (filtersChanged ||
          current.length != searched.length ||
          current.entries.any((e) => !identical(e.value, searched[e.key]))) {
        _invalidateSearch(current);
        _filtersChanged = filtersChanged;
      }
    });
  }

  void _invalidateSearch(Map<String, ComicSource> sources) {
    _searchGeneration++;
    _searching = false;
    _sourcesChanged = true;
    _searchedSources = sources;
    _sourceCount = _searchableSources().length;
    _raw.clear();
    _agg = null;
    _failed.value = {};
  }

  void _onQueryChanged() {
    setState(() {
      if (_controller.text.trim() != _query) {
        // 输入变更后，旧请求仍可回报源健康，但不能覆盖当前页面。
        _searchGeneration++;
        _searching = false;
        _query = '';
        _sourceCount = 0;
        _searchedSources = null;
        _sourcesChanged = false;
        _filtersChanged = false;
        _raw.clear();
        _agg = null;
        _failed.value = {};
      }
    });
  }

  void _refill(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _showFilters() async {
    _focusNode.unfocus();
    final filters = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SearchFilterSheet(state: widget.state),
    );
    if (!mounted || filters == null || filters == widget.state.searchFilters) {
      return;
    }
    final repeat = _query.isNotEmpty;
    await widget.state.setSearchFilters(filters);
    if (mounted && repeat) await _doSearch();
  }

  /// 源 id → 显示名（结果标签用）。
  String _sourceName(String id) {
    for (final s in widget.state.sources) {
      if (s.id == id) return s.name.isEmpty ? id : s.name;
    }
    return id;
  }

  bool _isCurrentSearch(int generation) =>
      mounted && generation == _searchGeneration;

  Future<void> _doSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _searching) return;
    final state = widget.state;
    final sources = _searchableSources();
    final enabled = sources.values.toList();
    final generation = ++_searchGeneration;
    _focusNode.unfocus();
    setState(() {
      _searching = true;
      _query = q;
      _sourceCount = enabled.length;
      _searchedSources = _searchableSources(ignoreHealth: true);
      _sourcesChanged = false;
      _filtersChanged = false;
      _raw.clear();
      _agg = null;
      _failed.value = {};
    });
    await state.recordSearch(q);
    if (!_isCurrentSearch(generation)) return;

    final okIds = <String>{};
    final errors = <String, String>{};
    await Future.wait(
      enabled.map((s) async {
        final future = SourceService.instance.runtimeFor(s).search(q);
        try {
          final page = await future.timeout(widget.sourceTimeout);
          if (_isCurrentSearch(generation)) {
            setState(() {
              _raw[s.id] = page.items;
              _reaggregate();
            });
          }
          okIds.add(s.id);
        } catch (e) {
          future.ignore();
          if (_isCurrentSearch(generation)) {
            setState(() {
              _failed.value = {
                ..._failed.value,
                s.id: SearchSourceFailure(
                  name: _sourceName(s.id),
                  kind: classifySearchFailure(e),
                ),
              };
            });
          }
          if (classifySearchFailure(e) != SearchSourceFailKind.blocked) {
            errors[s.id] = e.toString();
          }
        }
      }),
    );
    // 健康回报：成功清零失败计数，失败累加（源页据此标红/一键禁用失效源）。
    await state.reportSourceHealth(okIds, errors, observedSources: enabled);
    if (_isCurrentSearch(generation)) setState(() => _searching = false);
  }

  void _reaggregate() {
    _agg = SearchAggregator.aggregate(Map.of(_raw), (sourceId) {
      for (final s in widget.state.sources) {
        if (s.id == sourceId) return s.weight;
      }
      return 0;
    });
  }

  String _statusLine() {
    final timeouts = _failed.value.values
        .where((f) => f.kind == SearchSourceFailKind.timeout)
        .length;
    final blocked = _failed.value.values
        .where((f) => f.kind == SearchSourceFailKind.blocked)
        .length;
    return searchAggregateStatus(
      sourceCount: _sourceCount,
      successCount: _raw.length,
      timeoutCount: timeouts,
      errorCount: _failed.value.length - timeouts - blocked,
      blockedCount: blocked,
      searching: _searching,
    );
  }

  void _showFailures() {
    if (_failed.value.isEmpty) return;
    _focusNode.unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: ValueListenableBuilder<Map<String, SearchSourceFailure>>(
          valueListenable: _failed,
          builder: (context, failures, _) => SearchFailurePanel(
            failures: failures.values.toList(),
            onManageSources: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(this.context).push(
                MaterialPageRoute(
                  builder: (_) => SourceScreen(state: widget.state),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _titleBar(BuildContext context, bool canPop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 4, 20, 4),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: ScreenTitle('搜索'),
            ),
          ),
          IconButton(
            tooltip: '搜索筛选',
            onPressed: _showFilters,
            icon: Badge(
              isLabelVisible: widget.state.searchFilters.isActive,
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fieldStyle = Theme.of(context).textTheme.bodyMedium;
    final actionStyle = IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      iconSize: 20,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final surface = scheme.brightness == Brightness.light
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainerLow;
    final canSearch = !_searching && _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: fieldStyle,
        textAlignVertical: TextAlignVertical.center,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _doSearch(),
        decoration: InputDecoration(
          hintText: '搜索书名、作者…',
          hintStyle: fieldStyle?.copyWith(color: scheme.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.primary),
          ),
          suffixIconConstraints: const BoxConstraints(minHeight: 42),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: '清空输入',
                    style: actionStyle,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _focusNode.requestFocus();
                    },
                  ),
                IconButton(
                  tooltip: '搜索',
                  style: actionStyle,
                  icon: const Icon(Icons.search),
                  onPressed: canSearch ? _doSearch : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyView(BuildContext context) {
    final history = widget.state.searchHistory;
    if (history.isEmpty) return _searchPrompt;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  '最近10词',
                  style: textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                textStyle: textTheme.labelLarge?.copyWith(fontSize: 13),
              ),
              onPressed: widget.state.clearSearchHistory,
              child: const Text('清空'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          // 胶囊之间的垂直留白由 48px 点击区提供，不再叠加行间距。
          children: [
            for (final query in history)
              Tooltip(
                message: query,
                child: ActionChip(
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: scheme.brightness == Brightness.light
                      ? scheme.surfaceContainerLowest
                      : scheme.surfaceContainerLow,
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  labelStyle: textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                  label: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _refill(query),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _statusAndTips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tip = searchFailureTip(_failed.value.values);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _statusLine(),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (tip != null) ...[
            const SizedBox(height: 8),
            Tooltip(
              message: '查看失败源',
              child: Material(
                color: scheme.errorContainer.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _showFailures,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 18,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tip,
                            semanticsLabel: '${_failed.value.length} 个源未响应',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: scheme.onErrorContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultsView(BuildContext context) {
    return Column(
      children: [
        if (_query.isNotEmpty && _sourceCount > 0 && !_sourcesChanged)
          _statusAndTips(context),
        Expanded(
          child: AnimatedSwitcher(
            key: ObjectKey(_searchedSources),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: _resultContent(),
          ),
        ),
      ],
    );
  }

  Widget _resultContent() {
    if (_query.isEmpty) {
      return _searchPrompt;
    }
    if (_sourceCount == 0) {
      if (widget.state.searchFilters.isActive) {
        return EmptyStateView(
          key: const ValueKey('filtered-no-sources'),
          icon: Icons.filter_list_off_outlined,
          title: '当前筛选下没有可搜索的源',
          message: '调整健康筛选或指定源，也可重置为全部源。',
          actionLabel: '调整筛选',
          onAction: _showFilters,
        );
      }
      return EmptyStateView(
        key: const ValueKey('no-sources'),
        icon: Icons.travel_explore,
        title: '暂无可搜索的源',
        message: '启用一个支持搜索的漫画源后再试。',
        actionLabel: '管理源',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SourceScreen(state: widget.state)),
        ),
      );
    }
    if (_sourcesChanged) {
      return EmptyStateView(
        key: const ValueKey('sources-changed'),
        icon: Icons.manage_search_outlined,
        title: _filtersChanged ? '搜索筛选已更新' : '漫画源已更新',
        message: '关键词已保留，重新搜索获取最新结果。',
        actionLabel: '重新搜索',
        onAction: _doSearch,
      );
    }
    final agg = _agg;
    if (agg != null && agg.books.isNotEmpty) {
      return ListView.builder(
        key: ValueKey('results-$_query'),
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: agg.books.length,
        itemBuilder: (context, i) => BookTile(
          key: ObjectKey(agg.books[i]),
          book: agg.books[i],
          state: widget.state,
          sourceLabel: _sourceName(agg.sourceIds[i]),
        ),
      );
    }
    if (_searching) {
      return const BookListSkeleton(key: ValueKey('loading'));
    }
    if (_raw.isEmpty && _failed.value.isNotEmpty) {
      return EmptyStateView(
        key: const ValueKey('failed'),
        icon: Icons.cloud_off_outlined,
        title: '暂时无法连接漫画源',
        message: '检查网络，或到「源」页查看源状态后再试。',
        actionLabel: '重新搜索',
        onAction: _doSearch,
      );
    }
    return EmptyStateView(
      key: const ValueKey('empty'),
      icon: Icons.search_off_outlined,
      title: '没有找到相关漫画',
      message: '试试更短的书名、作者名，或换一个关键词。',
      actionLabel: '修改关键词',
      onAction: () {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
        _focusNode.requestFocus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titleBar(context, canPop),
            _searchField(context),
            Expanded(
              child: _controller.text.trim().isEmpty
                  ? _historyView(context)
                  : _resultsView(context),
            ),
          ],
        ),
      ),
    );
  }
}
