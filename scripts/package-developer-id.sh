#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/package-developer-id.sh --team-id TEAMID --notary-profile PROFILE [options]

Build, sign, export, notarize, staple, and package SequencerAI for distribution
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
  --skip-notarize              Export and package the signed app, but do not
                               notarize or staple it.
  --upload-r2                  Upload the final DMG to Cloudflare R2.
                               env: SEQAI_UPLOAD_R2=1
  --r2-key KEY                 R2 object key for the final DMG.
  --r2-prefix PREFIX           R2 object prefix. Defaults to
                               releases/developer-id.
                               env: R2_DISTRIBUTION_PREFIX
  --r2-bucket BUCKET           R2 bucket. Env: R2_DISTRIBUTION_BUCKET, R2_BUCKET
  --r2-endpoint URL            R2 S3 endpoint. Env: R2_DISTRIBUTION_ENDPOINT,
                               R2_ENDPOINT
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
upload_r2=0
r2_key=""
r2_prefix="${R2_DISTRIBUTION_PREFIX:-releases/developer-id}"
r2_bucket="${R2_DISTRIBUTION_BUCKET:-${R2_BUCKET:-}}"
r2_endpoint="${R2_DISTRIBUTION_ENDPOINT:-${R2_ENDPOINT:-}}"

case "${SEQAI_UPLOAD_R2:-}" in
  1|true|TRUE|yes|YES|on|ON)
    upload_r2=1
    ;;
esac

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
    --upload-r2)
      upload_r2=1
      ;;
    --r2-key)
      [[ $# -ge 2 ]] || { printf 'Missing value for --r2-key\n' >&2; exit 64; }
      r2_key="${2:-}"
      shift 2
      continue
      ;;
    --r2-prefix)
      [[ $# -ge 2 ]] || { printf 'Missing value for --r2-prefix\n' >&2; exit 64; }
      r2_prefix="${2:-}"
      shift 2
      continue
      ;;
    --r2-bucket)
      [[ $# -ge 2 ]] || { printf 'Missing value for --r2-bucket\n' >&2; exit 64; }
      r2_bucket="${2:-}"
      shift 2
      continue
      ;;
    --r2-endpoint)
      [[ $# -ge 2 ]] || { printf 'Missing value for --r2-endpoint\n' >&2; exit 64; }
      r2_endpoint="${2:-}"
      shift 2
      continue
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

for tool in git xcodebuild xcrun ditto codesign hdiutil; do
  command -v "$tool" >/dev/null || {
    printf 'Required tool not found on PATH: %s\n' "$tool" >&2
    exit 127
  }
done

if ((upload_r2 == 1)); then
  command -v node >/dev/null || {
    printf 'Required tool not found on PATH for --upload-r2: node\n' >&2
    exit 127
  }
fi

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
final_dmg="$output_dir/${zip_slug}-${commit}-developer-id.dmg"
dmg_staging="$output_dir/dmg-root"

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
if ((upload_r2 == 1)); then
  printf '  r2 upload:       enabled\n'
  printf '  r2 bucket:       %s\n' "${r2_bucket:-<from env file>}"
  printf '  r2 prefix:       %s\n' "$r2_prefix"
fi

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

rm -rf "$dmg_staging" "$final_dmg"
mkdir -p "$dmg_staging"
ditto "$app_path" "$dmg_staging/${distribution_app_name}.app"
ln -s /Applications "$dmg_staging/Applications"
hdiutil create \
  -volname "$distribution_app_name" \
  -srcfolder "$dmg_staging" \
  -format UDZO \
  -ov \
  "$final_dmg"
codesign --force --sign "$signing_identity" --timestamp "$final_dmg"
codesign --verify --verbose=2 "$final_dmg"

if ((skip_notarize == 0)); then
  xcrun notarytool submit "$final_dmg" \
    --keychain-profile "$notary_profile" \
    --wait

  xcrun stapler staple "$final_dmg"
  xcrun stapler validate "$final_dmg"
fi

r2_upload_json=""
if ((upload_r2 == 1)); then
  upload_args=("$repo_root/scripts/r2-upload-artifact.mjs" "$final_dmg" "--prefix" "$r2_prefix")
  if [[ -n "$r2_key" ]]; then
    upload_args+=("--key" "$r2_key")
  fi
  if [[ -n "$r2_bucket" ]]; then
    upload_args+=("--bucket" "$r2_bucket")
  fi
  if [[ -n "$r2_endpoint" ]]; then
    upload_args+=("--endpoint" "$r2_endpoint")
  fi
  r2_upload_json="$(node "${upload_args[@]}")"
  printf '%s\n' "$r2_upload_json"
fi

printf '\nDeveloper ID package complete:\n'
printf '  app:             %s\n' "$app_path"
printf '  dmg:             %s\n' "$final_dmg"
if ((skip_notarize == 1)); then
  printf '  notarization:    skipped\n'
else
  printf '  notarization:    app and dmg stapled\n'
fi
if ((upload_r2 == 1)); then
  printf '  r2 upload:       complete\n'
fi
