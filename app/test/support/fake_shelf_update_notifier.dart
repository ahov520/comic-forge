import 'package:comic_forge/services/shelf_update_notifier.dart';
import 'package:comic_forge/state/shelf_update_notices.dart';

class FakeShelfUpdateNotifier implements ShelfUpdateNotifier {
  FakeShelfUpdateNotifier({this.permissionGranted = true, this.launchRequest});

  bool permissionGranted;
  final shown = <ShelfUpdateNotice>[];
  int cancelAllCount = 0;
  void Function(ShelfUpdateOpenRequest request)? onOpen;
  ShelfUpdateOpenRequest? launchRequest;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<bool> show(ShelfUpdateNotice notice) async {
    shown.add(notice);
    return true;
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    shown.clear();
  }

  @override
  void setOnOpen(void Function(ShelfUpdateOpenRequest request)? handler) {
    onOpen = handler;
  }

  @override
  ShelfUpdateOpenRequest? takeLaunchRequest() {
    final launch = launchRequest;
    launchRequest = null;
    return launch;
  }

  void tap(ShelfUpdateOpenRequest request) => onOpen?.call(request);
}
