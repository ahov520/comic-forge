import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'widgets.dart';

/// 设置子页：列出、新增、删除全局域名黑名单。
class DomainBlacklistScreen extends StatefulWidget {
  const DomainBlacklistScreen({super.key, required this.state});

  final AppState state;

  @override
  State<DomainBlacklistScreen> createState() => _DomainBlacklistScreenState();
}

class _DomainBlacklistScreenState extends State<DomainBlacklistScreen> {
  final _controller = TextEditingController();
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final raw = _controller.text;
    final host = DomainBlocklist.normalize(raw);
    if (host == null) {
      setState(() => _hint = '请输入域名或网址，例如 evil.com');
      return;
    }
    final added = await widget.state.addBlockedDomain(raw);
    if (!mounted) return;
    if (!added) {
      setState(() => _hint = '$host 已在名单中');
      return;
    }
    _controller.clear();
    setState(() => _hint = '已拦截 $host');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final hosts = widget.state.blockedDomains;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const ScreenTitle('域名黑名单'),
        const SizedBox(height: 8),
        Text(
          '拦截匹配主机及其子域的浏览、搜索、阅读和下载请求。已下载的本地图片仍可离线阅读。',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('domain-block-input'),
          controller: _controller,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '域名或网址',
            hintText: 'evil.com 或 https://evil.com/path',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('domain-block-add'),
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('加入黑名单'),
        ),
        if (_hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_hint!, style: textTheme.bodySmall),
          ),
        const SizedBox(height: 20),
        Text(
          hosts.isEmpty ? '尚未拦截任何域名' : '已拦截 ${hosts.length} 个域名',
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (hosts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '加入后，对应站点的在线请求会立即失败并提示原因。',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final host in hosts)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: ListTile(
                key: ValueKey('blocked-host-$host'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                minTileHeight: 48,
                title: Text(host, style: textTheme.bodyMedium),
                trailing: IconButton(
                  tooltip: '移除 $host',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.state.removeBlockedDomain(host);
                    if (mounted) setState(() => _hint = '已移除 $host');
                  },
                ),
              ),
            ),
      ],
    );
  }
}
