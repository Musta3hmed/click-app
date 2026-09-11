# FOMO — Social Media App

iOS app built with SwiftUI + SwiftData. Two developers, each running their own
Claude Code session on their own machine. This file is committed so both
sessions share the same context and conventions.

## Project layout

```
Project FOMO - Social Media.xcodeproj   # objectVersion 77 (Xcode 16+)
Project FOMO - Social Media/            # app sources
  Project_FOMO___Social_MediaApp.swift  # @main entry, ModelContainer setup
  ContentView.swift                     # root view
  Item.swift                            # SwiftData @Model
  Assets.xcassets/
Project FOMO - Social MediaTests/       # unit tests
Project FOMO - Social MediaUITests/      # UI tests
```

The target name contains spaces and hyphens, so the Swift type names use
underscore-mangled forms (`Project_FOMO___Social_MediaApp`). This is expected —
do not "fix" it.

## Build

The project uses **file system synchronized groups**. Files added to the source
folder are picked up automatically — you do *not* need to edit `project.pbxproj`
to add a file. Never hand-edit `project.pbxproj`.

Verify a build from the command line:

```bash
xcodebuild -project 'Project FOMO - Social Media.xcodeproj' \
  -scheme 'Project FOMO - Social Media' \
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

The app is still the stock Xcode SwiftUI + SwiftData template — a list that adds
rows showing timestamps. No FOMO-specific features are implemented yet. The
product direction has not been defined.
