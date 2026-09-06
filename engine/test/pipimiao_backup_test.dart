import 'package:engine/engine.dart';
import 'package:test/test.dart';

/// 用真实备份样本回归（用户提供，2026-09-06）。
void main() {
  late PipimiaoBackup backup;
  late SharedRule rule;

  setUpAll(() {
    backup = PipimiaoBackup.parseFile('test/fixtures/pipimiao_backup.pbak');
    rule = backup.sharedRules.first;
  });

  test('备份元信息', () {
    expect(backup.version, 260201);
    expect(backup.timeMs, greaterThan(0));
  });

  test('订阅仓库信息（gitRuleMap）', () {
    expect(backup.storeSubscriptions, isNotEmpty);
    expect(backup.storeSubscriptions.first.url, 'https://github.com/AcgLibrary/ppcat_store');
    expect(backup.storeSubscriptions.first.auto, isTrue);
  });

  test('分享源 ruleLink 提取', () {
    expect(backup.sharedRules.length, 1);
    expect(rule.name, contains('皮皮喵来源教程'));
    expect(rule.storeBytes.length, 390);
  });

  test('ruleLink 内嵌 .mh_rules 结构', () {
    final s = rule.inspect()!;
    expect(s.entry.name, '.mh_rules');
    expect(s.entry.method, 8);
    expect(s.entry.crc32, 0xe44cfc5b);
  });

  test('尾部明文分片解出 legado 格式 JSON 前缀', () {
    final partial = rule.partialRulesJson();
    expect(partial, isNotNull);
    expect(partial!, contains('"bookSourceName":"皮皮喵来源教程（教程）"'));
    expect(partial, contains('ruleFindUrl'));
  });

  test('extractCompleteSources 对截断条目容错', () {
    // 教程源的明文分片在 181B 处截断（无完整对象），应返回空而非抛异常
    final out = backup.extractCompleteSources();
    expect(out, isEmpty);
  });
}
