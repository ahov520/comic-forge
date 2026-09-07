import 'package:comic_forge/state/app_state.dart';
import 'package:comic_forge/ui/shelf_explore_screens.dart';
import 'package:comic_forge/ui/shelf_groups_screen.dart';
import 'package:comic_forge/ui/widgets.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  final book = Book(name: '追更漫画', bookUrl: '/one', kind: '连载中');
  final other = Book(name: '完结漫画', bookUrl: '/two', kind: '完结');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.toggleShelf(book);
    await state.toggleShelf(other);
  });

  tearDown(() => state.dispose());

  Future<void> showShelf(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShelfScreen(state: state, onExplore: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> filter(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> picker(WidgetTester tester) async {
    final tile = find
        .ancestor(of: find.text(book.name), matching: find.byType(InkWell))
        .first;
    await tester.longPress(
      find.descendant(of: tile, matching: find.byType(BookCover)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置分组'));
    await tester.pumpAndSettle();
  }

  testWidgets('书架菜单新建、验证、重命名和删除分组，书籍保留', (tester) async {
    await showShelf(tester);
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分组管理'));
    await tester.pumpAndSettle();
    expect(find.byType(ShelfGroupsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('新建分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入分组名称'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '追更');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('0 本漫画'), findsOneWidget);
    await tester.tap(find.byTooltip('追更的操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '每日追更');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('每日追更的操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('还没有自定义分组'), findsOneWidget);
    expect(state.shelf, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按多选归组，分组与连载状态叠加，空分类可恢复，清空归组', (tester) async {
    final a = await state.shelfGroups.create('追更');
    final b = await state.shelfGroups.create('喜爱');
    await showShelf(tester);
    await picker(tester);
    for (final id in [a, b]) {
      await tester.tap(find.byKey(ValueKey('assign-$id')));
      await tester.pump();
    }
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.shelfGroups.groupsFor(book.bookUrl), {a, b});
    await filter(tester, '追更');
    expect(find.text(book.name), findsOneWidget);
    expect(find.text(other.name), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '已完结'));
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有漫画'), findsOneWidget);
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text(book.name), findsOneWidget);
    expect(find.text(other.name), findsOneWidget);
    await filter(tester, '未分组');
    expect(find.text(book.name), findsNothing);
    expect(find.text(other.name), findsOneWidget);
    await filter(tester, '喜爱');
    await picker(tester);
    expect(
      tester.widget<CheckboxListTile>(find.byKey(ValueKey('assign-$a'))).value,
      isTrue,
    );
    await tester.tap(find.text('清空分组'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有漫画'), findsOneWidget);
    expect(state.shelfGroups.groupsFor(book.bookUrl), isEmpty);
    await state.shelfGroups.delete(b);
    await tester.pumpAndSettle();
    expect(find.text(book.name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('归组弹层可新建，退出不保存选择，再次打开后保存', (tester) async {
    await showShelf(tester);
    await picker(tester);
    await tester.tap(find.text('新建分组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '稍后读');
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();
    final id = state.shelfGroups.groups.single.id;
    expect(
      tester.widget<CheckboxListTile>(find.byKey(ValueKey('assign-$id'))).value,
      isTrue,
    );
    Navigator.of(tester.element(find.byType(CheckboxListTile))).pop();
    await tester.pumpAndSettle();
    expect(state.shelfGroups.groupsFor(book.bookUrl), isEmpty);
    await picker(tester);
    await tester.tap(find.byKey(ValueKey('assign-$id')));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.shelfGroups.groupsFor(book.bookUrl), {id});
    expect(tester.takeException(), isNull);
  });
}
