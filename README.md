# Comic Forge

[![Build APK](https://github.com/ahov520/comic-forge/actions/workflows/build.yml/badge.svg)](https://github.com/ahov520/comic-forge/actions/workflows/build.yml)

规则引擎漫画聚合阅读器。Flutter + 纯 Dart 规则引擎，兼容皮皮喵(ppcat) / legado / H-Viewer 系源规则。

> **定位与声明**：Comic Forge 是本地规则引擎工具，**不提供任何漫画内容、不搭任何后端**。
> 仓库内置的 `assets/store.json` 是社区公开仓库中的**源规则文本快照**（仅解析规则，无任何内容数据），
> 规则著作权归原作者（皮皮喵社区 / AcgLibrary），收录仅为兼容性研究。请支持正版漫画平台。

## 功能

- **规则引擎**（`engine/` 纯 Dart 包，110 项单测）：
  - legado / ppcat 风格 `rule*` 全套键名（搜索 / 发现 / 详情 / 章节 / 取图 / 评论）
  - 选择器：CSS · legado 简写（`class.x.0` / `tag.a`，支持下标与 `-` 倒序）· XPath 子集 · JSONPath 子集（单 `|` 键备选）
  - `||` 备选 · `&&` 合并 · `##正则##替换` · `{{key}}/{{page}}` 与裸 `searchKey`/`searchPage` 占位（含算术 `searchPage-1`、`{{48*(page-1)}}`）
  - `UrlNext` 自动翻页（章节列表/图片页）· 详情字段缺省回退搜索规则
  - ppcat `@` 请求语法：POST 表单体 / `@{json}@PostJson` / `@Header:` 全链路；`{{js}}`/`@js:` 静态子集（js_lite）、`@put:{}` 剥离、`{$.id}` 字面模板
- **仓库订阅双轨**：
  - Track A：自有明文 `store.json` + `meta.json`（[格式文档](docs/store-format.md)）
  - Track B：ppcat 加密 `.mh_rules` —— **无需密钥**即可提取明文分片（约半数源）；
    注入解密器后可全量（接口已留）
- **内置 493 条社区源快照**：首次启动自动导入，「源 → 恢复内置源」可随时重置；
  导入自动补回旧坏数据缺失的规则
- **导入皮皮喵备份**：支持官方 `.pbak`（gzip JSON，含分享源 ruleLink 与订阅仓库信息）
- **源健康**：搜索/发现失败自动回报，连续失败≥3 源页标红、一键禁用失效源
- **聚合搜索**：并发查启用源，可按健康状态或指定源组合过滤；筛选与「最近10词」本地保留，支持点按回填与一键清空，切换标签保留结果和草稿
- **分类探索**：按源规则加载更多、去重追加；刷新和下一页失败保留已加载列表并可重试
- **沉浸阅读器**：黑底与毛玻璃工具栏、滚动/翻页双模式（翻页支持双指缩放）、话间导航和亮度调节；失败图片可独立重试
- **阅读闭环**：阅读进度记忆（续读定位）、章节图片磁盘缓存（防盗链头跟随源）、
  预加载下一话、章节目录 SWR 离线缓存
- **书架更新**：下拉或点击刷新检查最新章节，封面显示未读角标；长按单本或通过书架菜单清除提醒，保留真实阅读进度，新话到来后再次提示
- **书架分组/标签**：菜单管理自定义分组，长按漫画可加入多个组；按组或未分组筛选，并与连载状态组合，分组与筛选本地持久化
- **批量离线下载**：详情页选择多话或选中未读章节，队列显示图片进度并支持失败补传；书架菜单和设置页可进入下载管理，完成的漫画可跨重启离线阅读
- **阅读历史**：按今天、昨天和日期查看最近阅读，支持直接续读和移除记录；未收藏漫画同样保留，旧版进度自动迁移，移除记录不会清除真实阅读进度
- **详情换源**：候选与命中数随源启停和规则编辑同步，查找失败与无匹配分别提示并可原地重试
- **H-Viewer 兼容**：`HViewerAdapter` 可转换 H-Viewer-Sites 站点规则

离线下载支持 Android 和桌面应用，文件独立保存，不受普通图片缓存淘汰影响。
下载在应用运行时继续，重新打开后恢复未完成任务；WebDAV 备份不包含离线图片。

## 下载

去 [Actions](https://github.com/ahov520/comic-forge/actions/workflows/build.yml) 选最新成功的
run，在 Artifacts 里下载 `comic-forge-release-apk`（release 签名，直接安装）。

## 本地构建

```bash
git clone https://github.com/ahov520/comic-forge.git
cd comic-forge/engine && dart test     # 引擎测试
cd ../app && flutter test              # 界面与状态回归
flutter analyze                       # 静态分析
flutter run                           # 开发运行
flutter build apk --release            # 出包
```

本机 Android 出包记录、无 KVM 模拟器启动命令及验证范围见 [Android 验证记录](docs/android-validation.md)。

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

- [x] **JS 取图规则**：引擎 `JsHook` 可注入接口 + app 接 flutter_js（QuickJS），
      浏览器/java.* 助手 shim；`$function getImgList` 取图已真网验证（腾讯漫画
      pccrack 解密实取图片）。59+ 源的复杂取图脚本在 Android 上可用；
      `{{js}}`/`@js:` 静态子集（js_lite）覆盖列表与 URL 拼接
- [ ] **store 全量解密**：定位 libapp.so 解密函数（blutter / AOT 逆向），拿到密钥后
      实现 `StoreDecryptor`，订阅官方仓库即得全量源（现为明文分片约半数）
- [x] **章节翻页**：`ruleChapterUrlNext` 支持（逐页追加 + 链接去重）
- [x] **广告拦截**：宽容格式族（urlRules 正则 / adUrl·adList 别名 / hosts 与 ||域名^ 文本）导入即过滤图片流
- [x] **WebDAV 备份/恢复**：书架、源库、进度、订阅仓库一键备份/合并恢复（MKCOL/PUT/GET + Basic 认证）
- [x] **阅读器增强**：滚动/翻页双模式、亮度调节、音量键翻页（Android 原生
      通道）、预加载下一话、话数与章内翻页位置记忆（跨重启）
- [x] **源编辑器 UI**：新建/编辑表单 + 规则试跑三级钻取（搜索→目录→取图+首图预览）
- [x] **源更新检查**：ruleVersion 变更检测 + 待应用角标 + ruleAuto 自动应用 + 启动 6h 节流自动检查
- [ ] **iOS / 桌面端**：引擎为纯 Dart，理论直接可用
- [ ] **视觉精修**：Open Design 工作流接入 CI 设计稿预览

## 设计

界面按 Open Design 的 `human-approachable` 方向（Airbnb/Duolingo 系）设计：
浅色背景 `#EFF2F4`、accent `#008668`（兼顾白字对比度）、圆角 12–18px、浅描边卡片。设计稿 [design/six-screens.html](design/six-screens.html)。

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
