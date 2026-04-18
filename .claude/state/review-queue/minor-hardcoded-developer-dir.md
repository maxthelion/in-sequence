# Minor: pre-git-push hook hardcodes DEVELOPER_DIR

**File:** `.claude/hooks/pre-git-push.sh`, lines 43–44
**Severity:** Minor

## What's wrong

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild …
```

Hardcoded path breaks on:

- `xcode-select -s` pointed at a different Xcode
- Xcode-beta installations (e.g. `Xcode-beta.app`)
- CI runners with Xcode in `/opt/Xcode/…` or `/Applications/Xcode_15.4.app/…`
- Users with Xcode at a non-default path

## What would be right

Only override when `DEVELOPER_DIR` is unset:

```bash
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
xcodebuild …
```

Or use `xcrun` which resolves the active developer dir at runtime:

```bash
xcrun xcodebuild -project … test
```

## Acceptance

- Hook works with `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` in the environment.
- Hook still works with no `DEVELOPER_DIR` set.
