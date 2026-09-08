import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backup_service.dart';
import '../state/app_state.dart';
import '../state/shelf_update_schedule.dart';
import 'domain_blacklist_screen.dart';
import 'downloads_screen.dart';
import 'reading_history_screen.dart';
import 'reading_stats_screen.dart';
import 'widgets.dart';

/// 设置。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    this.saveLocalBackup,
    this.shareLocalBackup,
    this.pickLocalBackup,
  });
  final AppState state;

  /// 测试可注入；默认走系统保存/分享/选文件。
  final Future<bool> Function(String fileName, String text)? saveLocalBackup;
  final Future<void> Function(String fileName, String text)? shareLocalBackup;
  final Future<String?> Function()? pickLocalBackup;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _adMsg;
  String? _backupMsg;

  Future<void> _chooseShelfUpdateInterval() async {
    final selected = await showModalBottomSheet<ShelfUpdateInterval>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('书架更新检查间隔')),
              for (final interval in ShelfUpdateInterval.values)
                ListTile(
                  title: Text(interval.label),
                  trailing:
                      widget.state.shelfUpdateSchedule.interval == interval
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, interval),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      await widget.state.shelfUpdateSchedule.setInterval(selected);
    }
  }

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

  Future<void> _exportLocalBackup() async {
    final text = BackupService.exportJson(widget.state);
    final name = BackupService.suggestedFileName();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出本地备份', style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '包含书架、源、阅读历史、章节书签和设置。不含离线图片与 WebDAV 密码。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('分享'),
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        await _shareBackup(name, text);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('保存到文件'),
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        await _saveBackup(name, text);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareBackup(String name, String text) async {
    try {
      if (widget.shareLocalBackup != null) {
        await widget.shareLocalBackup!(name, text);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsString(text);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Comic Forge 备份',
          ),
        );
      }
      if (mounted) setState(() => _backupMsg = '已分享备份 $name');
    } catch (e) {
      if (mounted) setState(() => _backupMsg = '分享失败：$e');
    }
  }

  Future<void> _saveBackup(String name, String text) async {
    try {
      final saved = widget.saveLocalBackup != null
          ? await widget.saveLocalBackup!(name, text)
          : await FilePicker.saveFile(
                  fileName: name,
                  bytes: Uint8List.fromList(utf8.encode(text)),
                  mimeType: 'application/json',
                  dialogTitle: '保存 Comic Forge 备份',
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                ) !=
                null;
      if (!mounted) return;
      setState(() => _backupMsg = saved ? '已保存备份 $name' : _backupMsg);
    } catch (e) {
      if (mounted) setState(() => _backupMsg = '保存失败：$e');
    }
  }

  Future<void> _importLocalBackup() async {
    try {
      final text = widget.pickLocalBackup != null
          ? await widget.pickLocalBackup!()
          : await _pickBackupText();
      if (text == null || !mounted) return;
      BackupService.parsePayload(text);
      final mode = await showModalBottomSheet<BackupImportMode>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导入本地备份', style: Theme.of(sheetCtx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '合并：保留本地，补齐备份中的新增与较新进度、历史和书签。\n'
                  '覆盖：用备份替换书架、源、进度、历史、书签和已包含的设置。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(sheetCtx, BackupImportMode.merge),
                        child: const Text('合并导入'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () =>
                            Navigator.pop(sheetCtx, BackupImportMode.overwrite),
                        child: const Text('覆盖导入'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (mode == null || !mounted) return;
      final r = await BackupService.importJson(widget.state, text, mode: mode);
      if (!mounted) return;
      final action = mode == BackupImportMode.overwrite ? '覆盖' : '合并';
      setState(() {
        _backupMsg =
            '$action完成：源 ${r.sources} · 书架 ${r.shelf} · 历史 ${r.history} · 书签 ${r.bookmarks}';
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _backupMsg = e.message);
    } catch (e) {
      if (mounted) setState(() => _backupMsg = '导入失败：$e');
    }
  }

  Future<String?> _pickBackupText() async {
    final picked = await FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: '选择 Comic Forge 备份文件',
    );
    final path = picked?.path;
    if (path == null) return null;
    return File(path).readAsString();
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
                                          '恢复完成：源 ${r.sources} · 书架 ${r.shelf} · 历史 ${r.history} · 书签 ${r.bookmarks}',
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
                    '恢复时合并书架、订阅、历史和书签，保留源的启停设置，阅读进度采用较新的记录。',
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
                SwitchTheme(
                  // 去掉轨道两侧内边距，让可见右缘与其它行尾控件对齐。
                  data: SwitchTheme.of(
                    context,
                  ).copyWith(padding: EdgeInsets.zero),
                  child: SwitchListTile(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('深色模式'),
                    value: widget.state.darkMode,
                    onChanged: (v) => widget.state.setDark(v),
                  ),
                ),
              ),
              const _Header('书架'),
              row(
                SwitchListTile(
                  secondary: const Icon(Icons.update),
                  title: const Text('自动检查书架更新'),
                  subtitle: const Text('前台定时检查，回到应用时补查到期更新'),
                  value: widget.state.shelfUpdateSchedule.enabled,
                  onChanged: widget.state.shelfUpdateSchedule.setEnabled,
                ),
              ),
              row(
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('检查间隔'),
                  subtitle: Text(
                    widget.state.shelfUpdateSchedule.interval.label,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: widget.state.shelfUpdateSchedule.enabled,
                  onTap: widget.state.shelfUpdateSchedule.enabled
                      ? _chooseShelfUpdateInterval
                      : null,
                ),
              ),
              row(
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('更新通知'),
                  subtitle: const Text('发现新章节时发送系统通知，点按打开漫画'),
                  value: widget.state.updateNotifications.enabled,
                  onChanged: (value) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final allowed = await widget.state
                        .setUpdateNotificationsEnabled(value);
                    if (!allowed && value && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('未授予通知权限，可在系统设置中开启')),
                      );
                    }
                  },
                ),
              ),
              const _Header('数据'),
              row(
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('阅读统计'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReadingStatsScreen(
                        stats: widget.state.readingStats,
                        sources: widget.state.sources,
                      ),
                    ),
                  ),
                ),
              ),
              row(
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('阅读历史'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReadingHistoryScreen(state: widget.state),
                    ),
                  ),
                ),
              ),
              row(
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('下载管理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DownloadsScreen(state: widget.state),
                    ),
                  ),
                ),
              ),
              if (BackupService.supportsLocalExchange) ...[
                row(
                  ListTile(
                    leading: const Icon(Icons.ios_share_outlined),
                    title: const Text('导出本地备份'),
                    subtitle: Text(
                      _backupMsg ?? '分享或保存书架、源、设置、历史和书签',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exportLocalBackup,
                  ),
                ),
                row(
                  ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('导入本地备份'),
                    subtitle: Text(
                      _backupMsg ?? '可选择合并或覆盖现有数据',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _importLocalBackup,
                  ),
                ),
              ],
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
              row(
                ListTile(
                  leading: Icon(
                    Icons.domain_disabled_outlined,
                    color: widget.state.blockedDomains.isNotEmpty
                        ? scheme.primary
                        : null,
                  ),
                  title: const Text('域名黑名单'),
                  subtitle: Text(
                    widget.state.blockedDomains.isEmpty
                        ? '未拦截任何域名'
                        : '已拦截 ${widget.state.blockedDomains.length} 个域名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          DomainBlacklistScreen(state: widget.state),
                    ),
                  ),
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
