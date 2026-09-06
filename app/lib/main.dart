import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_state.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  final state = AppState();
  await state.load();
  // 启动后台检查订阅仓库更新（节流 6h，静默失败，不打断首屏）
  state.autoCheckUpdates().catchError((_) {});
  runApp(ComicForgeApp(state: state));
}

class ComicForgeApp extends StatelessWidget {
  const ComicForgeApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final scheme = ColorScheme.fromSeed(
          // Open Design human-approachable 方向 accent: oklch(56% 0.12 170)
          seedColor: const Color(0xFF169876),
          brightness: state.darkMode ? Brightness.dark : Brightness.light,
        );
        return MaterialApp(
          title: 'Comic Forge',
          debugShowCheckedModeBanner: false,
          themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
          theme: _theme(scheme),
          darkTheme: _theme(scheme),
          home: HomeShell(state: state),
        );
      },
    );
  }

  ThemeData _theme(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      // human-approachable 方向：舒适圆角(12-18)、极浅描边、无阴影卡片
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }
}
