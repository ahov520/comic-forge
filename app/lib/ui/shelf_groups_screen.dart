import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/shelf_groups.dart';
import 'widgets.dart';

Future<String?> _editGroup(
  BuildContext context,
  ShelfGroups groups, {
  ShelfGroup? group,
}) => showDialog<String>(
  context: context,
  builder: (_) => _GroupNameDialog(groups: groups, group: group),
);

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.groups, this.group});
  final ShelfGroups groups;
  final ShelfGroup? group;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _controller = TextEditingController(text: widget.group?.name);
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
    final group = widget.group;
    final id = group?.id ?? await widget.groups.create(_controller.text);
    if (group != null) await widget.groups.rename(id, _controller.text);
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.group == null ? '新建分组' : '重命名分组'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: ShelfGroups.maxNameLength,
        decoration: const InputDecoration(labelText: '分组名称'),
        validator: (value) =>
            widget.groups.nameError(value ?? '', exceptId: widget.group?.id),
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

class ShelfGroupsScreen extends StatelessWidget {
  const ShelfGroupsScreen({super.key, required this.state});
  final AppState state;

  Future<void> _delete(BuildContext context, ShelfGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('删除「${group.name}」？漫画和阅读进度会保留。'),
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
    if (confirmed == true) await state.shelfGroups.delete(group.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final groups = state.shelfGroups;
      return Scaffold(
        appBar: AppBar(
          title: const Text('书架分组'),
          actions: [
            IconButton(
              tooltip: '新建分组',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => _editGroup(context, groups),
            ),
          ],
        ),
        body: groups.groups.isEmpty
            ? EmptyStateView(
                icon: Icons.folder_outlined,
                title: '还没有自定义分组',
                message: '创建分组后，长按书架漫画即可设置。一本漫画可加入多个分组。',
                actionLabel: '新建分组',
                onAction: () => _editGroup(context, groups),
              )
            : ListView(
                children: [
                  for (final group in groups.groups)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(group.name),
                      subtitle: Text(
                        '${state.shelf.where((book) => groups.groupsFor(book.bookUrl).contains(group.id)).length} 本漫画',
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: '${group.name}的操作',
                        onSelected: (action) {
                          if (action == 'rename') {
                            _editGroup(context, groups, group: group);
                          } else {
                            _delete(context, group);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除分组')),
                        ],
                      ),
                    ),
                ],
              ),
      );
    },
  );
}

Future<void> showShelfGroupPicker(
  BuildContext context,
  AppState state,
  Book book,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ShelfGroupPicker(state: state, book: book),
);

class _ShelfGroupPicker extends StatefulWidget {
  const _ShelfGroupPicker({required this.state, required this.book});
  final AppState state;
  final Book book;

  @override
  State<_ShelfGroupPicker> createState() => _ShelfGroupPickerState();
}

class _ShelfGroupPickerState extends State<_ShelfGroupPicker> {
  late final _selected = widget.state.shelfGroups
      .groupsFor(widget.book.bookUrl)
      .toSet();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) => SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                '设置分组 · ${widget.book.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建分组'),
              onTap: () async {
                final id = await _editGroup(context, widget.state.shelfGroups);
                if (mounted && id != null) setState(() => _selected.add(id));
              },
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.state.shelfGroups.groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('新建分组以整理这本漫画。'),
                    ),
                  for (final group in widget.state.shelfGroups.groups)
                    CheckboxListTile(
                      key: ValueKey('assign-${group.id}'),
                      title: Text(group.name),
                      value: _selected.contains(group.id),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(group.id);
                        } else {
                          _selected.remove(group.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('清空分组'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      await widget.state.assignShelfGroups(
                        widget.book,
                        _selected,
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
