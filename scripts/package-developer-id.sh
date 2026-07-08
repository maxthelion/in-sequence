#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/package-developer-id.sh --team-id TEAMID --notary-profile PROFILE [options]

Build, sign, export, notarize, staple, and zip SequencerAI for distribution
outside the Mac App Store using a Developer ID Application certificate.

Required unless supplied by environment:
  --team-id TEAMID             Apple Developer Team ID
                               env: SEQAI_DEVELOPMENT_TEAM, DEVELOPMENT_TEAM,
                                    APPLE_TEAM_ID
  --notary-profile PROFILE     notarytool keychain profile
                               env: SEQAI_NOTARY_PROFILE, NOTARY_PROFILE

Options:
  --identity NAME              Signing identity. Defaults to
                               "Developer ID Application"
                               env: SEQAI_DEVELOPER_ID_APPLICATION
  --output-dir DIR             Output directory. Defaults to
                               dist/developer-id/<timestamp>-<commit>
  --app-name NAME              Distributed .app bundle name. Defaults to
                               "In Sequence"
                               env: SEQAI_DISTRIBUTION_APP_NAME
  --configuration NAME         Xcode configuration. Defaults to Release
  --scheme NAME                Xcode scheme. Defaults to SequencerAI
  --skip-notarize              Export and zip the signed app, but do not
                               notarize or staple it.
  --allow-dirty                Permit packaging from a dirty git worktree.
  --help                       Show this help.

Before first notarization, store credentials with:
  xcrun notarytool store-credentials seqai-notary \
    --apple-id YOUR_APPLE_ID \
    --team-id TEAMID \
    --password APP_SPECIFIC_PASSWORD

Then run:
  scripts/package-developer-id.sh \
    --team-id TEAMID \
    --notary-profile seqai-notary
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/SequencerAI.xcodeproj"
scheme="SequencerAI"
configuration="Release"
distribution_app_name="${SEQAI_DISTRIBUTION_APP_NAME:-In Sequence}"
team_id="${SEQAI_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-${APPLE_TEAM_ID:-}}}"
signing_identity="${SEQAI_DEVELOPER_ID_APPLICATION:-Developer ID Application}"
notary_profile="${SEQAI_NOTARY_PROFILE:-${NOTARY_PROFILE:-}}"
output_dir=""
skip_notarize=0
allow_dirty=0

while (($# > 0)); do
  case "$1" in
    --team-id)
      [[ $# -ge 2 ]] || { printf 'Missing value for --team-id\n' >&2; exit 64; }
      team_id="${2:-}"
      shift 2
      continue
      ;;
    --identity)
      [[ $# -ge 2 ]] || { printf 'Missing value for --identity\n' >&2; exit 64; }
      signing_identity="${2:-}"
      shift 2
      continue
      ;;
    --notary-profile)
      [[ $# -ge 2 ]] || { printf 'Missing value for --notary-profile\n' >&2; exit 64; }
      notary_profile="${2:-}"
      shift 2
      continue
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { printf 'Missing value for --output-dir\n' >&2; exit 64; }
      output_dir="${2:-}"
      shift 2
      continue
      ;;
    --configuration)
      [[ $# -ge 2 ]] || { printf 'Missing value for --configuration\n' >&2; exit 64; }
      configuration="${2:-}"
      shift 2
      continue
      ;;
    --app-name)
      [[ $# -ge 2 ]] || { printf 'Missing value for --app-name\n' >&2; exit 64; }
      distribution_app_name="${2:-}"
      shift 2
      continue
      ;;
    --scheme)
      [[ $# -ge 2 ]] || { printf 'Missing value for --scheme\n' >&2; exit 64; }
      scheme="${2:-}"
      shift 2
      continue
      ;;
    --skip-notarize)
      skip_notarize=1
      ;;
    --allow-dirty)
      allow_dirty=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if [[ -z "$team_id" ]]; then
  printf 'Missing --team-id TEAMID.\n\n' >&2
  usage >&2
  exit 64
fi

if ((skip_notarize == 0)) && [[ -z "$notary_profile" ]]; then
  printf 'Missing --notary-profile PROFILE, or pass --skip-notarize.\n\n' >&2
  usage >&2
  exit 64
fi

for tool in git xcodebuild xcrun ditto codesign; do
  command -v "$tool" >/dev/null || {
    printf 'Required tool not found on PATH: %s\n' "$tool" >&2
    exit 127
  }
done

cd "$repo_root"

if ((allow_dirty == 0)) && [[ -n "$(git status --porcelain)" ]]; then
  printf 'Refusing to package from a dirty worktree. Commit/stash changes or pass --allow-dirty.\n' >&2
  git status --short >&2
  exit 65
fi

commit="$(git rev-parse --short=12 HEAD)"
branch="$(git rev-parse --abbrev-ref HEAD)"
dirty="false"
if [[ -n "$(git status --porcelain)" ]]; then
  dirty="true"
fi

if [[ -z "$output_dir" ]]; then
  timestamp="$(date -u +%Y%m%d-%H%M%S)"
  output_dir="$repo_root/dist/developer-id/${timestamp}-${commit}"
fi

archive_path="$output_dir/SequencerAI.xcarchive"
export_dir="$output_dir/export"
export_options="$output_dir/ExportOptions.plist"
zip_slug="$(printf '%s' "$distribution_app_name" | tr -cd '[:alnum:]_-')"
if [[ -z "$zip_slug" ]]; then
  zip_slug="SequencerAI"
fi
notary_zip="$output_dir/${zip_slug}-notary-submit.zip"
final_zip="$output_dir/${zip_slug}-${commit}-developer-id.zip"

mkdir -p "$output_dir"

cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${team_id}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>${signing_identity}</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

printf 'Packaging SequencerAI Developer ID build\n'
printf '  branch:          %s\n' "$branch"
printf '  commit:          %s\n' "$commit"
printf '  dirty:           %s\n' "$dirty"
printf '  team:            %s\n' "$team_id"
printf '  identity:        %s\n' "$signing_identity"
printf '  app name:        %s\n' "$distribution_app_name"
printf '  output:          %s\n' "$output_dir"

xcodebuild archive \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity" \
  DEVELOPMENT_TEAM="$team_id" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  GIT_COMMIT="$commit" \
  GIT_BRANCH="$branch" \
  GIT_DIRTY="$dirty"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$export_options"

app_path="$(find "$export_dir" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "$app_path" ]]; then
  printf 'Export succeeded but no .app was found in %s\n' "$export_dir" >&2
  exit 66
fi

distribution_app_path="$export_dir/${distribution_app_name}.app"
if [[ "$app_path" != "$distribution_app_path" ]]; then
  rm -rf "$distribution_app_path"
  mv "$app_path" "$distribution_app_path"
  app_path="$distribution_app_path"
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_zip"

if ((skip_notarize == 0)); then
  xcrun notarytool submit "$notary_zip" \
    --keychain-profile "$notary_profile" \
    --wait

  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
fi

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$final_zip"

printf '\nDeveloper ID package complete:\n'
printf '  app:             %s\n' "$app_path"
printf '  zip:             %s\n' "$final_zip"
if ((skip_notarize == 1)); then
  printf '  notarization:    skipped\n'
else
  printf '  notarization:    stapled\n'
fi
