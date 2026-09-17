#!/usr/bin/env bash
set -euo pipefail
TEST_SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TEST_SOURCE"
mkdir -p .build
xcrun swiftc -swift-version 5 \
  macos/Models.swift macos/ArticleEvidence.swift macos/Scoring.swift \
  macos/DirectFeeds.swift macos/Products.swift macos/NewsStore.swift \
  macos/DirectFeedTests.swift macos/ProductTests.swift macos/Tests.swift \
  -framework Cocoa -framework Security -framework CryptoKit \
  -o .build/scoring-tests
.build/scoring-tests macos/assessments-v2.json
