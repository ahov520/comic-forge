import 'dart:io';

import 'package:engine/engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/clipboard_import.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'source_editor_screen.dart';
import 'source_subscription_dialog.dart';
import 'widgets.dart';

/// 仓库 URL → 设计稿短名（`user/repo`）；源列表 URL → `host/文件名`。
String repoDisplayName(String url) {
  final ref = RepoRef.parse(url);
  if (ref != null && ref.isListUrl) {
    final uri = Uri.tryParse(ref.listUrl!);
    if (uri != null) {
      final file = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      return file.isEmpty ? uri.host : '${uri.host}/$file';
    }
    return ref.canonical;
  }
  var s = url.trim();
  s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^www\.'), '');
  s = s.replaceFirst(RegExp(r'\.git$'), '');
  final parts = s.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.length >= 3) return '${parts[1]}/${parts[2]}';
  if (parts.length == 2) return '${parts[0]}/${parts[1]}';
  return url;
}

/// 上次成功刷新文案。
String repoSyncLabel(int? epochMs) {
  if (epochMs == null || epochMs <= 0) return '尚未成功更新';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '上次成功 $mm-$dd $hh:$min';
}

/// 订阅失败摘要（空字符串表示没有失败）。
String repoFailureLabel(String? error) {
  final msg = error?.trim() ?? '';
  if (msg.isEmpty) return '';
  return '上次失败：$msg';
}

/// 源列表健康筛选：全部 / 连续失败≥3 / 已停用。
enum SourceHealthFilter { all, unhealthy, disabled }

/// 源是否属于当前健康筛选。
bool sourceMatchesHealthFilter(ComicSource source, SourceHealthFilter filter) {
  return switch (filter) {
    SourceHealthFilter.all => true,
    SourceHealthFilter.unhealthy => source.isUnhealthy,
    SourceHealthFilter.disabled => !source.enabled,
  };
}

/// 设置页「源订阅」副标题。
String sourceSubscriptionSubtitle(AppState state) {
  if (state.repos.isEmpty) return '订阅远程源列表并检查更新';
  final n = state.repos.length;
  final failed = state.repoFailureCount;
  if (failed > 0) return '$n 个订阅 · $failed 个上次失败';
  return '$n 个订阅 · ${repoSyncLabel(state.latestRepoSuccessAt)}';
}

/// 源管理：订阅仓库 / 手动导入 / 启停。
class SourceScreen extends StatefulWidget {
  const SourceScreen({super.key, required this.state, this.repoClient});
  final AppState state;
  final RepoClient? repoClient;

