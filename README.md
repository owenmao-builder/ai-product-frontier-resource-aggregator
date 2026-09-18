# AI Product Frontier Resource Aggregator

[简体中文](README.zh-CN.md) · [Download for Mac](https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator/releases/latest) · [Scoring rules](macos/SCORE_POLICY.md)

Curates important AI technology and product updates using **novelty, impact, explanatory value, and decision relevance**, with key insights available directly from the **macOS menu bar**.

Read concise Chinese highlights, inspect the evidence behind a score, and track specific models and product releases from the past week. Built on [SuYxh/ai-news-aggregator](https://github.com/SuYxh/ai-news-aggregator), with a native SwiftUI menu bar app and an integrated React dashboard.

## Preview

<img src="docs/images/menu-news.png" alt="Mac menu bar: important news, Chinese highlights and evidence labels" width="420" />

<img src="docs/images/products-board.png" alt="AI products with specific model names and official release dates" width="960" />

Screenshots are examples captured on September 17, 2026. The interface and editorial briefs are currently in Chinese.

## What it does

- **One menu bar icon:** open ✦ for news previews, scores, expandable highlights, and manual refresh.
- **Evidence-aware prioritization:** scores reflect substantive changes and useful information, with source links and unresolved questions.
- **Chinese highlights for scores of 7+:** see what happened, what changed, why it matters, and the limitations.
- **Major-vendor releases from the last 7 days:** specific model, version, feature, or architecture names; official publication dates; expired entries disappear. Generic brand mentions do not qualify.
- **Recently trending tools:** GitHub weekly growth and recent Hacker News discussion provide visible popularity evidence.
- **A full dashboard:** search, source and category filters, favorites, reading history, and dark mode.
- **Direct subscriptions:** includes 苔藓之火 / Mossfire's public Substack feed alongside the upstream news snapshot.

## How importance is scored

| Criterion | Weight | Question |
| --- | ---: | --- |
| Substantive novelty | 30% | What has actually changed compared with prior work? |
| Practical impact | 30% | Who is affected, and by how much? |
| Explanatory value | 20% | Does the material explain mechanisms, conditions, and trade-offs? |
| Decision relevance | 20% | Does it help someone evaluate, adopt, research, or act? |

Official major-vendor **new model or substantive architecture releases receive +1 point**, capped at 10. Brand names, buzzwords, rumors, and old models being integrated elsewhere do not receive that bonus.

Evidence is displayed separately:

| Label | Meaning |
| --- | --- |
| **A 充分** | Direct material sufficiently supports the key judgments. |
| **B 待验** | Original material exists; important benefits or implications remain unverified. |
| **C 不足** | Insufficient material; pending assessment, with no numeric score. |

An official announcement establishes a release, but does not by itself prove superiority over competitors. Read the [full policy](macos/SCORE_POLICY.md) for category-specific criteria and higher-score requirements.

## Install on a Mac

1. Download `AI-News-macOS-arm64.zip` from [Releases](https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator/releases/latest).
2. Unzip it and move `AI News.app` to Applications.
3. Open the app, then click **✦** in the menu bar. Right-click the icon for settings and additional actions.

Requires **Apple Silicon and macOS 13 or later**. The downloadable build is ad-hoc signed, not Apple-notarized; building from source is also supported. Intel binaries are not provided.

The app checks for updates every 15 minutes by default. Closing the dashboard keeps the menu bar app running; quitting the app stops refreshes. It does not register itself to launch at login.

## Data and assessment behavior

- News snapshots come from the original project's public JSON endpoint by default. Change the HTTPS data directory in settings to use your own collector. Refreshing checks the current snapshot; it does not force the upstream collector to run.
- News times use **Beijing time (UTC+8)**. Today's Xinzhiyuan articles are checked against the publisher's WordPress API in one batch; verified publication times are cached and take priority over upstream timestamps. Only missing or unreliable publication times fall back to a collection time labeled **收录**; hover for the reason. Within the same score, known publication times sort ahead of collection-only times. Original upstream fields are preserved.
- Custom RSS and product popularity signals refresh independently in the Mac app. Source failures retain cached data and display their status.
- Product release entries in `data/products.json` are **maintainer-verified**, not an automatic discovery feed. Major-vendor entries require a specific release name, an official announcement, and a verified date within the last 7 local calendar days, including today.
- Trending means GitHub's weekly Trending list with at least 500 new stars, or a matching HN story from the last 7 days with at least 100 points. Evidence older than 24 hours no longer qualifies. Popularity is not a quality score.
- The app includes a dated editorial assessment snapshot. Automatic new assessments are **optional**: configure an HTTPS Chat Completions-compatible endpoint, model, and API key in settings. Each pass handles at most five of today's items; unassessed items remain **C 不足**.
- With automatic assessment enabled, limited public article excerpts and comparison material are sent to the configured model provider. API usage may incur charges. Keys stay in macOS Keychain; preferences, reading state, and caches stay on the Mac.
- The standalone web dashboard can read JSON snapshots; native refresh, model assessment, and live product popularity are supplied by the Mac app.

## Build and develop

For the Mac app, install Xcode Command Line Tools, Node.js 22+, and Python 3. The repository uses pnpm 7.33.7 lockfiles.

```bash
git clone https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator.git
cd ai-product-frontier-resource-aggregator
npx --yes pnpm@7.33.7 install --frozen-lockfile
npx --yes pnpm@7.33.7 --dir web install --frozen-lockfile
bash macos/build.sh
open "../AI News.app"
```

Run the existing checks:

```bash
npm run typecheck
npm test
npm --prefix web run build
npm run test:macos
```

Run the web dashboard or your own collector:

```bash
npm --prefix web run dev
npm run fetch
```

The collector writes its JSON output to `data/`. Large archives and translation caches are generated locally and excluded from Git. The **Update AI News Snapshot** GitHub workflow is manual, so publishing a fork does not automatically start repeated scraping or a Pages deployment.

See [UPSTREAM.md](UPSTREAM.md) for implementation details and [CONTRIBUTING.md](CONTRIBUTING.md) for changes to sources, releases, and scoring.

## Credits and license

Based on **[SuYxh/ai-news-aggregator](https://github.com/SuYxh/ai-news-aggregator)** at commit `d8ef598d087609cff362cac6404de7d493a7a5a8`. The original project supplies the collector and React dashboard foundation. This project adds the native Mac experience, evidence-aware scoring, Chinese briefs, direct feed refresh, and release/trending product views.

Code is released under the **[MIT License](LICENSE)**. See [NOTICE](NOTICE) for upstream attribution. Linked articles, publisher logos, and third-party material retain their respective rights.
