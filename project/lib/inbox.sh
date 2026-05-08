#!/usr/bin/env bash

project_tick_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

project_tick_safe_name() {
  printf "%s" "$1" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//; s/-$//'
}

project_tick_request_status() {
  local file="$1"
  local status
  status="$(sed -n 's/^status:[[:space:]]*//p' "$file" | head -1 | tr '[:upper:]' '[:lower:]' || true)"
  printf "%s" "${status:-pending}"
}

project_tick_is_terminal_status() {
  case "$1" in
    done|complete|completed|archived|blocked|handled|superseded) return 0 ;;
    *) return 1 ;;
  esac
}

project_tick_first_runnable_request() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local file status
  while IFS= read -r file; do
    [ "$(basename "$file")" = "README.md" ] && continue
    status="$(project_tick_request_status "$file")"
    if ! project_tick_is_terminal_status "$status"; then
      printf "%s\n" "$file"
      return 0
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' ! -name '.*' | sort)
  return 1
}

project_tick_has_runnable_request() {
  project_tick_first_runnable_request "$1" >/dev/null
}

project_tick_archive_request() {
  local file="$1"
  local archive
  archive="$(dirname "$file")/archive"
  mkdir -p "$archive"
  mv "$file" "$archive/$(basename "$file")"
  printf "%s/%s\n" "$archive" "$(basename "$file")"
}

project_tick_mark_blocked() {
  local file="$1"
  local reason="$2"
  local tmp
  tmp="$(mktemp)"
  if grep -q '^status:' "$file"; then
    sed '0,/^status:.*/s//status: blocked/' "$file" > "$tmp"
  else
    {
      echo "---"
      echo "status: blocked"
      echo "---"
      echo
      cat "$file"
    } > "$tmp"
  fi
  if grep -q '^blocker_reason:' "$tmp"; then
    sed "0,/^blocker_reason:.*/s//blocker_reason: \"$reason\"/" "$tmp" > "$file"
  else
    awk -v reason="$reason" '
      BEGIN { inserted = 0 }
      /^---$/ && NR > 1 && inserted == 0 {
        print "blocker_reason: \"" reason "\""
        inserted = 1
      }
      { print }
    ' "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

project_tick_write_note() {
  local inbox="$1"
  local slug="$2"
  local title="$3"
  local body="$4"
  mkdir -p "$inbox"
  local file="$inbox/$(date -u +%Y-%m-%dT%H-%M-%SZ)-$(project_tick_safe_name "$slug").md"
  cat > "$file" <<EOF
---
created: $(project_tick_now_iso)
source: project-tick
status: pending
priority: medium
---

# $title

EOF
  printf "%b\n" "$body" >> "$file"
  printf "%s\n" "$file"
}
