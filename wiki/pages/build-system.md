---
title: "Build System"
category: "meta"
tags: [build, xcodegen, xcode, ci, developer-dir]
summary: How the Xcode project is generated and built — xcodegen driven from project.yml, DEVELOPER_DIR workaround for environments where xcode-select points at CommandLineTools.
last-modified-by: user
---

## Rationale

The Xcode project is **generated** from `project.yml` by [xcodegen](https://github.com/yonaskolb/XcodeGen). Rationale:

- Agent-executable — no GUI steps
- Reviewable — `project.yml` is readable text; `.xcodeproj/project.pbxproj` is not
- Reproducible — re-running `xcodegen generate` from the same `project.yml` produces equivalent output
- Upgrade-friendly — new Xcode versions don't force merge conflicts in the checked-in project file

`.xcodeproj` is in `.gitignore`; `project.yml` is committed.

## Regenerating the project

```bash
xcodegen generate
```

From the repo root. Produces `SequencerAI.xcodeproj` anew. Existing DerivedData is safe to keep; regeneration just rewrites the project file.

## Building and testing from the command line

Standard:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS' test
```

Clean from scratch (what CI will do):

```bash
rm -rf SequencerAI.xcodeproj /tmp/seqai-build
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS' -derivedDataPath /tmp/seqai-build \
  clean build test
```

Expect `** TEST SUCCEEDED **`.

## Why `DEVELOPER_DIR`

Some environments (CI, dev machines recently updated, some laptop setups) leave `xcode-select` pointing at `/Library/Developer/CommandLineTools` instead of the full Xcode install. That breaks `xcodebuild` with *"tool 'xcodebuild' requires Xcode"*.

Fix options:

- **Non-invasive (preferred):** prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. No persistent system change.
- **Invasive:** `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` — persistent but requires admin.

Every automated build command in the repo uses the non-invasive form.

## project.yml shape

Top-level blocks:

- `name`, `options` (bundle prefix, deployment target, intermediate groups)
- `settings.base` — Swift version, deployment target, codesigning identity (`-` = ad-hoc)
- `targets.SequencerAI` — the app; sources under `Sources/`; resources (`Info.plist`); entitlements (sandbox + user-selected read-write + audio-input); `GENERATE_INFOPLIST_FILE: NO` because `info.properties` supplies the plist inline
- `targets.SequencerAITests` — XCTest bundle; depends on `SequencerAI`; hosts in the app bundle; `GENERATE_INFOPLIST_FILE: YES` (Xcode 16 requirement for test targets)
- `schemes.SequencerAI` — build targets + test target mapping

## Entitlements

`Sources/Resources/SequencerAI.entitlements`:

- `com.apple.security.app-sandbox` — required for macOS App Store distribution and general hygiene
- `com.apple.security.files.user-selected.read-write` — Document-based app needs this to open/save `.seqai` files via NSOpenPanel / NSSavePanel
- `com.apple.security.files.bookmarks.app-scope` — for restoring recent-files across launches
- `com.apple.security.device.audio-input` — reserved for future audio-side work

## When to edit project.yml

Whenever adding a new top-level source directory, target, test bundle, entitlement, scheme, or custom build setting. Always followed by `xcodegen generate` + commit. Never edit `.xcodeproj/project.pbxproj` directly — your edits will be overwritten on next regenerate.

## References

- `project.yml` in repo root
- xcodegen docs: <https://github.com/yonaskolb/XcodeGen/tree/master/Docs>
