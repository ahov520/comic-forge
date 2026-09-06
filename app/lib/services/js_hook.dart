// 平台分流：Android/iOS 用 flutter_js（QuickJS）；web 等不支持平台用空实现。
export 'js_hook_stub.dart'
    if (dart.library.io) 'js_hook_flutterjs.dart';
