# 源仓库订阅协议（Store Format）

Comic Forge 的源仓库订阅兼容两种格式：**Track A（自有明文格式，推荐）** 与
**Track B（皮皮喵/ppcat 加密格式，互操作）**。

## 仓库地址解析

接受以下输入形式（与 ppcat 的正则语义一致）：

```
github.com/<user>/<repo>
https://github.com/<user>/<repo>
https://gitee.com/<user>/<repo>
<user>/<repo>            # 简写，默认 github
```

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

也兼容 ppcat 平铺键写法（`ruleSearchList`/`ruleSearchName`/…/`ruleContentUrlNext`），
导入时自动归一（见 `ComicSource.fromPpcatFlat`，键名映射表见
`lib/src/models/comic_source.dart` 的 `RuleSet.ppcatFlatKeys`）。

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
