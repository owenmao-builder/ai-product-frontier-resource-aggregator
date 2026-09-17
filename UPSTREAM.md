# AI Product Frontier Resource Aggregator · 项目来源与实现

公开仓库：[owenmao-builder/ai-product-frontier-resource-aggregator](https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator)。英文介绍与安装方式见 [README.md](README.md)，中文介绍见 [README.zh-CN.md](README.zh-CN.md)。

直接基于 [SuYxh/ai-news-aggregator](https://github.com/SuYxh/ai-news-aggregator) 修改，保留原 React 看板、采集器、来源过滤、收藏、阅读历史、主题和工作流。上游在 package.json 与 README 中声明 MIT 许可。基础提交为 `d8ef598d087609cff362cac6404de7d493a7a5a8`。

新增 `macos/` 原生菜单栏、预览、刷新、缓存及重要性评估；网页接入原生数据、类型筛选、评分解释与排序。移除了桌面版不需要的百度统计脚本。

## 使用

打开同级 `AI News.app`，点击菜单栏单个闪光符号（✦）。新闻右侧显示 0–10 分，以及「A 充分 / B 待验 / C 不足」。C 不足显示“—”并保持待评估；悬停或展开评分依据可读完整解释。7 分及以上显示中文标题，点“展开重点”阅读中文摘要；再点“评分依据”查看维度、理由、变化、来源和待确认事项；点标题打开原文。

菜单默认显示今天，可筛选全部、7 分以上、待评估和未读消息；完整看板增加新闻类型筛选。默认按重要度排列，可切换最新优先。右键图标打开设置或退出。默认每 15 分钟检查，也可立即拉取。

菜单栏和完整看板可切换「新闻 / AI 产品」。「AI 产品」默认展示「大厂上新 · 7 天」：按官方首发日期筛选最近 7 个自然日（含本机今天），只列具体模型、版本、新功能或新架构；新模型优先。卡片显示官方发布日期、此次新增能力、使用方式和发布公告。超过时限、日期未核实或只有品牌名的条目不展示，抓取、重新报道和资料核对不会重置发布日期。

2026-09-17 核验的当前样例是 Gemini 3.8 Live、Gemini 3.8 Live Extended Thinking（9 月 15 日），以及 Claude Docs、Claude Slides（9 月 16 日）。GPT-6 Astra 已按具体模型建档，但官方 RSS 首发日期为 9 月 3 日，自动排除在本周栏目外；9 月 9 日的企业介绍文章不会当作模型重新发布。

发布资料维护在 `data/products.json`，不是自动发现的全网目录。可搜索型号、公司与用途，展开中文重点、官网及当天已有的相关新闻。每次刷新自动更新 GitHub 周榜与 Hacker News 近 7 天讨论：周榜新增至少 500 星或单个相关话题至少 100 赞才进入「近期热门」。大厂条目在热门与全部列表中也须满足 7 天发布期限；独立工具可以较早发布、最近走红。超过 24 小时的热度停止计入；抓取失败保留缓存并提示。热度不等于质量或新闻重要性分数。网页独立运行时展示有效发布资料，实时热度由 Mac 应用提供。

## 数据与评分

默认读取上游 GitHub Pages 公开 JSON，上游约每两小时采集一次。本机更频繁检查不会触发作者提前采集。可改成自己部署的同结构 HTTPS 数据目录。退出应用后停止轮询；关闭看板则继续运行。

自选订阅已加入 [苔藓之火](https://mossfirepodcast.substack.com/) 的公开文章与播客文字稿（[官方 RSS](https://mossfirepodcast.substack.com/feed)）。Mac 应用每次刷新会独立拉取，与上游 JSON 合并、去重；抓取失败保留缓存，并在完整看板的「信息源 → 我的信息源」显示状态和最近发布的文章。按原始发布日期进入 24 小时 / 7 天窗口，无更新时仍显示已配置来源，不把旧文章当作今天的新闻。该作者属于独立评论来源，品牌提及不会触发官方发布加分。

订阅配置统一在 `feeds/direct-feeds.json`；原项目 Node 采集器也会加载，未提供私有 OPML 时仍会采集这些自选订阅。修改配置后重新构建应用即可生效。

[评分标准 v2.1](macos/SCORE_POLICY.md)：实质增量 30%、实际影响 30%、解释价值 20%、决策价值 20%。按类型解释维度；Agent/Harness 等词只作对应新闻的关注点，不加分。官方大厂新模型或实质新架构发布单独加 1 分；证据 A/B/C 单独展示。旧标题关键词分全部失效。

沿用初版 23 篇原文的编辑评估，本轮只新增核查 1 条今天收录的新模型消息，提供 8 条今日中文重点，存于 `macos/assessments-v2.json`。记录以内容指纹匹配；其余消息先暂分类型并标为待评估。只读摘要的论文会注明；没有独立验证的性能声明不会被当作已证明事实。

如需后续自动评估，在设置中启用“自动读取正文并使用 AI 评估”，填写兼容 Chat Completions 的 HTTPS API 地址、模型和 Key。Key 存在 macOS 钥匙串，不进入网页、源码或日志。每轮只处理本机当天最多 5 条消息，读取公开正文及可用的历史对照并向所配模型发送有限片段，可能收费。程序计算分数并检查版本、引用、维度、发布依据与中文重点。不足时保持待评估；待评估结果可在 6 小时后重试。没有配置外部 API 时，这次附带结果仍可使用。

## 构建与验证

需要 Apple Silicon Mac、macOS 13+、Xcode Command Line Tools 与 Node.js：

```bash
bash macos/build.sh
```

脚本复用原项目 pnpm 7 锁文件。产物为同级 `AI News.app`，仅本地签名，未 Apple 公证。

```bash
mkdir -p .build
xcrun swiftc -swift-version 5 macos/Models.swift macos/ArticleEvidence.swift macos/Scoring.swift macos/DirectFeeds.swift macos/Products.swift macos/NewsStore.swift macos/DirectFeedTests.swift macos/ProductTests.swift macos/Tests.swift -framework Cocoa -framework Security -framework CryptoKit -o .build/scoring-tests
.build/scoring-tests
```

测试覆盖无关键词加分、按类型判断、总分计算、证据门槛、旧分失效、引文与来源校验、正文提取和去重。可编译 `macos/Relabel.swift` 替换测试入口，导出重标记 JSON：`relabel export 原数据目录 macos/assessments-v2.json 输出目录`。

应用不注册开机启动。缓存位于系统 Application Support 的 `AINewsMenu` 目录，偏好设置使用 `local.owen.AINewsMenu` 域。
