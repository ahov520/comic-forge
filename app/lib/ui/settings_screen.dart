import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// 设置。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => ListView(
        children: [
          const _Header('外观'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式'),
            value: state.darkMode,
            onChanged: (v) => state.setDark(v),
          ),
          const _Header('数据'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('WebDAV 备份/恢复'),
            subtitle: const Text('规划中（Phase 4）'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('广告拦截规则'),
            subtitle: const Text('兼容皮皮喵广告拦截规则 JSON（规划中）'),
            enabled: false,
          ),
          const _Header('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Comic Forge'),
            subtitle: Text('v0.1.0 · 规则引擎漫画聚合阅读器\n本地工具，不内置任何源，不提供任何内容'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
