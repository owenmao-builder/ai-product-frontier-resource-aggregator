#!/usr/bin/env bash
set -euo pipefail
APP_SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
APP_OUTPUT="${1:-$APP_SOURCE/../AI News.app}"
cd "$APP_SOURCE/web"
if [ ! -d node_modules ]; then npx --yes pnpm@7.33.7 install --frozen-lockfile; fi
MAC_APP=1 npm run build
cd "$APP_SOURCE"
if [ ! -d node_modules/esbuild ]; then npx --yes pnpm@7.33.7 install --frozen-lockfile; fi
mkdir -p "$APP_OUTPUT/Contents/MacOS" "$APP_OUTPUT/Contents/Resources/web" "$APP_OUTPUT/Contents/Resources/seed"
node macos/bundle-collector.mjs "$APP_OUTPUT"
cp macos/Info.plist "$APP_OUTPUT/Contents/Info.plist"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP_OUTPUT/Contents/Resources/"
cp feeds/direct-feeds.json "$APP_OUTPUT/Contents/Resources/"
cp -R web/dist/. "$APP_OUTPUT/Contents/Resources/web/"
cp macos/assessments-v2.json "$APP_OUTPUT/Contents/Resources/seed/"
cp data/products.json data/product-pulse.json "$APP_OUTPUT/Contents/Resources/seed/"
cp data/latest-24h.json data/latest-7d.json "$APP_OUTPUT/Contents/Resources/seed/"
mkdir -p "$APP_OUTPUT/Contents/Resources/web/data"
cp data/source-status.json data/opml-feeds.json "$APP_OUTPUT/Contents/Resources/web/data/"
python3 - "$APP_OUTPUT/Contents/Resources/web/index.html" <<'PYBUILD'
from pathlib import Path
import sys
path=Path(sys.argv[1])
path.write_text(path.read_text().replace('type="module"', 'defer').replace('crossorigin', ''))
PYBUILD
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 \
  macos/Models.swift macos/ArticleEvidence.swift macos/Scoring.swift macos/InterestScore.swift macos/NewsPriority.swift macos/DirectFeeds.swift macos/LocalCollector.swift macos/SourceTimes.swift macos/Products.swift macos/NewsStore.swift macos/Views.swift macos/ProductViews.swift macos/App.swift \
  -framework Cocoa -framework SwiftUI -framework WebKit -framework Security -framework CryptoKit \
  -o "$APP_OUTPUT/Contents/MacOS/AINewsMenu"
codesign --force --sign - "$APP_OUTPUT/Contents/Helpers/node"
codesign --force --deep --sign - "$APP_OUTPUT"
printf 'Built: %s\n' "$APP_OUTPUT"
