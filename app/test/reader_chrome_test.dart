import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_forge/ui/reader_chrome.dart';

void main() {
  testWidgets('可见时渲染顶/底渐变遮罩（IgnorePointer 不拦点击）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Stack(children: [
        ColoredBox(color: Colors.white, child: SizedBox.expand()),
        ReaderChromeOverlay(visible: true, topInset: 24, bottomInset: 16),
      ]),
    ));
    final gradients = find
        .descendant(
          of: find.byType(ReaderChromeOverlay),
          matching: find.byWidgetPredicate((d) =>
              d is DecoratedBox &&
              d.decoration is BoxDecoration &&
              (d.decoration as BoxDecoration).gradient != null),
        )
        .evaluate();
    expect(gradients, hasLength(2), reason: '顶部+底部两条渐变');
    // IgnorePointer 包裹（点击穿透）
    expect(
        find.descendant(
            of: find.byType(ReaderChromeOverlay),
            matching: find.byType(IgnorePointer)),
        findsOneWidget);
  });

  testWidgets('不可见时整体收起（不渲染渐变、不占布局）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Stack(children: [
        ColoredBox(color: Colors.white, child: SizedBox.expand()),
        ReaderChromeOverlay(visible: false, topInset: 24, bottomInset: 16),
      ]),
    ));
    expect(find.byType(ReaderChromeOverlay), findsOneWidget);
    expect(
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((d) =>
            d.decoration is BoxDecoration &&
            (d.decoration as BoxDecoration).gradient != null),
        isEmpty);
  });
}
