# Click — Social Media App

iOS app built with SwiftUI + SwiftData. Two developers, each running their own
Claude Code session on their own machine. This file is committed so both
sessions share the same context and conventions.

## Project layout

```
Click.xcodeproj   # objectVersion 77 (Xcode 16+)
Click/            # app sources
  ClickApp.swift  # @main entry, ModelContainer setup
  Assets.xcassets/  # AppIcon + Logo (brand mark)
  Components/ Mock/ Models/ Screens/ Support/
ClickTests/       # unit tests
ClickUITests/      # UI tests
```

The project was renamed from "Project FOMO - Social Media" to **Click**:
target, scheme, product, bundle ids (`Jatlas.Click*`), folders and type names.

## Build

The project uses **file system synchronized groups**. Files added to the source
folder are picked up automatically — you do *not* need to edit `project.pbxproj`
to add a file. Never hand-edit `project.pbxproj`.

Verify a build from the command line:

```bash
xcodebuild -project 'Click.xcodeproj' \
  -scheme 'Click' \
  -destination 'generic/platform=iOS' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

If `xcrun simctl list runtimes` comes back empty, install a simulator
runtime with `xcodebuild -downloadPlatform iOS` (~7GB) before trying to run
the app rather than just compile it.

## Conventions

- SwiftUI only — no UIKit unless there's no SwiftUI equivalent.
- SwiftData for persistence. Models are `@Model final class`.
- Keep views small; extract subviews rather than growing one big `body`.
- No third-party dependencies without discussing first.

### Motion (phase 4)

- **Never declare an animation curve outside `Theme.Motion`** —
  `Theme.swift` and `ClickMotion.swift` are the only files allowed to
  (CI lints for it). Call sites read `@Environment(\.motion)`, which maps
  every tier to a short fade under Reduce Motion; never branch on
  `accessibilityReduceMotion` in a view (RootView is the single read).
- Buttons use `.buttonStyle(.click)` (or `.clickQuiet` / `.clickSilent`);
  the style owns the press animation, the disabled treatment AND the
  haptic — never add a manual haptic next to it.

### Casing (phase 4)

1. Anything **Click draws** is lowercase: titles, buttons, labels,
   enum `label`s, menu items.
2. Anything the **system** draws (alert titles/buttons/messages) is
   sentence case.
   All-caps is reserved for the hero headline, the two celebration
   headlines, and the LIKE/NOPE stamps. Accessibility labels stay natural
   sentence case (they are spoken, not drawn).

### Layout tokens (phase 4)

- Spacing on the 4pt grid via `Theme.Metric.Space` stops; corner radii via
  the `Metric` radius tokens (a raw literal in `cornerRadius:` is allowed
  only in ConfettiView/ClickLogoView); primary buttons are 52pt capsules;
  text fields are 16/12 padding.

## Working together — IMPORTANT

Two Claude sessions are editing this repo from different machines. Neither one
can see the other's uncommitted work.

- **Branch per feature.** Never commit directly to `main`.
- **Pull before you start.** `git pull --rebase origin main`
- **Push often.** Small commits. Long-lived branches drift badly here.
- **Split by feature area, not by file.** Claude rewrites whole files, so two
  people in one file is the main way this goes wrong. Agree on ownership
  ("you take the feed, I take auth") before starting.
- **Never commit `xcuserdata/`.** It's gitignored. It holds per-user Xcode
  window state and will conflict endlessly if it sneaks back in.

## Current state

The app is **Click**, a swipe-to-meet social discovery app. Flow: WelcomeView
(animated sign-in) → OnboardingView (name, 18+ DOB gate, gender, seeking,
photos, coarse location; resumable, persists per step) → three tabs behind a
custom floating tab bar (chats, swipe, profile). Auth is a real architecture
(`Click/Auth/`): AuthProvider protocol, Keychain-stored session, full Apple +
Google (PKCE) implementations gated behind AuthConfig until a paid Apple dev
account / Google client ID exist — mocks run meanwhile, labelled in the UI.
All data is local SwiftData with seeded mock content — there is no backend.
Brand is the orange/pink of the logo (Theme.brand*); the deck filters by the
user's seeking preference; coins are vector smileys (CoinView).

Source layout inside `Click/`:

```
Auth/        AuthProvider, AuthSession, KeychainStore, AccountEraser,
             Apple/Google/Mock providers
Support/     Theme.swift (all design tokens), Haptics, SafetyCenter,
             LocationService, ImageProcessing, ClickButtonStyle
Components/  Reusable views (CoinView, ConfettiView, ClickLogoView,
             CountryBadge, …) — build new UI from these
Models/      SwiftData @Model types + AppSchema (schema source of truth)
Mock/        MockData.swift + DemoPhotos.swift (runtime AI-face fetch)
Screens/     RootView, WelcomeView, WelcomeCelebrationView, Onboarding/,
             ChatsView, SwipeView, BingoView, ProfileView, ConversationView,
             SettingsView
```

Hard rules added in phase 3:

- **No emoji anywhere in Swift sources** — CI fails the build. They render
  as boxes where the emoji font is missing. Use SF Symbols or vectors;
  country flags are `CountryBadge` ISO-code pills.
- **Sign-out and account deletion go through `AuthSession.signOut(erasing:)`**
  → `AccountEraser`. Never leave the current-user row behind; it is bound to
  `ownerProviderID`.
- **No paid surfaces** (offers/subscription/coin store) without a decision —
  they were deliberately removed. Coins are earned (daily rewards, bingo)
  and spent (boosters, bingo claims) only.
- The report sheet's copy must stay honest: there is NO moderation backend.

Conventions that matter:

- **Never hard-code a colour or font.** Everything comes from `Theme` and the
  `Font.click(_:)` / `Font.clickPlain(_:)` helpers, which is what keeps light
  and dark mode working.
- `AppSchema.models` is the single schema list. Add new `@Model` types there or
  they will not persist.
- Header textures are drawn procedurally in `TexturedHeader.swift`. Swap the
  `Canvas` for an `Image` when real artwork exists.
- Avatars are generated initials-on-gradient (`StickerAvatar`). Deterministic
  per name, so they are stable across launches.

## Known gotchas

**Stale DerivedData breaks `@testable import`.** After deleting or renaming
files in the synchronized source folder, the app's emitted module can go stale
and every app symbol reads as "cannot find X in scope" from the test target —
with no "no such module" error to explain it. Check
`Build/Products/Debug-iphoneos/*.swiftmodule/*.abi.json`; if it says
`"name": "NO_MODULE"`, the module is empty. Fix:

```bash
xcodebuild -project 'Click.xcodeproj' -scheme 'Click' clean
```

**The Xcode project was generated with broken template expansion.** The app
entry point, the unit test file, and both UI test files all shipped with literal
`___FILEHEADER___` / `___PACKAGENAME:identifier___` / `___FILEBASENAMEASIDENTIFIER___`
placeholders that do not compile. All four are fixed. If you add a target and it
fails with `expected '{' in struct`, this is why.

**`#Predicate` needs `import Foundation`** — importing only SwiftData is not
enough in test files.
