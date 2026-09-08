import 'package:flutter/material.dart';

Future<bool> confirmCleanup(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '清除',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
