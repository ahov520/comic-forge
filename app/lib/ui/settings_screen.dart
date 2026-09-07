import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backup_service.dart';
import '../state/app_state.dart';
import 'widgets.dart';

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
        dialogTitle: '选择广告拦截规则文件',
      );
      final path = picked?.path;
      if (path == null || !mounted) return;
      final contents = await File(path).readAsString();
      if (!mounted) return;
      final ok = await widget.state.setAdBlock(contents);
      if (!mounted) return;
      setState(() {
        _adMsg = ok ? null : '未能识别规则，请重新选择文件';
      });
    } catch (_) {
      if (mounted) setState(() => _adMsg = '无法读取规则文件，请重试');
    }
  }

  /// WebDAV 配置与备份/恢复面板。
  void _showWebDavSheet(BuildContext context) {
    final cfg =
        widget.state.webDavConfig ??
        const {
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
          : cfg['path'],
    );
    String? msg;
    bool busy = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WebDAV 备份/恢复',
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(
                      labelText: '服务器地址（https://…）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: user,
                          decoration: const InputDecoration(
                            labelText: '账号',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: pass,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '密码',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: path,
                    decoration: const InputDecoration(
                      labelText: '备份文件远端路径',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 18,
                                ),
                          label: const Text('备份'),
                          onPressed: busy
                              ? null
                              : () async {
                                  setSheet(() {
                                    busy = true;
                                    msg = null;
                                  });
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
                                    if (!sheetCtx.mounted) return;
                                    setSheet(() => msg = '备份完成 ✓（覆盖远端同名文件）');
                                  } catch (e) {
                                    if (sheetCtx.mounted) {
                                      setSheet(() => msg = '备份失败：$e');
                                    }
                                  } finally {
                                    if (sheetCtx.mounted) {
                                      setSheet(() => busy = false);
                                    }
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            size: 18,
                          ),
                          label: const Text('恢复'),
                          onPressed: busy
                              ? null
                              : () async {
                                  setSheet(() {
                                    busy = true;
                                    msg = null;
                                  });
                                  try {
                                    final r =
                                        await BackupService.restoreFromWebDav(
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
                                    if (!sheetCtx.mounted) return;
                                    setSheet(
                                      () => msg =
                                          '恢复完成：源 ${r.sources} · 书架 ${r.shelf} · 进度 ${r.progress} · 订阅 ${r.repos}',
                                    );
                                  } catch (e) {
                                    if (sheetCtx.mounted) {
                                      setSheet(() => msg = '恢复失败：$e');
                                    }
                                  } finally {
                                    if (sheetCtx.mounted) {
                                      setSheet(() => busy = false);
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  if (msg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(msg!, style: const TextStyle(fontSize: 12)),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '恢复时合并书架与订阅，保留源的启停设置，阅读进度采用较新的记录。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(sheetCtx).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) => _buildSettings(context),
  );

  Widget _buildSettings(BuildContext context) {
    final adBlock = widget.state.adBlock;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final server =
        Uri.tryParse(widget.state.webDavConfig?['url'] ?? '')?.host ?? '';
    final ruleActionStyle = IconButton.styleFrom(
      // 图标与行尾箭头对齐，同时保留 48px 点击区域。
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.zero,
      alignment: AlignmentDirectional.centerEnd,
    );
    Widget row(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: child,
      ),
    );
    return SafeArea(
      bottom: false,
      child: ListTileTheme(
        data: ListTileThemeData(
          // dense 会把标题强制改为 13px；稿中行标题为 bodyMedium（14px）。
          minTileHeight: 48,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minLeadingWidth: 18,
          horizontalTitleGap: 12,
          minVerticalPadding: 13,
          titleTextStyle: textTheme.bodyMedium,
          subtitleTextStyle: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          iconColor: scheme.onSurfaceVariant,
        ),
        child: IconTheme.merge(
          data: const IconThemeData(size: 18),
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: ScreenTitle('设置'),
              ),
              const _Header('外观'),
              row(
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('深色模式'),
                  value: widget.state.darkMode,
                  onChanged: (v) => widget.state.setDark(v),
                ),
              ),
              const _Header('数据'),
              row(
                ListTile(
                  leading: Icon(
                    Icons.cloud_upload_outlined,
                    color: server.isNotEmpty ? scheme.primary : null,
                  ),
                  title: const Text('WebDAV 备份 / 恢复'),
                  subtitle: Text(
                    server.isEmpty ? '未配置服务器' : server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showWebDavSheet(context),
                ),
              ),
              row(
                ListTile(
                  leading: Icon(
                    Icons.block_outlined,
                    color: adBlock != null ? scheme.primary : null,
                  ),
                  title: const Text('广告拦截规则'),
                  subtitle: Text(
                    _adMsg ??
                        (adBlock != null
                            ? '已启用 · ${adBlock.urlRules.length} 条图片规则'
                            : '导入规则以过滤广告图片'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: adBlock == null
                      ? IconButton(
                          style: ruleActionStyle,
                          tooltip: '导入广告规则',
                          icon: const Icon(Icons.upload_file_outlined),
                          onPressed: _importAdBlock,
                        )
                      : IconButton(
                          style: ruleActionStyle,
                          tooltip: '清除规则',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await widget.state.setAdBlock(null);
                            if (mounted) setState(() => _adMsg = null);
                          },
                        ),
                  onTap: _importAdBlock,
                ),
              ),
              const _Header('关于'),
              row(
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Comic Forge v0.1.0'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
                child: Text(
                  '本地规则工具 · 不提供漫画内容',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
