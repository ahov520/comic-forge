# Comic Forge：同类开源漫画软件调研与演进路线

> 调研时间：2026-11-04。以公开 GitHub 项目 README / 功能列表为主；这是**主要代表项目的抽样比较**，不是宣称穷尽 GitHub 所有漫画阅读项目。

## 调研项目与可借鉴部分

| 项目 | 地址 | 值得研究 | Comic Forge 当前情况 |
|---|---|---|---|
| Mihon | https://github.com/mihonapp/mihon | 可配置阅读器、追漫平台同步、定期更新 | 阅读模式、更新与备份已覆盖；追漫平台未接入 |
| Kotatsu-Redo | https://github.com/Kotatsu-Redo/Kotatsu-Redo | 全源排序、隐私阅读、电纸书模式、CBZ、推荐与同步 | 换源与健康已有；无痕阅读本 PR 新增 |
| Mangayomi | https://github.com/kodjodevf/mangayomi | Flutter 多平台结构、Dart/JS 扩展生态、跟踪平台 | 同为 Flutter；本项目是规则 JSON 引擎，不能直接装它的扩展 |
| Suwayomi-Server | https://github.com/Suwayomi/Suwayomi-Server | 独立服务端 API、跨设备同步、扩展运行 | 目前本地优先 + WebDAV 备份；暂不引入服务端复杂度 |
| OpenComic | https://github.com/ollm/OpenComic | 本地 CBZ/ZIP、双页、色彩调整、OPDS、局域网资源 | 当前离线下载为应用内文件；本地归档导入待做 |
| Aidoku | https://github.com/Aidoku/Aidoku | WASM 沙箱插件、CBZ、本地/服务器阅读与 OCR | 规则 JS 兼容不等于安全插件沙箱；需要隔离模型 |
| Legado（阅读） | https://github.com/gedoor/legado | 自定义源规则、替换净化、源导入兼容 | 已支持部分 Legado 规则；复杂 JS / 动态页面仍有差距 |
| Keiyoushi extensions | https://github.com/keiyoushi/extensions | 扩展仓库索引、版本与信任管理 | 不应把 APK 扩展误当 JSON 规则导入 |
| HakuNeko | https://github.com/manga-download/hakuneko | 批量下载、站点连接器维护 | 已有下载队列；断点与错误分类可继续优化 |
| Tachidesk-Sorayomi | https://github.com/Suwayomi/Tachidesk-Sorayomi | Flutter 桌面/移动客户端 + 服务端连接 | 未来可探索可选的私有服务端 |
| Kototoro | https://github.com/Kototoro-app/Kototoro | Android 阅读器分支的互动与阅读体验 | 关注阅读 UI，但不复制其实现 |
| OpenFic（非漫画主类） | https://github.com/ahov520/OpenFic | 用户自己的阅读/内容项目，参考工作流与复用 | 可在后续单独评估模块复用 |

## 不应重复做的功能

当前代码已有：源健康体检（含自动探测）、失效源筛选、并发聚合搜索、换源扫描、阅读统计、阅读历史、章节书签、分组、连续滚动/翻页、下一章预取、离线下载、WebDAV/本地备份、亮度与音量键阅读、源规则试跑。新需求优先弥补缺口。

## 已落地：当前功能 PR

1. **源列表即时搜索**：按源名、分组、站点/ID 检索，与现有健康筛选组合，无远程请求。
2. **无痕阅读**：设置和阅读器内开关；不开启新搜索历史、进度、阅读历史、阅读统计与章内位置记录。仅作用于新记录，不自动删除已有记录、缓存或用户主动书签。
3. **隐私友好的诊断摘要**：源页菜单复制源数量、可用搜索源数量及失败分类；不包含完整源 URL、请求头与 Cookie。

## 后续迭代建议（按优先级）

| 优先级 | 功能 | 关键实施点和验收 |
|---|---|---|
| P0 | 真机源兼容测试向导 | 搜索→详情→目录→首图分层报告，区分 403/429/超时/规则无命中；单源可重复复现 |
| P0 | 本地 CBZ/ZIP 漫画导入 | 只解析图片；防 Zip Slip、限制解压文件数与大小、拒绝路径穿越与异常压缩比；本地阅读进度可持久化 |
| P1 | 阅读舒适度与无障碍 | Webtoon 连续模式、适配电纸书的高对比低动画预设、双页与阅读方向；做屏幕尺寸/手势测试 |
| P1 | 下载任务可靠性 | 失败分类、可取消的并发限速、断点/重试、每章校验与离线文件完整性检查 |
| P1 | 本地源质量排序 | 仅基于用户本机成功率、延迟和最近活跃时间；手动固定喜欢的源，不上传浏览记录 |
| P2 | 导入/导出 CBZ | 允许把拥有使用权的离线内容导成标准归档；避免扩展格式伪兼容 |
| P2 | AniList / Bangumi 等进度同步 | OAuth 授权、显式隐私同意、离线队列、冲突合并，默认关闭 |
| P2 | 多端同步 | 优先完善 WebDAV 增量冲突策略，再考虑可选私有 API 服务；端到端数据保密 |
| P3 | 插件生态 | 先定义受限 JS/WASM 插件协议、权限与签名校验，再评估 Mihon APK 桥接；不允许未受信任代码无提示执行 |
| P3 | OCR 辅助与图像增强 | 先做离线 OCR 文本选取/查词，不未经同意上传漫画图片到模型服务 |

## 技术与合规边界

- 优先借鉴**功能设计和公开协议**，而不是直接粘贴其他项目代码。尤其 GPL 家族和含 CLA 的项目，复用前要评估许可兼容。
- 不预装未经授权的漫画内容；来源规则由用户自行选择，避免把未经许可的资源库写进客户端。
- 源失败不能简单等于源永久不可用：请求超时、地域限制、账号验证、站点升级和解析失败应该分开报告。
- 优先完整自动化测试与可安装 APK 真机实测，避免为了功能数量牺牲稳定性。
