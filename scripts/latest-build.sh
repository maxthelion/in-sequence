#!/usr/bin/env bash
set -euo pipefail

website_url="${INSEQ_WEBSITE_URL:-https://inseq-website.maxthelion.workers.dev}"
mode="summary"

case "${1:-}" in
  "") ;;
  --json) mode="json" ;;
  --download-url) mode="download-url" ;;
  -h|--help)
    cat <<'USAGE'
Usage: scripts/latest-build.sh [--json|--download-url]

Reads the marketing website's machine-readable latest release marker.

Environment:
  INSEQ_WEBSITE_URL  Override the website origin.
USAGE
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 64
    ;;
esac

website_url="${website_url%/}"
if [[ "$mode" == "download-url" ]]; then
  printf '%s/download/latest\n' "$website_url"
  exit 0
fi

release_json="$(curl --fail --silent --show-error "$website_url/api/releases/latest")"
if [[ "$mode" == "json" ]]; then
  printf '%s\n' "$release_json"
  exit 0
fi

printf '%s' "$release_json" | node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const release = JSON.parse(input);
  const mb = (Number(release.bytes || 0) / 1024 / 1024).toFixed(1);
  console.log(`Latest build: ${release.fileName}`);
  console.log(`Commit:       ${release.commit || "unknown"}`);
  console.log(`Branch:       ${release.branch || "unknown"}`);
  console.log(`Published:    ${release.createdAt || "unknown"}`);
  console.log(`Size:         ${mb} MB`);
  console.log(`SHA-256:      ${release.sha256 || "unknown"}`);
});
'
printf 'Download:     %s/download/latest\n' "$website_url"
