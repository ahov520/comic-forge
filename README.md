# Comic Forge

规则引擎漫画聚合阅读器——参照皮皮喵(ppcat)机制逆向互操作实现，**本地工具，不内置任何源，不提供任何内容**。

```
comic-forge/
├── engine/    纯 Dart 规则引擎包（零 Flutter 依赖，41 个单测全绿）
├── app/       Flutter 客户端（Material 3，六屏 + 阅读器）
├── design/    Open Design 设计稿（human-approachable 方向六屏）
└── docs/      仓库订阅协议文档
```

## 功能（v0.1）

- **规则引擎**：legado/ppcat 风格 `rule*` 全套键名；CSS / legado 简写 / XPath 子集 /
  JSONPath 子集选择器；`||` 备选、`&&` 合并、`##正则##替换` 后处理、`{{key}}/{{page}}` URL 模板、
  `UrlNext` 自动翻页。
- **仓库订阅**：输入 `github.com/user/repo` / `gitee.com/user/repo` 即可订阅源仓库。
  - Track A（明文 `store.json` + `meta.json`）开箱即用，格式见 `docs/store-format.md`；
  - Track B（ppcat 加密 `.mh_rules`）协议与结构解析已实现，解密器留有注入接口（见下）。
- **H-Viewer 规则兼容**：`HViewerAdapter` 可将 H-Viewer-Sites 的站点规则 JSON 转换为
  本引擎源（真实样例已测试）。
- **App 六屏**：书架（封面网格+收藏）/ 探索（源+分类）/ 聚合搜索 / 源管理（订阅+启停）/
  设置 / 沉浸阅读器（图片流+工具栏）。
- 聚合搜索并发查所有启用源；书架、源库本地持久化。

## 运行

```bash
cd engine && dart test          # 引擎测试
cd app && flutter run           # 运行 App
```

首次使用：进「源」页 → 右上角 ＋ → 输入一个明文源仓库地址订阅。

## 与皮皮喵的互操作状态

| 能力 | 状态 |
|---|---|
| 仓库导入协议（meta + store 抓取、GitHub/Gitee/jsdelivr 多候选） | ✅ 已实现并实测 |
| 规则 schema（60+ `rule*` 键） | ✅ 已实现 |
| ppcat 加密 store（`.mh_rules`）结构解析 | ✅ 已实现（真实样本回归测试） |
| ppcat 加密 store 解密 | ⏳ 待密钥（见下） |
| ppcat「本地备份」导入 | ⏳ 待样本 |

**关于解密密钥**：`.mh_rules` 是流式加密、逐文件密钥流不同，静态破解不可行。
计划的取证路径：用户真机导出皮皮喵「本地备份」文件（零破解），或 ARM 原生环境动态分析。
拿到后实现 `StoreDecryptor` 并注入 `RepoClient(storeDecryptor: ...)` 即可无缝订阅
`AcgLibrary/ppcat_store` 等现有社区仓库。**刻意不做**：绕过皮皮喵授权/正版检测（那是
对软件保护措施的破解，与格式互操作是两回事）。

## 设计

界面按 Open Design 的 `human-approachable` 方向（Airbnb/Duolingo 系统）设计：
背景 `oklch(98% 0.004 240)`、accent `oklch(56% 0.12 170)`（#169876）、圆角 12–18px、
浅描边卡片。设计稿 `design/six-screens.html` 已注册进 Open Design 项目
`Comic Forge`（本地 daemon 端口 4871，`od artifacts` 可见）。

## 边界

- 不内置、不分发任何漫画源或内容；
- 不做加固/授权绕过；
- 姿态与 legado 一致：本地规则引擎 + 用户自备源。
