import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

/// 订阅地址输入：就地校验，键盘提交，横屏时并排显示输入框和操作。
class SourceSubscriptionDialog extends StatefulWidget {
  const SourceSubscriptionDialog({super.key});

  @override
  State<SourceSubscriptionDialog> createState() =>
      _SourceSubscriptionDialogState();
}

class _SourceSubscriptionDialogState extends State<SourceSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _showErrors = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    } else {
      setState(() => _showErrors = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact =
        media.size.width >= 480 &&
        media.size.height - media.viewInsets.bottom - media.padding.vertical <
            260;
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('订阅')),
    ];
    return AlertDialog(
      scrollable: true,
      semanticLabel: '订阅源仓库',
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 24 : 40,
        vertical: compact ? 8 : 24,
      ),
      contentPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
          : const EdgeInsets.fromLTRB(24, 20, 24, 24),
      title: compact ? null : const Text('订阅源仓库'),
      content: Form(
        key: _formKey,
        autovalidateMode: _showErrors
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: SizedBox(
          width: compact ? 500 : null,
          child: Flex(
            direction: compact ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: compact ? FlexFit.tight : FlexFit.loose,
                child: TextFormField(
                  controller: _controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    labelText: compact ? '订阅源仓库' : '仓库地址',
                    hintText: 'github.com/user/repo',
                    helperText: compact
                        ? null
                        : '支持 GitHub、Gitee，或 GitHub 的 user/repo 简写',
                    helperMaxLines: 3,
                    errorMaxLines: 2,
                    isDense: compact,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return '请输入仓库地址';
                    if (RepoRef.parse(value) == null) {
                      return '请输入 GitHub 或 Gitee 仓库地址';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
              ),
              if (compact) ...[const SizedBox(width: 12), ...actions],
            ],
          ),
        ),
      ),
      actions: compact ? null : actions,
    );
  }
}
