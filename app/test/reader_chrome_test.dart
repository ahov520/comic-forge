import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    await tester.tap(find.text('上一话'));
    await tester.pump();
    expect(next, 0);
    await tester.tap(find.text('下一话'));
    await tester.pump();
    expect(next, 1);
  });

  testWidgets('目录表点选当前之外的话', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderCatalogSheet(
            chapters: [
              Chapter(title: '第1话', url: '/c1'),
              Chapter(title: '第2话', url: '/c2'),
              Chapter(title: '第3话', url: '/c3'),
            ],
            currentIndex: 0,
            onPick: (i) => picked = i,
          ),
        ),
      ),
    );
    expect(find.text('目录 · 3 话'), findsOneWidget);
    expect(find.text('第1话'), findsOneWidget);
    await tester.tap(find.text('第3话'));
    expect(picked, 2);
  });

  testWidgets('窄屏大字号底栏避开安全区，隐藏后点击穿透', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var catalog = 0;
    var brightness = 0;
    var pageTaps = 0;

    Widget reader({required bool visible}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(bottom: 24),
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => pageTaps++,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ReaderBottomChrome(
                visible: visible,
                progressLabel: '1044/1300',
                canPrev: false,
                canNext: false,
                onCatalog: () => catalog++,
                onBrightness: () => brightness++,
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(reader(visible: true));
    final progress = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('1044/\n1300'),
        matching: find.byType(RichText),
      ),
    );
    expect(progress.didExceedMaxLines, isFalse, reason: '当前话和总话数均应完整可读');
    await tester.tap(find.byIcon(Icons.menu));
    await tester.tap(find.text('亮度'));
    expect(catalog, 1);
    expect(brightness, 1);
    expect(tester.getRect(find.text('亮度')).bottom, lessThanOrEqualTo(616));
    expect(tester.takeException(), isNull);

    final catalogPosition = tester.getCenter(find.byIcon(Icons.menu));
    await tester.pumpWidget(reader(visible: false));
    await tester.pumpAndSettle();
    await tester.tapAt(catalogPosition);
    expect(catalog, 1);
    expect(pageTaps, 1);
  });

  testWidgets('千话目录打开即可看到当前话，大字号与末话仍可选相邻章节', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chapters = List.generate(
      1300,
      (i) => Chapter(title: '第${i + 1}话', url: '/chapter/$i'),
    );
    for (final scale in [1.0, 2.0]) {
      for (final current in [1043, 1299]) {
        var picked = -1;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey((scale, current)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(bottom: 24),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: ReaderCatalogSheet(
                chapters: chapters,
                currentIndex: current,
                onPick: (value) => picked = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('第${current + 1}话').hitTestable(), findsOneWidget);
        expect(find.text('第1话'), findsNothing);
        final target = current == 1299 ? current - 1 : current + 1;
        await tester.tap(find.text('第${target + 1}话'));
        expect(picked, target);
        expect(tester.takeException(), isNull);
      }
    }
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
