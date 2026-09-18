# Contributing

Issues and pull requests are welcome. Include the relevant source URL and a
short example of the behavior you want to change.

## Development

Follow the build commands in [README.md](README.md). Run `npm test`, `npm run typecheck`
and `npm --prefix web run build`; for native or scoring changes, also run
`npm run test:macos` on a Mac.

`test/` contains upstream scripts that fetch live third-party sites. They
are optional diagnostics, not the automated regression suite.

## Sources and product releases

- Public direct RSS subscriptions belong in `feeds/direct-feeds.json`.
- Product profiles belong in `data/products.json`. Major-vendor releases
  need a specific name, `releasedOn` (official date, YYYY-MM-DD),
  `releaseKind`, and a first-party announcement in `sourceURL`.
- Do not replace the release date with the day it was scraped or mentioned
  in a later article. A brand name alone is not a release.
- Parse source-local dates with an explicit timezone. Use WordPress `date_gmt`
  as UTC where available. Future or inconsistent cached publication times use
  a clearly labeled collection time in the UI; never silently relabel it as publication.
- Keep summaries short, explain the change, and distinguish vendor claims
  from verified results. Popularity evidence is refreshed separately.

## Scoring

Follow [SCORE_POLICY.md](macos/SCORE_POLICY.md). Changes to the interface or
scoring rules should be checked with a small sample of today's news; do not
relabel historical news unless that is part of the agreed change.

Keep evidence levels separate from importance. Insufficient evidence means
pending assessment, not a zero score or an invented result.

## Local data

Keep credentials, personal OPML files, reading state, and machine-specific
paths out of commits. Generated archives, translation caches, and builds
are ignored. The Mac app stores its API key in Keychain.

Contributions are made under the [MIT License](LICENSE).
