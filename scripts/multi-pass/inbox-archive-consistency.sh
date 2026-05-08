#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

settings="docs/multi-pass-coordinator/settings.yaml"
coordinator_inbox="docs/multi-pass-coordinator/inbox/coordinator"

echo "# Inbox Archive Consistency"
echo
echo "- command_id: inbox-archive-consistency"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

if [ ! -f "$settings" ]; then
  echo "Missing settings file: $settings"
  exit 0
fi

frontmatter_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter {
      split($0, parts, ":")
      if (parts[1] == key) {
        sub("^[^:]*:[[:space:]]*", "", $0)
        gsub(/^["'\'']|["'\'']$/, "", $0)
        print $0
        exit
      }
    }
  ' "$file"
}

configured_inboxes() {
  awk '
    $0 == "loops:" { in_loops = 1; next }
    in_loops && /^scripts:/ { exit }
    in_loops && /^  - id:/ {
      id = $3
      next
    }
    in_loops && /^    inbox:/ {
      sub(/^    inbox:[[:space:]]*/, "", $0)
      print id "\t" $0
    }
  ' "$settings"
}

echo "## Configured Actor Inboxes"
configured_inboxes | while IFS=$'\t' read -r actor inbox; do
  if [ -d "$inbox" ]; then
    echo "- $actor: $inbox"
  else
    echo "- $actor: $inbox (missing)"
  fi
done
echo

echo "## Archived Requests Still Marked Pending"
found_archived_pending=0
while IFS=$'\t' read -r actor inbox; do
  archive="$inbox/archive"
  [ -d "$archive" ] || continue
  while IFS= read -r file; do
    status="$(frontmatter_value status "$file" || true)"
    if [ "$status" = "pending" ]; then
      echo "- $actor: $file"
      found_archived_pending=1
    fi
  done < <(find "$archive" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' -print | sort)
done < <(configured_inboxes)
if [ "$found_archived_pending" -eq 0 ]; then
  echo "- none"
fi
echo

echo "## Active Requests Also Present In Archive"
found_active_archive_duplicate=0
while IFS=$'\t' read -r actor inbox; do
  archive="$inbox/archive"
  [ -d "$inbox" ] || continue
  [ -d "$archive" ] || continue
  while IFS= read -r file; do
    archived="$archive/$(basename "$file")"
    if [ -f "$archived" ]; then
      echo "- $actor: $(basename "$file")"
      echo "  active: $file"
      echo "  archived: $archived"
      found_active_archive_duplicate=1
    fi
  done < <(find "$inbox" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name '.gitkeep' -print | sort)
done < <(configured_inboxes)
if [ "$found_active_archive_duplicate" -eq 0 ]; then
  echo "- none"
fi
echo

echo "## Duplicate Coordinator Completion Notes"
completion_rows="$(mktemp)"
trap 'rm -f "$completion_rows"' EXIT

if [ -d "$coordinator_inbox" ]; then
  while IFS= read -r file; do
    actor="$(sed -n 's/^Actor `\([^`]*\)` completed request `.*/\1/p' "$file" | head -1)"
    request="$(sed -n 's/^Actor `[^`]*` completed request `\([^`]*\)`.*/\1/p' "$file" | head -1)"
    result="$(sed -n 's/^- result: `\([^`]*\)`.*/\1/p' "$file" | head -1)"
    if [ -n "$actor" ] && [ -n "$request" ] && [ -n "$result" ]; then
      printf '%s\t%s\t%s\t%s\n' "$actor" "$request" "$result" "$file" >> "$completion_rows"
    fi
  done < <(find "$coordinator_inbox" -maxdepth 2 -type f -name '*.md' ! -name 'README.md' -print | sort)
fi

if [ -s "$completion_rows" ]; then
  sort -t $'\t' -k1,1 -k2,2 -k3,3 "$completion_rows" | awk -F '\t' '
    function flush(i) {
      if (count > 1) {
        print "- actor: `" actor "`"
        print "  request: `" request "`"
        print "  result: `" result "`"
        print "  notes:"
        for (i = 1; i <= count; i++) {
          print "    - " files[i]
        }
        found = 1
      }
      delete files
      count = 0
    }
    {
      key = $1 FS $2 FS $3
      if (NR > 1 && key != last_key) {
        flush()
      }
      actor = $1
      request = $2
      result = $3
      files[++count] = $4
      last_key = key
    }
    END {
      if (NR > 0) {
        flush()
      }
      if (!found) {
        print "- none"
      }
    }
  '
else
  echo "- none"
fi
