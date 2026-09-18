# AI Product Frontier Resource Aggregator

**AI 产品的前沿资源整合器** · [English](README.md) · [下载 Mac 版](https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator/releases/latest)

基于**实质增量、实际影响、解释价值、决策价值**四项标准，筛选市面上较为重要的 AI 技术与产品信息，通过 **Mac 状态栏**查看核心信息、中文重点和证据依据。

基于 [SuYxh/ai-news-aggregator](https://github.com/SuYxh/ai-news-aggregator) 扩展，提供原生 SwiftUI 菜单栏与完整 React 看板。

## 界面预览

<img src="docs/images/menu-news.png" alt="Mac 菜单栏的新闻重点与证据标签" width="420" />

<img src="docs/images/products-board.png" alt="近一周大厂上新与近期热门工具" width="960" />

以上为 2026 年 9 月 17 日的界面样例，发布条目随时间窗口变化。

## 核心功能

- **菜单栏直接看：** 单个 ✦ 图标，展开新闻、刷新、查看中文重点，点标题阅读原文。
- **按重要性筛选：** 增量 30%、影响 30%、解释 20%、决策 20%；官方大厂新模型或实质新架构发布额外 +1 分，最高 10 分。
- **证据讲清楚：** A 充分、B 待验、C 不足。数字表示阅读重要性，字母表示依据是否充分；C 保持待评估。
- **高分中文重点：** 7 分及以上展示发生了什么、相比之前有什么变化、影响与限制。
- **近一周大厂上新：** 展示具体型号、版本、新功能及官方发布日期；超过最近 7 个自然日（含今天）自动移出，不用品牌名充当新产品。
- **近期热门工具：** 显示 GitHub 周榜新增星数、HN 近 7 天讨论及来源。热度不等于质量。
- **完整看板：** 搜索、来源和类型筛选、收藏、阅读历史、暗色主题。
- **直接订阅：** 包含「苔藓之火」的 Substack 公开文章与播客文字稿。

## 安装

在 [Releases](https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator/releases/latest) 下载 `AI-News-macOS-arm64.zip`，解压后将 `AI News.app` 放到 Applications 并打开，点击状态栏的 **✦**。

支持 **Apple Silicon / macOS 13+**。下载包使用本地签名，尚未经过 Apple 公证；也可以按 [英文说明](README.md#build-and-develop) 从源码构建。

## 更新与评估

默认每 15 分钟并行直采 OpenAI、Google AI、DeepMind、Hugging Face、新智元和苔藓之火的原站 RSS，同时检查补充聚合快照、更新产品热度。原站新消息不必等待聚合平台更新；单个来源失败会保留缓存，其他来源继续刷新。关闭看板后继续运行，退出应用后停止；不自动注册开机启动。

界面分别显示“原站检查时间”和“聚合快照生成时间”，聚合快照超过一小时会标记滞后。检查成功不等于该来源有新发布，也不会把旧快照的时间改成当前时间。其他聚合平台仍随上游快照更新，可在设置中更换 HTTPS 数据目录。

新闻时间统一显示北京时间（UTC+8）。当天的新智元条目会批量核对原站接口，优先显示并缓存原站发布时间，刷新后不会被上游错误时间覆盖。仅在没有可靠发布时间时显示“收录”，悬停可查看原因；两种时间都无效时显示未知。同分时，发布时间明确的条目排在仅有收录时间的条目前。原始时间字段保留。

发布条目由维护者核对官方资料，热度及当天相关新闻自动刷新；当前并非自动发现所有新产品。GitHub 周趋势榜本周新增至少 500 星，或相关 HN 话题近 7 天至少 100 赞，才计为近期热门；热度数据超过 24 小时停止计入。

随包提供一组带日期的编辑评估。后续自动评估需要在设置中自行配置兼容 Chat Completions 的 HTTPS API 地址、模型和 Key；每轮只处理当天最多 5 条。启用后会将有限的公开原文及对照片段发给所配模型，可能产生模型费用。Key 存在 macOS 钥匙串，未评估条目保持 C 不足。

GitHub 的采集工作流默认手动运行；仓库发布后不会自动部署网站。详细规则见 [评分标准](macos/SCORE_POLICY.md)，数据与原项目说明见 [UPSTREAM.md](UPSTREAM.md)。

## 开源与致谢

采用 [MIT License](LICENSE)。感谢 [SuYxh/ai-news-aggregator](https://github.com/SuYxh/ai-news-aggregator) 提供采集器和 React 看板基础。原项目署名及扩展范围见 [NOTICE](NOTICE)。新闻原文及第三方材料的权利归相应权利人所有。
