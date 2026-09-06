# Comic Forge

[![Build APK](https://github.com/ahov520/comic-forge/actions/workflows/build.yml/badge.svg)](https://github.com/ahov520/comic-forge/actions/workflows/build.yml)

规则引擎漫画聚合阅读器。Flutter + 纯 Dart 规则引擎，兼容皮皮喵(ppcat) / legado / H-Viewer 系源规则。

> **定位与声明**：Comic Forge 是本地规则引擎工具，**不提供任何漫画内容、不搭任何后端**。
> 仓库内置的 `assets/store.json` 是社区公开仓库中的**源规则文本快照**（仅解析规则，无任何内容数据），
> 规则著作权归原作者（皮皮喵社区 / AcgLibrary），收录仅为兼容性研究。请支持正版漫画平台。

## 功能

- **规则引擎**（`engine/` 纯 Dart 包，50+ 单测）：
  - legado / ppcat 风格 `rule*` 全套键名（搜索 / 发现 / 详情 / 章节 / 取图 / 评论）
  - 选择器：CSS · legado 简写（`class.x.0` / `tag.a`，支持下标与 `-` 倒序）· XPath 子集 · JSONPath 子集
  - `||` 备选 · `&&` 合并 · `##正则##替换` · `{{key}}/{{page}}` 与裸 `searchKey`/`searchPage` 占位
  - `UrlNext` 自动翻页 · 详情字段缺省回退搜索规则
- **仓库订阅双轨**：
  - Track A：自有明文 `store.json` + `meta.json`（[格式文档](docs/store-format.md)）
  - Track B：ppcat 加密 `.mh_rules` —— **无需密钥**即可提取明文分片（约半数源）；
    注入解密器后可全量（接口已留）
- **内置 493 条社区源快照**：首次启动自动导入，「源 → 恢复内置源」可随时重置
- **导入皮皮喵备份**：支持官方 `.pbak`（gzip JSON，含分享源 ruleLink 与订阅仓库信息）
- **聚合搜索**：并发查所有启用源
- **沉浸阅读器**：图片流连续滚动 + 工具栏
- **H-Viewer 兼容**：`HViewerAdapter` 可转换 H-Viewer-Sites 站点规则

## 下载

去 [Actions](https://github.com/ahov520/comic-forge/actions/workflows/build.yml) 选最新成功的
run，在 Artifacts 里下载 `comic-forge-release-apk`（release 签名，直接安装）。

## 本地构建

```bash
git clone https://github.com/ahov520/comic-forge.git
cd comic-forge/engine && dart test     # 引擎测试
cd ../app && flutter run               # 开发运行
flutter build apk --release            # 出包
```

## 与皮皮喵的互操作状态

| 能力 | 状态 |
|---|---|
| 仓库导入协议（meta + store，GitHub/Gitee/jsdelivr 多候选） | ✅ 已实现并实测 |
| 规则 schema（60+ `rule*` 键） | ✅ 已实现（真实样本校准） |
| 加密 `.mh_rules` 明文分片提取（无需密钥） | ✅ 已实现（真实样本逐字节回归） |
| 加密 `.mh_rules` 全量解密 | ⏳ 密钥待取证（`StoreDecryptor` 接口已留） |
| 皮皮喵 `.pbak` 备份导入 | ✅ 已实现（真实样本回归） |
| H-Viewer 站点规则转换 | ✅ 已实现 |

## Roadmap / 后续规划

- [ ] **JS 取图规则**：59/194 源的 `$function getImgList(){...}` 需要 JS 执行环境
      （flutter_js / WebView 桥接，接收 `html` 变量返回图片列表）
- [ ] **store 全量解密**：定位 libapp.so 解密函数（blutter / AOT 逆向），拿到密钥后
      实现 `StoreDecryptor`，订阅官方仓库即得全量源（现为明文分片约半数）
- [ ] **章节翻页**：`ruleChapterUrlNext` 支持（长漫画分页源）
- [ ] **广告拦截**：兼容皮皮喵广告拦截规则 JSON 格式
- [ ] **WebDAV 备份/恢复**：书架、源库、阅读进度上云
- [ ] **阅读器增强**：音量键翻页、亮度手势、预加载下一话、阅读进度记忆
- [ ] **源编辑器 UI**：App 内创建/调试源（引擎已支持，缺界面）
- [ ] **源更新检查**：订阅仓库 ruleVersion 变更提醒与一键更新
- [ ] **iOS / 桌面端**：引擎为纯 Dart，理论直接可用
- [ ] **视觉精修**：Open Design 工作流接入 CI 设计稿预览

## 设计

界面按 Open Design 的 `human-approachable` 方向（Airbnb/Duolingo 系）设计：
accent `#169876`、圆角 12–18px、浅描边卡片。设计稿 [design/six-screens.html](design/six-screens.html)。

## 目录结构

```
comic-forge/
├── engine/    纯 Dart 规则引擎包（零 Flutter 依赖，可独立测试）
├── app/       Flutter 客户端（Material 3，内置源快照在 app/assets/）
├── store-snapshot/  493 条社区源快照（Track A 仓库格式，可直接被订阅）
├── design/    Open Design 设计稿
└── docs/      源仓库订阅协议文档
```

## License

MIT。源规则快照的著作权归皮皮喵社区原作者所有，如有侵权请联系移除。
