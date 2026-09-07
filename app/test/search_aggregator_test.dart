import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:engine/engine.dart';
import 'package:comic_forge/state/search_aggregator.dart';

Book _b(String name, {String author = '', String bookUrl = ''}) =>
    Book(name: name, author: author, bookUrl: bookUrl);

void main() {
  group('SearchAggregator', () {
    test('去重：同名同作者保留权重高的源，统计被合并条数', () {
      final agg = SearchAggregator.aggregate({
        'srcA': [_b('一人之下', author: '米二', bookUrl: 'a/1')],
        'srcB': [_b('一人之下', author: '米二', bookUrl: 'b/1')],
        'srcC': [_b('镖人', author: '许先哲', bookUrl: 'c/1')],
      }, (id) => id == 'srcB' ? 10 : 0);

      expect(agg.books, hasLength(2));
      expect(agg.books.first.bookUrl, 'b/1', reason: '同名去重应保留权重高的 srcB');
      expect(agg.duplicatesRemoved, 1);
      expect(agg.sourcesHit, 3);
      expect(agg.sourceIds.first, 'srcB');
    });

    test('按源权重排序：高权重源的结果排前', () {
      final agg = SearchAggregator.aggregate({
        'low': [_b('低权重书')],
        'high': [_b('高权重书')],
      }, (id) => id == 'high' ? 9 : 1);
      expect(agg.books.first.name, '高权重书');
    });

    test('权重相同按到达顺序', () {
      final agg = SearchAggregator.aggregate({
        'first': [_b('甲')],
        'second': [_b('乙')],
      }, (_) => 5);
      expect(agg.books.map((b) => b.name).toList(), ['甲', '乙']);
    });

    test('名称空白与大小写不影响去重键；不同作者不去重', () {
      final agg = SearchAggregator.aggregate({
        'a': [_b(' 海贼王 ', author: '尾田')],
        'b': [_b('海贼王', author: '尾田荣一郎')],
      }, (_) => 0);
      expect(agg.books, hasLength(2), reason: '作者不同不合并');
      expect(agg.duplicatesRemoved, 0);
    });

    test('空结果源不计命中；books 与 sourceIds 一一对应', () {
      final agg = SearchAggregator.aggregate({
        'empty': <Book>[],
        'hit': [_b('书1'), _b('书2')],
      }, (_) => 0);
      expect(agg.sourcesHit, 1);
      expect(agg.books, hasLength(2));
      expect(agg.sourceIds, ['hit', 'hit']);
    });
  });

  group('searchAggregateStatus', () {
    test('搜索中尚无结果只报正在聚合的源数', () {
      expect(
        searchAggregateStatus(
          sourceCount: 3,
          successCount: 0,
          timeoutCount: 0,
          errorCount: 0,
          searching: true,
        ),
        '正在聚合 3 个源',
      );
    });

    test('对齐设计稿：成功与超时并列', () {
      expect(
        searchAggregateStatus(
          sourceCount: 3,
          successCount: 2,
          timeoutCount: 1,
          errorCount: 0,
          searching: true,
        ),
        '正在聚合 3 个源 · 2 成功 1 超时',
      );
    });

    test('结束后改用已聚合，失败单独计数', () {
      expect(
        searchAggregateStatus(
          sourceCount: 3,
          successCount: 1,
          timeoutCount: 1,
          errorCount: 1,
          searching: false,
        ),
        '已聚合 3 个源 · 1 成功 1 超时 1 失败',
      );
    });
  });

  group('searchFailureTip / classifySearchFailure', () {
    test('超时与失败分别点名', () {
      expect(
        searchFailureTip(const [
          SearchSourceFailure(name: '咕咕漫画', kind: SearchSourceFailKind.timeout),
          SearchSourceFailure(name: '备用源', kind: SearchSourceFailKind.error),
          SearchSourceFailure(name: '拾荒漫画', kind: SearchSourceFailKind.timeout),
        ]),
        '2 个源超时：咕咕漫画、拾荒漫画 · 1 个源失败：备用源',
      );
    });

    test('无失败返回 null', () {
      expect(searchFailureTip(const []), isNull);
    });

    test('TimeoutException 与 timeout/超时文案归为超时', () {
      expect(
        classifySearchFailure(TimeoutException('source')),
        SearchSourceFailKind.timeout,
      );
      expect(
        classifySearchFailure(Exception('Fetch timeout')),
        SearchSourceFailKind.timeout,
      );
      expect(classifySearchFailure(Exception('连接超时')), SearchSourceFailKind.timeout);
      expect(classifySearchFailure(Exception('offline')), SearchSourceFailKind.error);
    });
  });
}
