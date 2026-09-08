import 'package:comic_forge/services/shelf_update_notifier.dart';
import 'package:comic_forge/state/shelf_update_notices.dart';
import 'package:comic_forge/state/shelf_updates.dart';
import 'package:engine/engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('comic-forge/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? initializeResult = true;
  bool permission = true;
  bool showOk = true;

  setUp(() {
    calls.clear();
    initializeResult = {
      'bookUrl': 'https://notify.example/book',
      'sourceId': 'src',
    };
    permission = true;
    showOk = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return initializeResult;
        case 'requestPermission':
          return permission;
        case 'show':
          return showOk;
        case 'cancelAll':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('初始化会取出冷启动打开请求，点按回调后打开', () async {
    final notifier = AndroidShelfUpdateNotifier();
    final opened = <ShelfUpdateOpenRequest>[];
    await notifier.initialize();
    expect(calls.map((call) => call.method), ['initialize']);
    final launch = notifier.takeLaunchRequest();
    expect(launch?.bookUrl, 'https://notify.example/book');
    expect(notifier.takeLaunchRequest(), isNull);

    notifier.setOnOpen(opened.add);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('opened', {
          'bookUrl': 'https://notify.example/other',
          'sourceId': 'src',
        }),
      ),
      (_) {},
    );
    expect(opened, hasLength(1));
    expect(opened.single.bookUrl, 'https://notify.example/other');
  });

  test('展示通知把书名、正文和打开参数发给原生', () async {
    final notifier = AndroidShelfUpdateNotifier();
    final book = Book(
      name: '通知漫画',
      sourceId: 'src',
      bookUrl: 'https://notify.example/book',
    );
    final badge = ShelfUpdateBadge(
      token: shelfUpdateToken('src', 'https://notify.example/c4', '第4话'),
      label: '未读 4',
      latestTitle: '第4话',
      unreadCount: 4,
    );
    expect(
      await notifier.show(ShelfUpdateNotice(book: book, badge: badge)),
      isTrue,
    );
    final shown = calls.singleWhere((call) => call.method == 'show');
    final args = shown.arguments as Map;
    expect(args['title'], '通知漫画');
    expect(args['body'], '未读 4 话 · 第4话');
    expect(args['bookUrl'], book.bookUrl);
    expect(args['sourceId'], 'src');
    expect(args['id'], shelfUpdateNoticeId(shelfUpdateNoticeKey(book)));
  });

  test('权限被拒或插件缺失时不抛错', () async {
    final notifier = AndroidShelfUpdateNotifier();
    permission = false;
    expect(await notifier.requestPermission(), isFalse);
    showOk = false;
    final book = Book(
      name: '漫画',
      bookUrl: 'https://notify.example/x',
      sourceId: 'src',
    );
    final badge = const ShelfUpdateBadge(
      token: 't',
      label: '更新',
      latestTitle: '第1话',
    );
    expect(
      await notifier.show(ShelfUpdateNotice(book: book, badge: badge)),
      isFalse,
    );

    messenger.setMockMethodCallHandler(channel, null);
    expect(await notifier.requestPermission(), isFalse);
    expect(
      await notifier.show(ShelfUpdateNotice(book: book, badge: badge)),
      isFalse,
    );
  });
}
