/// JS 钩子空实现（web 等不支持 dart:ffi 的平台）。
/// 取图回退到普通规则解析，不影响其余功能。
class FlutterJsHook {
  FlutterJsHook._();

  static final FlutterJsHook instance = FlutterJsHook._();

  Future<String?> call(String code, Map<String, dynamic> env) async {
    return null;
  }
}
