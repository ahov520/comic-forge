import 'dart:io';

import 'package:engine/engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';

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
            helperText: '支持明文 store.json 仓库；ppcat 加密仓库待密钥取证后开放',
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('源'),
          actions: [
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
              onSelected: (v) {
                if (v == 'backup') _importPipimiaoBackup();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'backup',
                  child: ListTile(
                    leading: Icon(Icons.restore_outlined),
                    title: Text('导入皮皮喵备份'),
                    subtitle: Text('.pbak · 提取分享源与订阅'),
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
              ...widget.state.repos.map((r) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.link),
                    title: Text(r, style: const TextStyle(fontSize: 13)),
                  )),
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
                              size: 64, color: scheme.outline),
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
                        return ListTile(
                          leading: const Icon(Icons.book_outlined),
                          title: Text(s.name.isEmpty ? s.id : s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [if (s.group.isNotEmpty) s.group, s.url]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Switch(
                            value: s.enabled,
                            onChanged: (_) =>
                                widget.state.toggleSource(s.id),
                          ),
                          onLongPress: () =>
                              widget.state.removeSource(s.id),
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
