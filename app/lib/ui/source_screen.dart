import 'dart:io';

import 'package:engine/engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/clipboard_import.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import 'source_editor_screen.dart';

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
        _lastResult =
            '体检完成：可用 $ok / $total（失效源已标红，可用菜单「禁用失效源」一键停用）';
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
      setState(() => _lastResult = sources.isEmpty
          ? '备份读取成功：${backup.sharedRules.length} 条分享源（加密部分待密钥），'
              '已同步 ${backup.storeSubscriptions.length} 个订阅仓库'
          : '导入成功：${sources.length} 个源（来自 ${backup.sharedRules.length} 条分享记录）');
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('订阅')),
        ],
      ),
    );
    if (ok != true) return;
    final url = controller.text.trim();
    if (url.isEmpty) return;
    setState(() => _subscribing = true);
    try {
      final bundle = await RepoClient(fetcher: SourceService.instance.fetcher).subscribe(url);
      await widget.state.addRepoSubscribed(url, bundle.sources);
      setState(() => _lastResult = '订阅成功：${bundle.ref.canonical} 导入 ${bundle.sources.length} 个源（Track ${bundle.track}）');
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
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SourceEditorScreen(state: widget.state, source: source),
        ));
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
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      SourceEditorScreen(state: widget.state, source: s),
                ));
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final pending = widget.state.pendingUpdateCount;
        return Scaffold(
        appBar: AppBar(
          title: Text(pending > 0 ? '源（$pending 个仓库待更新）' : '源'),
          actions: [
            IconButton(
              tooltip: '剪贴板导入 JSON',
              icon: const Icon(Icons.content_paste_go),
              onPressed: _importFromClipboard,
            ),
            IconButton(
              tooltip: '新建源',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SourceEditorScreen(state: widget.state),
              )),
            ),
            IconButton(
              tooltip: '订阅仓库',
              icon: _subscribing
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_sync_outlined),
              onPressed: _subscribing ? null : _subscribeDialog,
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) async {
                if (v == 'backup') {
                  _importPipimiaoBackup();
                } else if (v == 'builtin') {
                  final n = await widget.state.importBuiltinSources();
                  if (mounted) {
                    setState(() => _lastResult =
                        n > 0 ? '已从内置快照恢复 $n 个源' : '内置快照的源已全部在列');
                  }
                } else if (v == 'probeHealth') {
                  _probeHealth();
                } else if (v == 'refreshAll') {
                  await _refreshAllRepos();
                } else if (v == 'disableUnhealthy') {
                  final n = await widget.state.disableUnhealthySources();
                  if (mounted) {
                    setState(() => _lastResult =
                        n > 0 ? '已禁用 $n 个失效源（连续失败≥3，可重新打开开关恢复）' : '没有连续失败≥3 的源');
                  }
                } else if (v == 'resetHealth') {
                  final n = await widget.state.resetSourceHealth();
                  if (mounted) {
                    setState(() => _lastResult = '已清除 $n 个源的失败记录');
                  }
                }
              },
              itemBuilder: (context) => [
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
                if (widget.state.repos.isNotEmpty)
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
                if (widget.state.sources.isNotEmpty)
                  PopupMenuItem(
                    value: 'probeHealth',
                    child: ListTile(
                      leading: _probing
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
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
                    leading: Icon(Icons.block_outlined,
                        color: widget.state.sources.any((s) => s.isUnhealthy)
                            ? scheme.error
                            : null),
                    title: const Text('禁用失效源'),
                    subtitle: Text(
                        '连续失败≥3 的启用源（当前 ${widget.state.sources.where((s) => s.isUnhealthy && s.enabled).length} 个）'),
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
        body: Column(
          children: [
            if (_lastResult != null)
              Material(
                color: scheme.surfaceContainerHighest,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(_lastResult!, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _lastResult = null),
                  ),
                ),
              ),
            if (widget.state.repos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('已订阅仓库 (${widget.state.repos.length})',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
            if (widget.state.repos.isNotEmpty)
              ...widget.state.repos.map((r) {
                final lastAt = widget.state.repoLastRefresh[r];
                final last = lastAt == null
                    ? '尚未检查更新'
                    : '上次更新: ${DateTime.fromMillisecondsSinceEpoch(lastAt).toString().substring(0, 16)}';
                final u = widget.state.repoUpdates[r];
                final hasPending = u?.hasPending ?? false;
                final pendingText = hasPending
                    ? (u!.lastRuleVersion >= 0
                        ? ' · 有新版本 v${u.lastRuleVersion}→v${u.pendingVersion}'
                        : ' · 有新版本 v${u.pendingVersion}')
                    : '';
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.link,
                    color: hasPending ? scheme.primary : null,
                  ),
                  title: Text(r, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('$last$pendingText',
                      style: TextStyle(
                          fontSize: 11,
                          color: hasPending
                              ? scheme.primary
                              : scheme.onSurfaceVariant)),
                  trailing: _refreshingRepo == r || _refreshingRepo == '*'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : hasPending
                          ? IconButton(
                              tooltip: '应用更新（v${u!.pendingVersion}）',
                              icon: Icon(Icons.new_releases,
                                  size: 20, color: scheme.primary),
                              onPressed: () => _refreshRepo(r),
                            )
                          : IconButton(
                              tooltip: '检查更新',
                              icon: const Icon(Icons.sync, size: 20),
                              onPressed: () => _refreshRepo(r),
                            ),
                );
              }),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('源 (${widget.state.sources.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
            Expanded(
              child: widget.state.sources.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.source_outlined,
                              size: 64, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          const Text('还没有源'),
                          const SizedBox(height: 4),
                          const Text('点右上角订阅一个仓库',
                              style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: widget.state.sources.length,
                      itemBuilder: (context, i) {
                        final s = widget.state.sources[i];
                        final unhealthy = s.isUnhealthy;
                        final recentlyFailed =
                            s.failCount > 0 && s.lastError.isNotEmpty;
                        final subtitle = [
                          if (s.group.isNotEmpty) s.group,
                          s.url,
                          if (recentlyFailed)
                            '最近失败(${s.failCount}): ${s.lastError}',
                        ]
                            .where((e) => e.isNotEmpty)
                            .join(' · ');
                        return ListTile(
                          leading: Icon(
                            Icons.book_outlined,
                            color: unhealthy
                                ? scheme.error
                                : (recentlyFailed ? scheme.secondary : null),
                          ),
                          title: Text(s.name.isEmpty ? s.id : s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: unhealthy
                                  ? TextStyle(color: scheme.error)
                                  : null),
                          subtitle: Text(
                            subtitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: unhealthy
                                ? TextStyle(color: scheme.error)
                                : null,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (unhealthy)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.error_outline,
                                      size: 18, color: scheme.error),
                                ),
                              Switch(
                                value: s.enabled,
                                onChanged: (_) =>
                                    widget.state.toggleSource(s.id),
                              ),
                            ],
                          ),
                          onLongPress: () => _showSourceActions(s),
                        );
                      },
                    ),
            ),
          ],
        ),
        );
      },
    );
  }
}
