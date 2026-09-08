/// Comic Forge Engine — 纯 Dart 漫画源规则引擎。
///
/// 兼容 legado / 皮皮喵(ppcat) 风格的 rule* 规则键名，支持订阅 GitHub/Gitee
/// 形式的明文源仓库（Track A）、远程明文源列表 URL，以及 ppcat 加密
/// `.mh_rules` 仓库（Track B，解码器由外部注入）。
library;

export 'src/models/comic_source.dart';
export 'src/models/content.dart';
export 'src/models/ad_block.dart';
export 'src/analyzer/rule_analyzer.dart';
export 'src/analyzer/rule_evaluator.dart';
export 'src/adapter/hviewer_adapter.dart';
export 'src/store/repo_client.dart';
export 'src/store/ppcat_store.dart';
export 'src/store/tolerant_inflate.dart';
export 'src/store/pipimiao_backup.dart';
export 'src/store/webdav.dart';
export 'src/net/domain_blocklist.dart';
export 'src/net/fetcher.dart';
export 'src/net/request.dart';
export 'src/source_runtime.dart';
