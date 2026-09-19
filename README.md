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
- **One event, one card:** repeated coverage is merged in the menu and integrated dashboard. Distinct original media outlets earn a capped coverage bonus; expanded cards compare attributed angles, core implications and original links. Reading an event keeps later coverage read.
- **Direct interest scores:** model upgrades, architecture changes, speed/cost gains, product popularity and your watchlist determine reading priority; evidence status is shown separately.
- **Chinese reading for scores of 7+:** existing summaries are preserved; headline-only outlines are labeled. Up to five high-score public headlines per refresh are translated using the Google service already used by the upstream project.
- **Major-vendor releases from the last 7 days:** specific model, version, feature, or architecture names; official publication dates; expired entries disappear. Generic brand mentions do not qualify.
- **Recently trending tools:** GitHub weekly growth and recent Hacker News discussion provide visible popularity evidence.
- **A full dashboard:** search, source and category filters, favorites, reading history, and dark mode.
- **Direct sources:** OpenAI, Google AI, DeepMind, Hugging Face, Xinzhiyuan and 苔藓之火 / Mossfire are fetched directly from their original RSS feeds, independently of the aggregate snapshot.

## How interest is scored

Today's news receives a numeric **interest score immediately**, without requiring a model API key, original-body verification, comparisons or evidence A/B. It uses model upgrades (weight 30), architecture changes (30), speed gains (25), cost reductions (25), product popularity (25) and relevance (15). Only applicable dimensions enter the weighted average, normalized to 0–10; ordinary product/technical progress replaces the two technical dimensions when neither applies. Missing heat is explicitly marked as a neutral 2.5/5 estimate. Efficiency claims are binned by magnitude, using the lower endpoint of ranges. New products matching model/architecture/efficiency interests earn 3/5 relevance outside the watchlist, or 5/5 for a matched watchlist event.

Scoring uses headlines, available article bodies and attributed context from the same recent official release. One of the three body-reading slots per refresh is reserved for a technical story below 7, so brief headlines do not permanently hide major gains. Jev's current launch context and recent HN popularity yield 9.2; the Chinese highlights retain the vendor's claimed scope and are distinguished from each outlet's own coverage.

Evidence remains separate: **A 充分** means sufficient direct material, **B 待验** means partially unverified, and **C 不足** means limited material. C does not suppress the score. Plain brand mentions, rumors and old-model integrations are not new model releases. Expand a score to see its dimension values and weights. Read the [current policy](macos/SCORE_POLICY.md) for the formula and examples.

## Install on a Mac

1. Download `AI-News-macOS-arm64.zip` from [Releases](https://github.com/owenmao-builder/ai-product-frontier-resource-aggregator/releases/latest).
2. Unzip it and move `AI News.app` to Applications.
3. Open the app, then click **✦** in the menu bar. Right-click the icon for settings and additional actions.

Requires **Apple Silicon and macOS 13 or later**. The downloadable build is ad-hoc signed, not Apple-notarized; building from source is also supported. Intel binaries are not provided.

The app runs the complete collector locally every 15 minutes by default, checking the configured news platforms and public RSS catalog. The downloaded app includes a checksum-verified Node.js runtime, so users do not need to install Node. Closing the dashboard keeps the menu bar app running; quitting the app stops refreshes. It does not register itself to launch at login.

## Data and assessment behavior

- **Interest-first ranking** orders today's articles by the direct interest score, then event priority and source time. Scores update with current preferences and fresh product heat; historical saved scores and evidence assessments remain intact. No verification work blocks scoring.
- News platforms (including AIbase, Info Flow, Xinzhiyuan, TechURLs, Buzzing and NewsNow) and the public RSS catalog are checked directly by the bundled collector. Live updates no longer depend on a third-party JSON snapshot being regenerated. Source details show each collection entry's check time, success/failure, last successful fetch and latest publication. Platform/feed entry counts are distinct from the author/source count in the article list.
- News times use **Beijing time (UTC+8)**. Today's Xinzhiyuan articles are checked against the publisher's WordPress API in one batch; verified publication times are cached and take priority over upstream timestamps. Only missing or unreliable publication times fall back to a collection time labeled **收录**; hover for the reason. Within the same score, known publication times sort ahead of collection-only times. Original upstream fields are preserved.
- Official RSS and product popularity signals refresh independently while the complete collection runs. HTTP errors, unparseable source pages and timeouts remain visible; failed sources retain cached articles without blocking successful sources. A successful check means content was received, not that its publisher released something new. Recent posts survive a short feed rotating them out; articles age out of the selected time window.
- AIbase publication times come from the publisher's structured `addtime` field in Beijing time. Ranking refresh times and RSS channel build times are not treated as article publication times. Existing IDs, titles, translations, assessments and reading history survive deduplication and refreshes.
- Every local collection also discovers specific model, architecture, feature and product releases from news. It verifies supported official sources, follows original links in supported news outlets, and merges confirmed releases into both product views without editing the bundled catalog. Major-vendor entries require a specific name and a verified first-release date within the last 7 **Beijing calendar days**, including today. Undated or unavailable announcements remain visible as pending leads with source links and reasons; a recent report or page modification never renews an old release. Verification has bounded requests, caches, retries and failure isolation from news collection.
- `data/products.json` supplies additional maintainer-verified descriptions (including official pages that block automatic reads). Discovery currently recognizes specific release names from Qwen, Zhipu, OpenAI, Anthropic, Google, DeepSeek, Meta, Mistral and NVIDIA; coverage is not exhaustive. It needs no model API key and does not assign news evidence scores or validate vendors' performance claims.
- Trending means GitHub's weekly Trending list with at least 500 new stars, or a matching HN story from the last 7 days with at least 100 points. Evidence older than 24 hours no longer qualifies. Popularity is not a quality score.
- Historical editorial assessments remain available. Optional model-based body analysis can add fuller Chinese highlights for at most five of today's items per pass; it never gates the direct interest score. Configure an HTTPS Chat Completions-compatible endpoint, model and key only if this enrichment is wanted.
- With automatic assessment enabled, limited public article excerpts and comparison material are sent to the configured model provider. API usage may incur charges. Keys stay in macOS Keychain; preferences, reading state, and caches stay on the Mac.
- The standalone web dashboard can read JSON snapshots, including optional event metadata. Native refresh, event grouping and coverage analysis, model assessment, and live product popularity are supplied by the Mac app.

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
