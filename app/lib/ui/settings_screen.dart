import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backup_service.dart';
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

  /// WebDAV 配置与备份/恢复面板。
  void _showWebDavSheet(BuildContext context) {
    final cfg = widget.state.webDavConfig ?? const {
      'url': '',
      'user': '',
      'pass': '',
      'path': BackupService.defaultRemotePath,
    };
    final url = TextEditingController(text: cfg['url']);
    final user = TextEditingController(text: cfg['user']);
    final pass = TextEditingController(text: cfg['pass']);
    final path = TextEditingController(
        text: (cfg['path']?.isEmpty ?? true)
            ? BackupService.defaultRemotePath
            : cfg['path']);
    String? msg;
    bool busy = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 24 + MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WebDAV 备份/恢复',
                  style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                  controller: url,
                  decoration: const InputDecoration(
                      labelText: '服务器地址（https://…）',
                      isDense: true,
                      border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(controller: user,
                        decoration: const InputDecoration(
                            labelText: '账号', isDense: true,
                            border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(controller: pass, obscureText: true,
                        decoration: const InputDecoration(
                            labelText: '密码', isDense: true,
                            border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: path,
                  decoration: const InputDecoration(
                      labelText: '备份文件远端路径', isDense: true,
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: busy
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('备份'),
                    onPressed: busy ? null : () async {
                      setSheet(() { busy = true; msg = null; });
                      try {
                        await widget.state.setWebDavConfig({
                          'url': url.text.trim(),
                          'user': user.text.trim(),
                          'pass': pass.text,
                          'path': path.text.trim(),
                        });
                        await BackupService.backupToWebDav(
                          st: widget.state,
                          baseUrl: url.text.trim(),
                          username: user.text.trim(),
                          password: pass.text,
                          remotePath: path.text.trim(),
                        );
                        setSheet(() => msg = '备份完成 ✓（覆盖远端同名文件）');
                      } catch (e) {
                        setSheet(() => msg = '备份失败：$e');
                      } finally {
                        if (sheetCtx.mounted) setSheet(() => busy = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('恢复'),
                    onPressed: busy ? null : () async {
                      setSheet(() { busy = true; msg = null; });
                      try {
                        final r = await BackupService.restoreFromWebDav(
                          st: widget.state,
                          baseUrl: url.text.trim(),
                          username: user.text.trim(),
                          password: pass.text,
                          remotePath: path.text.trim(),
                        );
                        await widget.state.setWebDavConfig({
                          'url': url.text.trim(),
                          'user': user.text.trim(),
                          'pass': pass.text,
                          'path': path.text.trim(),
                        });
                        setSheet(() => msg =
                            '恢复完成：源 ${r.sources} · 书架 ${r.shelf} · 进度 ${r.progress} · 订阅 ${r.repos}');
                      } catch (e) {
                        setSheet(() => msg = '恢复失败：$e');
                      } finally {
                        if (sheetCtx.mounted) setSheet(() => busy = false);
                      }
                    },
                  ),
                ),
              ]),
              if (msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(msg!, style: const TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 4),
              Text('合并语义：源按 id 替换（保留本地启停），书架并集，进度取较新，订阅并集。',
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(sheetCtx).colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
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
          ListTile(
            leading: Icon(
              Icons.cloud_upload_outlined,
              color: widget.state.webDavConfig != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: const Text('WebDAV 备份/恢复'),
            subtitle: Text(widget.state.webDavConfig == null
                ? '未配置 · 点击填写服务器与账号（书架/源库/进度/订阅）'
                : '已配置 ${widget.state.webDavConfig!['url']}'),
            onTap: () => _showWebDavSheet(context),
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
