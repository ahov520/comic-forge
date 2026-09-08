import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/shelf_update_notices.dart';

/// 书架更新的系统通知出口；测试可注入，非 Android 走空实现。
abstract class ShelfUpdateNotifier {
  const ShelfUpdateNotifier();

  Future<void> initialize();
  Future<bool> requestPermission();
  Future<bool> show(ShelfUpdateNotice notice);
  Future<void> cancelAll();
  void setOnOpen(void Function(ShelfUpdateOpenRequest request)? handler);
  ShelfUpdateOpenRequest? takeLaunchRequest();
}

class NoopShelfUpdateNotifier implements ShelfUpdateNotifier {
  const NoopShelfUpdateNotifier();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> show(ShelfUpdateNotice notice) async => false;

  @override
  Future<void> cancelAll() async {}

  @override
  void setOnOpen(void Function(ShelfUpdateOpenRequest request)? handler) {}

  @override
  ShelfUpdateOpenRequest? takeLaunchRequest() => null;
}

const shelfUpdateNotificationChannel = MethodChannel(
  'comic-forge/notifications',
);

class AndroidShelfUpdateNotifier implements ShelfUpdateNotifier {
  AndroidShelfUpdateNotifier({MethodChannel? channel})
    : _channel = channel ?? shelfUpdateNotificationChannel;

  final MethodChannel _channel;
  void Function(ShelfUpdateOpenRequest request)? _onOpen;
  ShelfUpdateOpenRequest? _launch;
  bool _listening = false;

  @override
  Future<void> initialize() async {
    _listen();
    Object? pending;
    try {
      pending = await _channel.invokeMethod<Object>('initialize');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    _launch = ShelfUpdateOpenRequest.fromMap(pending);
  }

  @override
  Future<bool> requestPermission() async {
    _listen();
    try {
      return await _channel.invokeMethod<bool>('requestPermission') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> show(ShelfUpdateNotice notice) async {
    _listen();
    try {
      return await _channel.invokeMethod<bool>('show', {
            'id': shelfUpdateNoticeId(notice.key),
            'title': notice.book.name,
            'body': shelfUpdateNoticeBody(notice.badge),
            'bookUrl': notice.book.bookUrl,
            'sourceId': notice.book.sourceId ?? '',
          }) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  void setOnOpen(void Function(ShelfUpdateOpenRequest request)? handler) {
    _onOpen = handler;
    if (handler != null) _listen();
  }

  @override
  ShelfUpdateOpenRequest? takeLaunchRequest() {
    final launch = _launch;
    _launch = null;
    return launch;
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'opened') return;
      final request = ShelfUpdateOpenRequest.fromMap(call.arguments);
      if (request == null) return;
      final handler = _onOpen;
      if (handler != null) {
        handler(request);
      } else {
        _launch = request;
      }
    });
  }
}

ShelfUpdateNotifier createShelfUpdateNotifier() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidShelfUpdateNotifier();
  }
  return const NoopShelfUpdateNotifier();
}
