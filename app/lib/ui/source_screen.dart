import 'dart:io';

import 'package:engine/engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/clipboard_import.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'source_editor_screen.dart';
import 'widgets.dart';

/// 仓库 URL → 设计稿短名（`user/repo`）。
String repoDisplayName(String url) {
  var s = url.trim();
  s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^www\.'), '');
  s = s.replaceFirst(RegExp(r'\.git$'), '');
  final parts = s.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.length >= 3) return '${parts[1]}/${parts[2]}';
  if (parts.length == 2) return '${parts[0]}/${parts[1]}';
  return url;
}

/// 上次同步文案（对齐 six-screens「上次同步 09-06」）。
String repoSyncLabel(int? epochMs) {
  if (epochMs == null || epochMs <= 0) return '尚未检查更新';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '上次同步 $mm-$dd';
}

/// 源管理：订阅仓库 / 手动导入 / 启停。
class SourceScreen extends StatefulWidget {
  const SourceScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends State<SourceScreen> {
  bool _subscribing = false;
  String? _lastResult;
  String? _refreshingRepo;
  bool _probing = false;

  /// 源健康体检：真实搜索探测全部启用源，实时显示进度。
  Future<void> _probeHealth() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _lastResult = '体检中… 0';
    });
    final (ok, total) = await widget.state.probeSources(
      onProgress: (done, t) {
        if (mounted) setState(() => _lastResult = '体检中… $done/$t');
      },
    );
    if (mounted) {
      setState(() {
        _probing = false;
        _lastResult = '体检完成：可用 $ok / $total（失效源已标红，可用菜单「禁用失效源」一键停用）';
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
        _lastResult = r.summary;
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
        _lastResult = results.map((r) => r.summary).join('；');
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
      if (path == null) return;
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
      setState(
        () => _lastResult = sources.isEmpty
            ? '备份读取成功：${backup.sharedRules.length} 条分享源（加密部分待密钥），'
                  '已同步 ${backup.storeSubscriptions.length} 个订阅仓库'
            : '导入成功：${sources.length} 个源（来自 ${backup.sharedRules.length} 条分享记录）',
      );
    } catch (e) {
      setState(() => _lastResult = '备份导入失败：$e');
    }
  }

  Future<void> _subscribeDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('订阅源仓库'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'github.com/user/repo 或 gitee.com/user/repo',
            helperText: '明文仓库全量导入；ppcat 加密仓库自动提取明文分片（约半数源）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('订阅'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final url = controller.text.trim();
    if (url.isEmpty) return;
    setState(() => _subscribing = true);
    try {
      final bundle = await RepoClient(
        fetcher: SourceService.instance.fetcher,
      ).subscribe(url);
      await widget.state.addRepoSubscribed(url, bundle.sources);
      setState(
        () => _lastResult =
            '订阅成功：${bundle.ref.canonical} 导入 ${bundle.sources.length} 个源（Track ${bundle.track}）',
      );
    } catch (e) {
      setState(() => _lastResult = '订阅失败：$e');
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
          setState(() => _lastResult = '剪贴板导入成功：${sources.length} 个源');
        }
      case ClipboardImportInvalid(:final message):
        if (mounted) {
          setState(() => _lastResult = '剪贴板导入失败：$message');
        }
    }
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
        setState(() => _lastResult = n > 0 ? '已从内置快照恢复 $n 个源' : '内置快照的源已全部在列');
      }
    } else if (v == 'probeHealth') {
      _probeHealth();
    } else if (v == 'refreshAll') {
      await _refreshAllRepos();
    } else if (v == 'disableUnhealthy') {
      final n = await widget.state.disableUnhealthySources();
      if (mounted) {
        setState(
          () => _lastResult = n > 0
              ? '已禁用 $n 个失效源（连续失败≥3，可重新打开开关恢复）'
              : '没有连续失败≥3 的源',
        );
      }
    } else if (v == 'resetHealth') {
      final n = await widget.state.resetSourceHealth();
      if (mounted) {
        setState(() => _lastResult = '已清除 $n 个源的失败记录');
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
          body: SafeArea(
            bottom: false,
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
                  hasUnhealthy: widget.state.sources.any((s) => s.isUnhealthy),
                  onBack: () => Navigator.of(context).pop(),
                  onSubscribe: _subscribing ? null : _subscribeDialog,
                  onMore: _onMoreSelected,
                ),
                if (_lastResult != null)
                  Material(
                    color: scheme.surfaceContainerHighest,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: Text(
                        _lastResult!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _lastResult = null),
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
    final empty = repos.isEmpty && sources.isEmpty;
    return Column(
      children: [
        Flexible(
          fit: sources.isEmpty ? FlexFit.tight : FlexFit.loose,
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
                  shrinkWrap: sources.isNotEmpty,
                  slivers: [
                    if (repos.isNotEmpty) ...[
                      const SliverToBoxAdapter(child: _SectionLabel('已订阅仓库')),
                      SliverList.builder(
                        itemCount: repos.length,
                        itemBuilder: (context, i) =>
                            _repoCard(repos[i], scheme),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: _SectionLabel(
                        sources.isEmpty ? '源' : '源（${sources.length}）',
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
                    else
                      SliverList.builder(
                        itemCount: sources.length,
                        itemBuilder: (context, i) =>
                            _sourceRow(sources[i], scheme),
                      ),
                    if (sources.isNotEmpty)
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
              child: const Text('粘贴导入单个源 JSON'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _repoCard(String repo, ColorScheme scheme) {
    final lastAt = widget.state.repoLastRefresh[repo];
    final u = widget.state.repoUpdates[repo];
    final hasPending = u?.hasPending ?? false;
    final pendingText = hasPending
        ? (u!.lastRuleVersion >= 0
              ? ' · 有新版本 v${u.lastRuleVersion}→v${u.pendingVersion}'
              : ' · 有新版本 v${u.pendingVersion}')
        : '';
    final refreshing = _refreshingRepo == repo || _refreshingRepo == '*';
    return Card(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      color: scheme.brightness == Brightness.light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            Expanded(
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
                ],
              ),
            ),
            refreshing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
                  onLongPress: () => _showSourceActions(s),
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
              Switch(
                value: s.enabled,
                onChanged: (_) => widget.state.toggleSource(s.id),
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
  final bool hasUnhealthy;
  final VoidCallback onBack;
  final VoidCallback? onSubscribe;
  final Future<void> Function(String value) onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop)
            IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
          Expanded(
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
          TextButton(
            onPressed: onSubscribe,
            child: subscribing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '＋ 订阅仓库',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
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
