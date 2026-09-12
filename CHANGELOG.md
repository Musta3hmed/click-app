# Changelog

All notable changes to Click are documented here. Versions map to the
phase PRs; each also exists as a tagged
[GitHub release](https://github.com/Musta3hmed/click-app/releases).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning is [semver](https://semver.org/)-shaped (0.x while pre-App Store).

## [v0.4.0-beta.1] - 2026-09-12 (pre-release)

Phase 4 — [PR #4](https://github.com/Musta3hmed/click-app/pull/4) (open;
runtime verification on device pending).

### Added
- Five-tier `Theme.Motion` token system with a Reduce-Motion-aware
  `ClickMotion` environment resolver; CI lint bans raw animation curves
  outside the motion system.
- Light / dark / system appearance switch in Settings, re-theming live.
- MeshGradient ambient background behind the three tabs; welcome lava
  ported to the same GPU-native approach.
- Boost: spendable 30-minute visibility window with countdown indicator.
- Super likes with an opener, and a requests folder with accept/deny
  (also from inside the thread); 1 free super like per day.
- Bulk message to up to the next 100 people: booster-gated, confirmed,
  rate-limited to 1 per 24h, match celebrations suppressed in the loop.
- Matches folder (every mutual like lands somewhere visible) and a
  profile-views folder fed by boost activity.
- Real filters sheet (age / verified / interests), edit profile with the
  user's own photos, Settings location / legal / review / guidelines rows.
- Tab bar hides inside conversations (`ChromeState`).
- Scroll-driven header collapse on chats/profile (148pt to 92pt, 1:1 with
  the finger).
- Monetization surfaces (coin store, subscription tiers) — simulated,
  labelled "demo - no real charge" (owner decision 12 Sep 2026).
- Email sign-up with a required phone verification gate.
- 50-coin welcome bonus on wallet creation.
- CI executes the unit test suite on every push.

### Changed
- Elevated dark surface ramp, tempered brand palette for dark, visible
  sheet edges, no white-slab chrome, themed system sheets.
- Rewritten `ClickButtonStyle`: per-size press scale, asymmetric springs,
  built-in disabled treatment, opt-out haptics.
- Swipe deck performance rework (`CardDeck` owns drag state); bingo tiles
  genuinely 3D-flip; coins fly from claimed tiles to the wallet; coin spin
  is monotonic (never rewinds); sent chat bubbles animate from the composer.
- Design-token sweep: spacing scale, one text-field geometry, one primary
  button height, radius and glyph tokens, lowercase casing rules.

### Fixed
- Zodiac derived from date of birth (was always Aquarius).
- Duplicate conversations from start-over and double-send; rewind now
  cleans up N-deep.
- Dead controls removed or wired; `admirers`/`reveal` boosters no longer
  sold without a mechanic.
- Defaults keys centralised; account erasure clears all of them.

## [v0.3.0] - 2026-09-11

Phase 3 — [PR #3](https://github.com/Musta3hmed/click-app/pull/3),
cross-reviewed by three parallel agents (~40 findings fixed).

### Added
- Runtime demo photos (generated faces; no bundled likenesses).
- 3x3 daily bingo with coins-only rewards and in-app odds.
- Structural emoji ban enforced by CI.

### Fixed
- All 7 ship blockers: full account erasure bound to `ownerProviderID`,
  delete account, honest report copy, safety-menu hit-testing, blocking
  dismisses the open chat, under-18 answers exit onboarding, reduced
  location accuracy.
- Lightweight-migration crash: every new stored property carries a
  declared default (now a standing rule).
- Accessibility and layout pass across every screen, SE-class included.

## [v0.2.0] - 2026-09-11

Phase 2 — [PR #2](https://github.com/Musta3hmed/click-app/pull/2).

### Added
- Auth architecture: Keychain-backed session; Apple/Google PKCE flows
  gated behind `AuthConfig` (mocks until real credentials exist).
- Resumable onboarding with a hard 18+ gate and coarse-only location.
- Swipe overhaul: photo paging, opener composer, match celebration.
- Vector `CoinView`, shared `ClickButtonStyle`.
- CI: build-for-testing on a macOS runner.

### Changed
- Orange/pink logo palette applied app-wide.

## [v0.1.0] - 2026-09-11

Phase 1 — [PR #1](https://github.com/Musta3hmed/click-app/pull/1).

### Added
- Animated welcome / sign-in screen (gradient-blob lava, mock auth).
- Click logo as `AppIcon` + `Logo` assets.

### Changed
- Project renamed from "Project FOMO - Social Media" to **Click**;
  bundle identifiers moved to `Jatlas.Click*`.

[v0.4.0-beta.1]: https://github.com/Musta3hmed/click-app/releases/tag/v0.4.0-beta.1
[v0.3.0]: https://github.com/Musta3hmed/click-app/releases/tag/v0.3.0
[v0.2.0]: https://github.com/Musta3hmed/click-app/releases/tag/v0.2.0
[v0.1.0]: https://github.com/Musta3hmed/click-app/releases/tag/v0.1.0
