# 源仓库订阅协议（Store Format）

Comic Forge 的源仓库订阅兼容三种入口：**GitHub/Gitee 仓库 Track A（自有明文格式，推荐）**、
**远程明文源列表 URL**，以及 **Track B（皮皮喵/ppcat 加密格式，互操作）**。

## 仓库地址解析

接受以下输入形式（与 ppcat 的正则语义一致）：

```
github.com/<user>/<repo>
https://github.com/<user>/<repo>
https://gitee.com/<user>/<repo>
<user>/<repo>            # 简写，默认 github
https://example.com/store.json   # 远程明文源列表
```

直接源列表 URL 必须是 `http(s)`、无用户名密码，且主机不是 GitHub/Gitee 仓库根。
客户端只 GET 该地址，按明文 `store.json` / 源数组 / 单条源对象解析，**不会**尝试解密 `.mh_rules`。

## 拉取顺序

对每个文件依次尝试候选 URL，首个成功者生效：

1. `https://raw.githubusercontent.com/<user>/<repo>/master/<file>`
2. `https://cdn.jsdelivr.net/gh/<user>/<repo>@master/<file>`
3. `https://raw.githubusercontent.com/<user>/<repo>/main/<file>`
4. `https://cdn.jsdelivr.net/gh/<user>/<repo>@main/<file>`
5. （gitee 源）`https://gitee.com/<user>/<repo>/raw/master/<file>` / `raw/main/<file>`

## Track A：明文仓库（自有格式）

```
<repo>/
├── meta.json      # 可选；元信息
└── store.json     # 源列表（必须）
```

**meta.json**（键名与 ppcat 对齐，便于迁移）：

```json
{
  "ruleId": "0",
  "ruleVersion": 20260906,
  "ruleContent": "",
  "ruleAuto": true
}
```

**store.json**：顶层数组，或 `{"sources":[...]}` / `{"data":[...]}`。

源条目（嵌套写法，推荐）：

```json
{
  "id": "example-manga",
  "name": "示例漫画",
  "group": "示例分组",
  "icon": "https://.../icon.png",
  "url": "https://m.example.com",
  "enabled": true,
  "weight": 0,
  "headers": { "Referer": "https://img.example.com" },
  "rules": {
    "searchUrl": "https://m.example.com/search?q={{key}}&page={{page}}",
    "searchList": ".comic-list .item",
    "searchName": ".title@text",
    "searchAuthor": ".author@text",
    "searchCoverUrl": "img@src",
    "searchBookUrl": "a.title@href",
    "searchUrlNext": "a.next@href",
    "exploreUrl": "连载::https://m.example.com/list/1?page={{page}}\n完结::https://m.example.com/list/2?page={{page}}",
    "findList": ".comic-list .item",
    "findName": ".title@text",
    "findCoverUrl": "img@src",
    "findBookUrl": "a.title@href",
    "bookName": ".detail h1@text",
    "bookAuthor": ".detail .author@text",
    "bookCoverUrl": ".detail img@src",
    "bookIntroduce": ".intro@text",
    "chapterList": ".chapter-list a",
    "chapterName": "@text",
    "chapterUrl": "@href",
    "contentUrl": ".reader img@src",
    "contentUrlNext": "a.next-page@href"
  }
}
```

也兼容 ppcat 平铺键写法（`ruleSearchUrl`/`searchUrl`/`ruleSearchList`/`ruleSearchName`/…/`ruleContentUrlNext`），
导入时自动归一（见 `ComicSource.fromPpcatFlat`，键名映射表见
`engine/lib/src/models/comic_source.dart` 的 `RuleSet.ppcatFlatKeys`）。平铺条目的 `headers` 也会并入源。

## 规则语法（v1 支持子集）

| 语法 | 含义 | 示例 |
|---|---|---|
| `@css:sel@attr` | 显式 CSS | `@css:.title@text` |
| `sel@attr` | CSS + 提取 | `.title@text`、`img@src`、`a@href` |
| `id.x` / `class.x` / `tag.x` | legado 简写 | `id.main@tag.p@text` |
| `//x[@a='b']/@attr` | XPath 子集 | `//div[@class="item"]/a/@href` |
| `$.a.b[0].c` / `$.a[*].b` | JSONPath 子集 | `$.data.list[*].name` |
| `A \|\| B` | 备选 | `.a@text \|\| .b@text` |
| `A && B` | 合并 | `.a@text && .b@text` |
| `##正则##替换` | 正则后处理（$1..$9） | `.t@text##第(\d+)话##$1` |
| `{{key}}` `{{page}}` | URL 模板 | `?q={{key}}&p={{page}}` |

提取函数：`text` `textNodes` `html` `all` `href` `src` `content` `alt`
`title` `value` `attr:<name>`。

## Track B：ppcat 加密仓库（互操作）

布局（逆向确认，详见侦查案卷）：

- `meta`：明文 JSON（键同上）
- `store`：加密 ZIP，entry 名 `.mh_rules`，deflate。中央目录明文（可读出
  csize/usize/crc32），`[0, cdOff)` 为加密区（LFH+压缩数据），流式密码、
  逐文件密钥流不同。

解密器通过 `RepoClient(storeDecryptor: ...)` 注入；算法待 Phase 0 取证
（真机导出备份或 ARM 原生环境动态分析）。结构解析
（`PpcatStoreInspector`）已实现并有真实样本回归测试。

## 皮皮喵「本地备份」导入

待 Phase 0 拿到备份样本后实现（`PipimiaoBackupImporter`）。

## 广告拦截规则 JSON

设置页可导入；作用于阅读器图片流（引擎 `AdBlockRules`，见
`engine/lib/src/models/ad_block.dart`）。解析器按宽容设计，兼容生态内
多种实际流通格式（ppcat 原版为闭源 APK 内部格式、无公开文档，拿到
真实样本后可在解析器内零成本映射）：

```json
{
  "enabled": true,
  "urlRules":  ["(?i)adserver", "\\.abc\\.net/img/"],
  "nameRules": ["预告|插页"]
}
```

- JSON 键：`urlRules`（别名 `adUrl` / `adList` / `urls` / `blockUrls` /
  `urlRule`）→ URL 正则；`nameRules`（别名 `adName` / `nameList`）→ 名称正则。
- 顶层为纯字符串数组时整体视为 URL 规则（ppcat 风格 URL 正则列表）。
- **纯文本**（hosts / adblock 风格 txt）也接受：`#`/`!` 注释与空行跳过；
  `0.0.0.0 x.com` / `127.0.0.1 x.com` / `||x.com^` 均提取域名并整域
  （含子域）拦截；`@@` 白名单行跳过；其余行视为一条 URL 正则。
- 正则命中即过滤；普通域名即子串匹配，大小写不敏感。
