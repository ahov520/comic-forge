import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_state.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  final state = AppState();
  await state.load();
  // 启动后台检查订阅仓库更新（节流 6h，静默失败，不打断首屏）
  state.autoCheckUpdates().catchError((_) {});
  // 启动后台轻量体检：最多 20 源、7 天一次（优先未探测源，静默）
  state.autoProbeIfNeeded().catchError((_) {});
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
          builder: (context, child) {
            final theme = Theme.of(context);
            final dark = theme.brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (dark
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor:
                            theme.colorScheme.surfaceContainerLow,
                        systemNavigationBarIconBrightness: dark
                            ? Brightness.light
                            : Brightness.dark,
                        systemNavigationBarDividerColor: Colors.transparent,
                        systemNavigationBarContrastEnforced: false,
                      ),
              child: child!,
            );
          },
          home: HomeShell(state: state),
        );
      },
    );
  }

  ThemeData _theme(ColorScheme generated) {
    const background = Color(0xFFEFF2F4);
    const border = Color(0xFFDBDFE2);
    // 设计稿的中性底色不随种子色染绿；强调色略加深以保证白字对比度。
    const accent = Color(0xFF008668);
    final scheme = generated.brightness == Brightness.light
        ? generated.copyWith(
            primary: accent,
            onPrimary: Colors.white,
            primaryContainer: Color.alphaBlend(
              accent.withValues(alpha: 0.12),
              background,
            ),
            surface: background,
            surfaceBright: Colors.white,
            surfaceDim: border,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Colors.white,
            surfaceContainer: const Color(0xFFE9EDF0),
            surfaceContainerHigh: const Color(0xFFE3E8EC),
            surfaceContainerHighest: border,
            onSurface: const Color(0xFF0E171E),
            onSurfaceVariant: const Color(0xFF5A656D),
            outline: const Color(0xFF73808A),
            outlineVariant: border,
          )
        : generated;
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
        height: 64,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: Colors.transparent,
        labelPadding: EdgeInsets.zero,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 20,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
