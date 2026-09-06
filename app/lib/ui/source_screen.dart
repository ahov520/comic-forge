import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

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
