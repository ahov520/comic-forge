import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/reading_pref_presets.dart';
import 'widgets.dart';

Future<String?> showReaderPresetNameDialog(
  BuildContext context,
  AppState state, {
  ReadingPrefPreset? preset,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PresetNameDialog(state: state, preset: preset),
);

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.state, this.preset});
  final AppState state;
  final ReadingPrefPreset? preset;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final _controller = TextEditingController(text: widget.preset?.name);
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final preset = widget.preset;
    try {
      if (preset == null) {
        final id = await widget.state.saveCurrentReaderPreset(_controller.text);
        if (mounted) Navigator.of(context).pop(id);
      } else {
        await widget.state.readerPresets.rename(preset.id, _controller.text);
        if (mounted) Navigator.of(context).pop(preset.id);
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.preset == null ? '保存阅读预设' : '重命名预设'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: ReadingPrefPresets.maxNameLength,
        decoration: const InputDecoration(labelText: '预设名称'),
        validator: (value) => widget.state.readerPresets.nameError(
          value ?? '',
          exceptId: widget.preset?.id,
        ),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _saving ? null : _save, child: const Text('保存')),
    ],
  );
}

Future<bool> confirmDeleteReaderPreset(
  BuildContext context,
  ReadingPrefPreset preset,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除预设'),
      content: Text('删除「${preset.name}」？当前阅读设置会保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

String readerPresetsSubtitle(AppState state) {
  final presets = state.readerPresets.presets;
  if (presets.isEmpty) return '保存滚动/翻页、亮度和音量键';
  final active = state.activeReaderPreset;
  if (active != null) return '当前「${active.name}」';
  return '${presets.length} 个预设';
}

/// 设置子页：列出、保存、应用、重命名和删除阅读偏好预设。
class ReadingPrefPresetsScreen extends StatelessWidget {
  const ReadingPrefPresetsScreen({super.key, required this.state});
  final AppState state;

  Future<void> _save(BuildContext context) async {
    if (state.readerPresets.presets.length >= ReadingPrefPresets.maxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多保存 ${ReadingPrefPresets.maxCount} 个预设')),
      );
      return;
    }
    await showReaderPresetNameDialog(context, state);
  }

  Future<void> _delete(BuildContext context, ReadingPrefPreset preset) async {
    if (await confirmDeleteReaderPreset(context, preset)) {
      await state.readerPresets.delete(preset.id);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final presets = state.readerPresets.presets;
      final active = state.activeReaderPreset;
      return Scaffold(
        appBar: AppBar(
          title: const Text('阅读预设'),
          actions: [
            IconButton(
              tooltip: '保存当前为预设',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () => _save(context),
            ),
          ],
        ),
        body: presets.isEmpty
            ? EmptyStateView(
                icon: Icons.tune,
                title: '还没有阅读预设',
                message: '把当前的滚动/翻页、亮度和音量键保存下来，之后一点即可切换。',
                actionLabel: '保存当前设置',
                onAction: () => _save(context),
              )
            : ListView(
                children: [
                  for (final preset in presets)
                    ListTile(
                      key: ValueKey('reader-preset-${preset.id}'),
                      leading: Icon(
                        active?.id == preset.id
                            ? Icons.check_circle
                            : Icons.tune,
                      ),
                      title: Text(preset.name),
                      subtitle: Text(preset.summary),
                      onTap: () => state.applyReaderPreset(preset.id),
                      trailing: PopupMenuButton<String>(
                        tooltip: '${preset.name}的操作',
                        onSelected: (action) async {
                          switch (action) {
                            case 'update':
                              await state.updateReaderPreset(preset.id);
                            case 'rename':
                              await showReaderPresetNameDialog(
                                context,
                                state,
                                preset: preset,
                              );
                            case 'delete':
                              await _delete(context, preset);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'update',
                            child: Text('更新为当前设置'),
                          ),
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除预设')),
                        ],
                      ),
                    ),
                ],
              ),
      );
    },
  );
}
