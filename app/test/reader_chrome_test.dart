import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_forge/ui/reader_chrome.dart';

void main() {
  testWidgets('毛玻璃条使用 BackdropFilter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ReaderFrostedBar(child: Text('海贼王 · 第1044话')),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('海贼王 · 第1044话'), findsOneWidget);
  });

  testWidgets('顶栏可见显示标题，隐藏时 IgnorePointer 不拦点击', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ReaderTopChrome(
            visible: true,
            title: '源A · 海贼王 · 第1044话',
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    expect(find.text('源A · 海贼王 · 第1044话'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    expect(closed, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ReaderTopChrome(visible: false, title: '隐藏标题'),
        ),
      ),
    );
    final ignore = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(ReaderTopChrome),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignore.ignoring, isTrue);
  });

  testWidgets('底栏话间导航：上一话禁用、下一话可点', (tester) async {
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ReaderBottomChrome(
            visible: true,
            progressLabel: '1/12',
            canPrev: false,
            canNext: true,
            onNext: () => next++,
          ),
        ),
      ),
    );
    expect(find.text('上一话'), findsOneWidget);
    expect(find.text('下一话'), findsOneWidget);
    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('1/12'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.tap(find.text('上一话'));
    await tester.pump();
    expect(next, 0);
    await tester.tap(find.text('下一话'));
    await tester.pump();
    expect(next, 1);
  });

  testWidgets('可见时渲染顶/底渐变遮罩（IgnorePointer 不拦点击）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            ColoredBox(color: Colors.white, child: SizedBox.expand()),
            ReaderChromeOverlay(visible: true, topInset: 24, bottomInset: 16),
          ],
        ),
      ),
    );
    final gradients = find
        .descendant(
          of: find.byType(ReaderChromeOverlay),
          matching: find.byWidgetPredicate(
            (d) =>
                d is DecoratedBox &&
                d.decoration is BoxDecoration &&
                (d.decoration as BoxDecoration).gradient != null,
          ),
        )
        .evaluate();
    expect(gradients, hasLength(2), reason: '顶部+底部两条渐变');
    // IgnorePointer 包裹（点击穿透）
    expect(
      find.descendant(
        of: find.byType(ReaderChromeOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('不可见时整体收起（不渲染渐变、不占布局）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            ColoredBox(color: Colors.white, child: SizedBox.expand()),
            ReaderChromeOverlay(visible: false, topInset: 24, bottomInset: 16),
          ],
        ),
      ),
    );
    expect(find.byType(ReaderChromeOverlay), findsOneWidget);
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (d) =>
                d.decoration is BoxDecoration &&
                (d.decoration as BoxDecoration).gradient != null,
          ),
      isEmpty,
    );
  });
}
