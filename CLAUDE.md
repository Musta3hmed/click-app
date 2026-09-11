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

Note: as of the last check there was **no iOS Simulator runtime installed** on
Mustafa's machine (`xcrun simctl list runtimes` is empty). Install with
`xcodebuild -downloadPlatform iOS` (~7GB) if you need to actually run the app
rather than just compile it.

## Conventions

- SwiftUI only — no UIKit unless there's no SwiftUI equivalent.
- SwiftData for persistence. Models are `@Model final class`.
- Keep views small; extract subviews rather than growing one big `body`.
- No third-party dependencies without discussing first.

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

The app is **Click**, a swipe-to-meet social discovery app. Three tabs behind a
custom floating tab bar: chats, swipe, profile — gated behind WelcomeView (animated sign-in screen; mock auth via @AppStorage "isSignedIn"). All data is local SwiftData with
seeded mock content — there is no backend.

Source layout inside `Click/`:

```
Support/     Theme.swift (all design tokens), Haptics, SafetyCenter
Components/  The six reusable views — build new UI from these
Models/      SwiftData @Model types + AppSchema (schema source of truth)
Mock/        MockData.swift — replace wholesale when a backend lands
Screens/     RootView, WelcomeView (sign-in gate), ChatsView, SwipeView, ProfileView, ConversationView, SettingsView
```

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
