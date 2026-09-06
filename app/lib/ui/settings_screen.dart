import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// 设置。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _adMsg;

  Future<void> _importAdBlock() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: '选择广告拦截规则 JSON',
      );
      final path = picked?.path;
      if (path == null) return;
      final ok = await widget.state.setAdBlock(File(path).readAsStringSync());
      setState(() {
        _adMsg = ok
            ? '已导入广告拦截规则（${widget.state.adBlock!.urlRules.length} 条 URL / ${widget.state.adBlock!.nameRules.length} 条名称）'
            : '导入失败：JSON 解析失败';
      });
    } catch (e) {
      setState(() => _adMsg = '导入失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final adBlock = widget.state.adBlock;
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) => ListView(
        children: [
          const _Header('外观'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式'),
            value: widget.state.darkMode,
            onChanged: (v) => widget.state.setDark(v),
          ),
          const _Header('数据'),
          const ListTile(
            leading: Icon(Icons.cloud_upload_outlined),
            title: Text('WebDAV 备份/恢复'),
            subtitle: Text('规划中（Phase 4）'),
            enabled: false,
          ),
          ListTile(
            leading: Icon(
              Icons.block_outlined,
              color: adBlock != null ? Theme.of(context).colorScheme.primary : null,
            ),
            title: const Text('广告拦截规则'),
            subtitle: Text(_adMsg ??
                (adBlock != null
                    ? '已启用：${adBlock.urlRules.length} 条 URL / ${adBlock.nameRules.length} 条名称正则'
                    : '导入规则 JSON（urlRules 正则过滤图片地址，nameRules 过滤章节名）')),
            trailing: adBlock == null
                ? IconButton(
                    tooltip: '导入规则 JSON',
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: _importAdBlock,
                  )
                : IconButton(
                    tooltip: '清除规则',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.state.setAdBlock(null);
                      if (mounted) setState(() => _adMsg = null);
                    },
                  ),
            onTap: _importAdBlock,
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