  @override
  State<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends State<SourceScreen> {
  bool _subscribing = false;
  final _feedback = ValueNotifier<String?>(null);
  String? _refreshingRepo;
  bool _probing = false;
  SourceHealthFilter _healthFilter = SourceHealthFilter.all;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _showFeedback() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          '操作详情',
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭详情',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: ValueListenableBuilder<String?>(
                    valueListenable: _feedback,
                    builder: (context, message, _) => SelectableText(
                      message ?? '暂无操作信息',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 源健康体检：真实搜索探测全部启用源，实时显示进度。
  Future<void> _probeHealth() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _feedback.value = '体检中… 0';
    });
    final (ok, total) = await widget.state.probeSources(
      onProgress: (done, t) {
        if (mounted) setState(() => _feedback.value = '体检中… $done/$t');
      },
    );
    if (mounted) {
      setState(() {
        _probing = false;
        _feedback.value = '体检完成：可用 $ok / $total（失效源已标红，可用菜单「禁用失效源」一键停用）';
      });
    }
  }

  /// 检查一个订阅仓库的更新。
  Future<void> _refreshRepo(String repo) async {
    if (_refreshingRepo != null) return;
    setState(() => _refreshingRepo = repo);
    final r = await widget.state.refreshRepo(repo);
    if (mounted) {
      setState(() {
        _refreshingRepo = null;
        _feedback.value = r.summary;
      });
    }
  }

  /// 检查全部订阅仓库。
  Future<void> _refreshAllRepos() async {
    if (_refreshingRepo != null) return;
    setState(() => _refreshingRepo = '*');
    final results = await widget.state.refreshAllRepos();
    if (mounted) {
      setState(() {
        _refreshingRepo = null;
        _feedback.value = results.map((r) => r.summary).join('；');
      });
    }
  }

  /// 导入皮皮喵「本地备份」(.pbak)。
  Future<void> _importPipimiaoBackup() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: '选择皮皮喵备份文件(.pbak)',
      );
      final path = picked?.path;
      if (path == null || !mounted) return;
      final bytes = File(path).readAsBytesSync();
      final backup = PipimiaoBackup.parse(bytes);
      // 1) 订阅仓库直接搬过来
      for (final sub in backup.storeSubscriptions) {
        if (!widget.state.repos.contains(sub.url)) {
          widget.state.addRepoSubscribed(sub.url, const []);
        }
      }
      // 2) 分享源里明文分片可解出的完整条目导入
      final sources = backup.extractCompleteSources();
      for (final s in sources) {
        await widget.state.addSourceManual(s);
      }
      if (!mounted) return;
      setState(
        () => _feedback.value = sources.isEmpty
            ? '备份读取成功：${backup.sharedRules.length} 条分享源（加密部分待密钥），'
                  '已同步 ${backup.storeSubscriptions.length} 个订阅仓库'
            : '导入成功：${sources.length} 个源（来自 ${backup.sharedRules.length} 条分享记录）',
      );
    } catch (e) {
      if (mounted) setState(() => _feedback.value = '备份导入失败：$e');
    }
  }

  Future<void> _subscribeDialog() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const SourceSubscriptionDialog(),
    );
    if (url == null || !mounted) return;
    final state = widget.state;
    setState(() => _subscribing = true);
    try {
      final bundle =
          await (widget.repoClient ?? SourceService.instance.repoClient)
              .subscribe(url);
      await state.addRepoSubscribed(
        bundle.ref.canonical,
        bundle.sources,
        meta: bundle.meta,
        markFetched: true,
      );
      if (!mounted) return;
      setState(
        () => _feedback.value =
            '订阅成功：${bundle.ref.canonical} 导入 ${bundle.sources.length} 个源'
            '${bundle.track == 'B-partial' ? '（部分源暂不支持）' : ''}',
      );
    } catch (e) {
      if (mounted) setState(() => _feedback.value = '订阅失败：$e');
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  /// 剪贴板导入：单条 → 编辑器预填；多条 → 直接批量导入。
  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    final r = ClipboardSourceImport.parse(text);
    switch (r) {
      case ClipboardImportSingle(:final source):
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                SourceEditorScreen(state: widget.state, source: source),
          ),
        );
      case ClipboardImportMany(:final sources):
        for (final s in sources) {
          await widget.state.addSourceManual(s);
        }
        if (mounted) {
          setState(() => _feedback.value = '剪贴板导入成功：${sources.length} 个源');
        }
      case ClipboardImportInvalid(:final message):
        if (mounted) {
          setState(() => _feedback.value = '剪贴板导入失败：$message');
        }
    }
  }

  Future<void> _disableUnhealthy() async {
    final n = await widget.state.disableUnhealthySources();
    if (!mounted) return;
    setState(
      () => _feedback.value = n > 0
          ? '已禁用 $n 个失效源（连续失败≥3，可重新打开开关恢复）'
          : '没有连续失败≥3 的源',
    );
  }

  Future<void> _enableDisabled({required bool unhealthyOnly}) async {
    final n = await widget.state.enableDisabledSources(
      unhealthyOnly: unhealthyOnly,
    );
    if (!mounted) return;
    setState(
      () => _feedback.value = n > 0
          ? (unhealthyOnly ? '已启用 $n 个已停用的失效源' : '已启用 $n 个已停用源')
          : (unhealthyOnly ? '没有已停用的失效源' : '没有已停用的源'),
    );
  }

  /// 长按源：编辑 / 删除。
  void _showSourceActions(ComicSource s) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑源'),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SourceEditorScreen(state: widget.state, source: s),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('删除源', style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(sheetCtx);
                widget.state.removeSource(s.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMoreSelected(String v) async {
    if (v == 'new') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SourceEditorScreen(state: widget.state),
        ),
      );
    } else if (v == 'backup') {
      _importPipimiaoBackup();
    } else if (v == 'builtin') {
      final n = await widget.state.importBuiltinSources();
      if (mounted) {
        setState(
          () => _feedback.value = n > 0 ? '已从内置快照恢复 $n 个源' : '内置快照的源已全部在列',
        );
      }
    } else if (v == 'probeHealth') {
      _probeHealth();
    } else if (v == 'refreshAll') {
      await _refreshAllRepos();
    } else if (v == 'disableUnhealthy') {
      await _disableUnhealthy();
    } else if (v == 'enableDisabledUnhealthy') {
      await _enableDisabled(unhealthyOnly: true);
    } else if (v == 'resetHealth') {
      final n = await widget.state.resetSourceHealth();
      if (mounted) {
        setState(() => _feedback.value = '已清除 $n 个源的失败记录');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final pending = widget.state.pendingUpdateCount;
        final canPop = Navigator.of(context).canPop();
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Column(
              children: [
                _SourceHeader(
                  pending: pending,
                  canPop: canPop,
                  subscribing: _subscribing,
                  probing: _probing,
                  hasRepos: widget.state.repos.isNotEmpty,
                  hasSources: widget.state.sources.isNotEmpty,
                  unhealthyEnabled: widget.state.sources
                      .where((s) => s.isUnhealthy && s.enabled)
                      .length,
                  disabledUnhealthy: widget.state.sources
                      .where((s) => s.isUnhealthy && !s.enabled)
                      .length,
                  hasUnhealthy: widget.state.sources.any((s) => s.isUnhealthy),
                  onBack: () => Navigator.of(context).pop(),
                  onSubscribe: _subscribing ? null : _subscribeDialog,
                  onMore: _onMoreSelected,
                ),
                if (_feedback.value != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Material(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Tooltip(
                        message: '查看操作详情',
                        child: ListTile(
                          contentPadding: const EdgeInsets.only(left: 12),
                          minTileHeight: 48,
                          minVerticalPadding: 4,
                          minLeadingWidth: 18,
                          horizontalTitleGap: 8,
                          leading: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: Semantics(
                            liveRegion: true,
                            child: Text(
                              _feedback.value!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(height: 1.35),
                            ),
                          ),
                          onTap: _showFeedback,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chevron_right, size: 18),
                              IconButton(
                                tooltip: '关闭提示',
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () =>
                                    setState(() => _feedback.value = null),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(child: _body(scheme)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(ColorScheme scheme) {
    final repos = widget.state.repos;
    final sources = widget.state.sources;
    final visible = sources
        .where((s) => sourceMatchesHealthFilter(s, _healthFilter))
        .toList();
    final unhealthyCount = sources.where((s) => s.isUnhealthy).length;
    final disabledCount = sources.where((s) => !s.enabled).length;
    final unhealthyEnabled = sources
        .where((s) => s.isUnhealthy && s.enabled)
        .length;
    final disabledUnhealthy = sources
        .where((s) => s.isUnhealthy && !s.enabled)
        .length;
    final empty = repos.isEmpty && sources.isEmpty;
    return Column(
      children: [
        Flexible(
          fit: visible.isEmpty ? FlexFit.tight : FlexFit.loose,
          child: empty
              ? EmptyStateView(
                  icon: Icons.source_outlined,
                  title: '还没有源',
                  message: '订阅一个仓库，或粘贴导入单个源 JSON，开始聚合漫画。',
                  actionLabel: '订阅仓库',
                  onAction: _subscribing ? null : _subscribeDialog,
                )
              : CustomScrollView(
                  // 短列表让导入按钮紧随内容；长列表仍受可用高度约束。
                  shrinkWrap: visible.isNotEmpty,
                  slivers: [
                    if (repos.isNotEmpty) ...[
                      const SliverToBoxAdapter(child: _SectionLabel('已订阅仓库')),
                      SliverList.builder(
                        itemCount: repos.length,
                        itemBuilder: (context, i) => _repoCard(
                          repos[i],
                          scheme,
                          isLast: i == repos.length - 1,
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: _SectionLabel(
                        sources.isEmpty
                            ? '源'
                            : _healthFilter == SourceHealthFilter.all
                            ? '源（${sources.length}）'
                            : '源（${visible.length}/${sources.length}）',
                      ),
                    ),
                    if (sources.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _SourceHealthFilterBar(
                          filter: _healthFilter,
                          unhealthyCount: unhealthyCount,
                          disabledCount: disabledCount,
                          unhealthyEnabled: unhealthyEnabled,
                          disabledUnhealthy: disabledUnhealthy,
                          onFilter: (value) =>
                              setState(() => _healthFilter = value),
                          onDisableUnhealthy: _disableUnhealthy,
                          onEnableDisabledUnhealthy: () =>
                              _enableDisabled(unhealthyOnly: true),
                          onEnableDisabled: () =>
                              _enableDisabled(unhealthyOnly: false),
                        ),
                      ),
                    if (sources.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyStateView(
                          icon: Icons.source_outlined,
                          title: '仓库里还没有源',
                          message: '检查仓库更新，或粘贴导入单个源 JSON。',
                          actionLabel: '检查更新',
                          onAction: _refreshingRepo != null
                              ? null
                              : _refreshAllRepos,
                        ),
                      )
                    else if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyStateView(
                          icon: Icons.filter_list_outlined,
                          title: _healthFilter == SourceHealthFilter.unhealthy
                              ? '没有失效源'
                              : '没有已停用的源',
                          message: _healthFilter == SourceHealthFilter.unhealthy
                              ? '连续失败达到 3 次的源会列在这里，可一键禁用或重新启用。'
                              : '关掉开关或禁用失效源后，它们会出现在这里。',
                          actionLabel: '查看全部',
                          onAction: () => setState(
                            () => _healthFilter = SourceHealthFilter.all,
                          ),
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) =>
                            _sourceRow(visible[i], scheme),
                      ),
                    if (visible.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
                          child: Text(
                            '长按删除 · 开关控制聚合范围',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _importFromClipboard,
              child: const Text('粘贴导入单个源 JSON', textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }

  void _showRepoActions(String repo) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.link_off, color: scheme.error),
              title: Text('取消订阅', style: TextStyle(color: scheme.error)),
              subtitle: const Text('已导入的源会保留，可稍后重新订阅'),
              onTap: () {
                Navigator.pop(sheetCtx);
                widget.state.removeRepo(repo);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _repoCard(String repo, ColorScheme scheme, {required bool isLast}) {
    final lastAt = widget.state.repoLastRefresh[repo];
    final u = widget.state.repoUpdates[repo];
    final hasPending = u?.hasPending ?? false;
    final pendingText = hasPending
        ? (u!.lastRuleVersion >= 0
              ? ' · 有新版本 v${u.lastRuleVersion}→v${u.pendingVersion}'
              : ' · 有新版本 v${u.pendingVersion}')
        : '';
    final failure = repoFailureLabel(u?.lastError);
    final refreshing = _refreshingRepo == repo || _refreshingRepo == '*';
    return Card(
      // 稿中相邻外边距会合并；末卡到分组只保留分组的 14px 上边距。
      margin: EdgeInsets.fromLTRB(20, 0, 20, isLast ? 0 : 10),
      color: scheme.brightness == Brightness.light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _showRepoActions(repo),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repoDisplayName(repo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${repoSyncLabel(lastAt)}$pendingText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: hasPending
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (failure.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          failure,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            refreshing
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: '正在检查仓库更新',
                        ),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: hasPending
                        ? '应用更新（v${u!.pendingVersion}）'
                        : '检查更新',
                    icon: Icon(
                      hasPending ? Icons.new_releases : Icons.sync,
                      color: hasPending ? scheme.primary : scheme.primary,
                    ),
                    onPressed: () => _refreshRepo(repo),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _sourceRow(ComicSource s, ColorScheme scheme) {
    final unhealthy = s.isUnhealthy;
    final recentlyFailed = s.failCount > 0 && s.lastError.isNotEmpty;
    final subtitle = [
      if (s.group.isNotEmpty) s.group,
      s.url,
      if (recentlyFailed) '最近失败(${s.failCount}): ${s.lastError}',
    ].where((e) => e.isNotEmpty).join(' · ');
    final name = s.name.isEmpty ? s.id : s.name;
    final iconColor = unhealthy
        ? scheme.error
        : (recentlyFailed ? scheme.secondary : scheme.onSurfaceVariant);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _showSourceActions(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      children: [
                        Icon(
                          Icons.grid_view_outlined,
                          size: 18,
                          color: iconColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: unhealthy ? scheme.error : null,
                                    ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontSize: 11,
                                        color: unhealthy
                                            ? scheme.error
                                            : scheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                        if (unhealthy)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.error_outline,
                              size: 18,
                              color: scheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                container: true,
                label: '启用$name',
                child: Switch(
                  value: s.enabled,
                  onChanged: (_) => widget.state.toggleSource(s.id),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}

/// 大标题「源」+「＋ 订阅仓库」，对齐 six-screens ⑤。
class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
    required this.pending,
    required this.canPop,
    required this.subscribing,
    required this.probing,
    required this.hasRepos,
    required this.hasSources,
    required this.unhealthyEnabled,
    required this.disabledUnhealthy,
    required this.hasUnhealthy,
    required this.onBack,
    required this.onSubscribe,
    required this.onMore,
  });

  final int pending;
  final bool canPop;
  final bool subscribing;
  final bool probing;
  final bool hasRepos;
  final bool hasSources;
  final int unhealthyEnabled;
  final int disabledUnhealthy;
  final bool hasUnhealthy;
  final VoidCallback onBack;
  final VoidCallback? onSubscribe;
  final Future<void> Function(String value) onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 4, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canPop)
            IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ScreenTitle('源'),
                  if (pending > 0)
                    Text(
                      '$pending 个仓库待更新',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: onSubscribe,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Visibility(
                  visible: !subscribing,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(
                    '＋ 订阅仓库',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
                if (subscribing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: '正在订阅仓库',
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: onMore,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new',
                child: ListTile(
                  leading: Icon(Icons.add_circle_outline),
                  title: Text('新建源'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  leading: Icon(Icons.restore_outlined),
                  title: Text('导入皮皮喵备份'),
                  subtitle: Text('.pbak · 提取分享源与订阅'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'builtin',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('恢复内置源'),
                  subtitle: Text('重新导入 APK 内置的 493 条社区源快照'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasRepos)
                const PopupMenuItem(
                  value: 'refreshAll',
                  child: ListTile(
                    leading: Icon(Icons.cloud_download_outlined),
                    title: Text('全部检查更新'),
                    subtitle: Text('逐个拉取订阅仓库，规则有变才更新'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (hasSources)
                PopupMenuItem(
                  value: 'probeHealth',
                  child: ListTile(
                    leading: probing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.monitor_heart_outlined),
                    title: const Text('源健康体检'),
                    subtitle: const Text('真实搜索探测全部启用源（受限并发），失效标红'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'disableUnhealthy',
                child: ListTile(
                  leading: Icon(
                    Icons.block_outlined,
                    color: hasUnhealthy ? scheme.error : null,
                  ),
                  title: const Text('禁用失效源'),
                  subtitle: Text('连续失败≥3 的启用源（当前 $unhealthyEnabled 个）'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'enableDisabledUnhealthy',
                child: ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('启用已停用的失效源'),
                  subtitle: Text('连续失败≥3 且已停用（当前 $disabledUnhealthy 个）'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'resetHealth',
                child: ListTile(
                  leading: Icon(Icons.health_and_safety_outlined),
                  title: Text('清除失败记录'),
                  subtitle: Text('重新探活前先重置标红状态'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceHealthFilterBar extends StatelessWidget {
  const _SourceHealthFilterBar({
    required this.filter,
    required this.unhealthyCount,
    required this.disabledCount,
    required this.unhealthyEnabled,
    required this.disabledUnhealthy,
    required this.onFilter,
    required this.onDisableUnhealthy,
    required this.onEnableDisabledUnhealthy,
    required this.onEnableDisabled,
  });

  final SourceHealthFilter filter;
  final int unhealthyCount;
  final int disabledCount;
  final int unhealthyEnabled;
  final int disabledUnhealthy;
  final ValueChanged<SourceHealthFilter> onFilter;
  final VoidCallback onDisableUnhealthy;
  final VoidCallback onEnableDisabledUnhealthy;
  final VoidCallback onEnableDisabled;

  @override
  Widget build(BuildContext context) {
    final showDisable = unhealthyEnabled > 0;
    final showEnableUnhealthy =
        filter != SourceHealthFilter.disabled && disabledUnhealthy > 0;
    final showEnableDisabled =
        filter == SourceHealthFilter.disabled && disabledCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChipRow(
          children: [
            FilterChoiceChip(
              key: const ValueKey('source-health-filter-all'),
              label: const Text('全部'),
              selected: filter == SourceHealthFilter.all,
              onSelected: (_) => onFilter(SourceHealthFilter.all),
            ),
            FilterChoiceChip(
              key: const ValueKey('source-health-filter-unhealthy'),
              label: Text('失效 $unhealthyCount'),
              selected: filter == SourceHealthFilter.unhealthy,
              onSelected: (_) => onFilter(SourceHealthFilter.unhealthy),
            ),
            FilterChoiceChip(
              key: const ValueKey('source-health-filter-disabled'),
              label: Text('已停用 $disabledCount'),
              selected: filter == SourceHealthFilter.disabled,
              onSelected: (_) => onFilter(SourceHealthFilter.disabled),
            ),
          ],
        ),
        if (showDisable || showEnableUnhealthy || showEnableDisabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 4,
              children: [
                if (showDisable)
                  TextButton(
                    key: const ValueKey('source-health-disable-unhealthy'),
                    onPressed: onDisableUnhealthy,
                    child: Text('禁用 $unhealthyEnabled 个失效源'),
                  ),
                if (showEnableUnhealthy)
                  TextButton(
                    key: const ValueKey('source-health-enable-unhealthy'),
                    onPressed: onEnableDisabledUnhealthy,
                    child: Text('启用 $disabledUnhealthy 个已停用的失效源'),
                  ),
                if (showEnableDisabled)
                  TextButton(
                    key: const ValueKey('source-health-enable-disabled'),
                    onPressed: onEnableDisabled,
                    child: Text('启用 $disabledCount 个已停用源'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
