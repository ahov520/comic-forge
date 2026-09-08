import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// 仅应用在前台时计时；Android 暂停期间到期的任务在恢复前台时补查。
class ShelfUpdateScheduler with WidgetsBindingObserver {
  ShelfUpdateScheduler(this.state) {
    final binding = WidgetsBinding.instance;
    _foreground =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    state.addListener(_schedule);
    _schedule();
  }

  final AppState state;
  late bool _foreground;
  bool _disposed = false;
  Timer? _timer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_disposed ||
        !_foreground ||
        state.shelf.isEmpty ||
        state.checkingShelfUpdates) {
      return;
    }
    final delay = state.shelfUpdateSchedule.nextCheckIn;
    if (delay == null) return;
    // 即使已到期也在下一轮事件触发，避免构建首屏时修改应用状态。
    _timer = Timer(delay, _check);
  }

  Future<void> _check() async {
    _timer = null;
    if (_disposed ||
        !_foreground ||
        state.shelf.isEmpty ||
        state.checkingShelfUpdates) {
      return;
    }
    final delay = state.shelfUpdateSchedule.nextCheckIn;
    if (delay == null) return;
    if (delay > Duration.zero) {
      _schedule();
      return;
    }
    try {
      await state.refreshShelfUpdates();
    } catch (_) {
      // 自动检查静默失败；最近尝试时间仍会节流，手动刷新可立即重试。
    } finally {
      if (!_disposed) _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(_schedule);
  }
}
