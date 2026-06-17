#!/usr/bin/env bash
# Build a static roadmap dashboard from deterministic roadmap state and current
# worktree hygiene signals. The retired /next-action behaviour tree is not
# refreshed or used here.

set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

ROADMAP_DIR="$REPO/docs/roadmap"
OUT="$ROADMAP_DIR/dashboard.html"
NOW_LOCAL="$(date '+%Y-%m-%d %H:%M %Z')"
NOW_EPOCH="$(date '+%s')"

html_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

frontmatter_value() {
  local file="$1"
  local key="$2"
  local fallback="${3:-}"

  if [ ! -f "$file" ]; then
    printf '%s\n' "$fallback"
    return
  fi

  local value
  value="$(awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      print
      exit
    }
  ' "$file")"

  if [ -n "$value" ]; then
    printf '%s\n' "$value" | sed 's/^"//; s/"$//'
  else
    printf '%s\n' "$fallback"
  fi
}

roadmap_dirs() {
  local index="$ROADMAP_DIR/README.md"
  local listed=""

  if [ -f "$index" ]; then
    listed="$(sed -n 's/^- \(**[0-9][0-9]*\*\* \)\{0,1\}\[[^]]*\](\([^)]*\/\))$/\2/p' "$index" | while IFS= read -r rel; do
      rel="${rel%/}"
      if [ -d "$ROADMAP_DIR/$rel" ]; then
        printf '%s\n' "$ROADMAP_DIR/$rel"
      fi
    done)"
  fi

  {
    printf '%s\n' "$listed"
    find "$ROADMAP_DIR" -mindepth 1 -maxdepth 1 -type d | sort
  } | awk 'NF && !seen[$0]++'
}

read_title() {
  local dir="$1"
  local title
  title="$(frontmatter_value "$dir/README.md" "title" "")"
  if [ -n "$title" ]; then
    printf '%s\n' "$title"
  elif [ -f "$dir/README.md" ]; then
    sed -n 's/^# //p' "$dir/README.md" | head -1
  else
    basename "$dir"
  fi
}

section_block() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == "## " heading { flag = 1; next }
    flag && /^## / { exit }
    flag { print }
  ' "$ROADMAP_DIR/next-actions.md"
}

section_value() {
  local heading="$1"
  local key="$2"
  section_block "$heading" | sed -n "s/^- \\*\\*$key:\\*\\* //p" | head -1
}

file_url() {
  printf 'file://%s\n' "$1"
}

relative_path() {
  local path="$1"
  printf '%s\n' "${path#$REPO/}"
}

count_files() {
  local dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f | wc -l | tr -d ' '
  else
    printf '0\n'
  fi
}

count_class() {
  if [ "$1" = "0" ]; then
    printf '%s\n' "ok"
  else
    printf '%s\n' "attention"
  fi
}

mtime_badge() {
  local file="$1"
  local mtime
  mtime="$(stat -f '%m' "$file")"
  if [ $((NOW_EPOCH - mtime)) -le 86400 ]; then
    printf '<span class="tag">new</span>'
  fi
}

refresh_selectors() {
  "$REPO/scripts/roadmap/next-roadmap-actions.sh" >/dev/null
}

prototype_groups_html() {
  local current_feature=""
  local file
  local feature_dir
  local feature_title

  while IFS= read -r file; do
    feature_dir="$(dirname "$(dirname "$file")")"
    if [ "$feature_dir" != "$current_feature" ]; then
      if [ -n "$current_feature" ]; then
        printf '%s\n' '          </ul>'
        printf '%s\n' '        </div>'
      fi
      current_feature="$feature_dir"
      feature_title="$(read_title "$feature_dir" | html_escape)"
      printf '%s\n' '        <div class="prototype-group">'
      printf '          <h3>%s</h3>\n' "$feature_title"
      printf '%s\n' '          <ul>'
    fi
    printf '            <li><a href="%s">%s</a> %s</li>\n' \
      "$(file_url "$file")" \
      "$(basename "$file" | html_escape)" \
      "$(mtime_badge "$file")"
  done < <(find "$ROADMAP_DIR" -path '*/prototypes/*.html' -type f | sort)

  if [ -n "$current_feature" ]; then
    printf '%s\n' '          </ul>'
    printf '%s\n' '        </div>'
  fi
}

worktree_rows_html() {
  git worktree list --porcelain | awk '
    /^worktree / { worktree = substr($0, 10) }
    /^HEAD / { head = substr($0, 6) }
    /^branch / {
      branch = substr($0, 8)
      print worktree "\t" head "\t" branch
      worktree = ""; head = ""; branch = ""
    }
  ' | while IFS=$'\t' read -r wt head branch; do
    local rel
    local short_head
    local dirty_count
    local status_class
    local detail

    rel="${wt#$REPO/}"
    if [ "$rel" = "$wt" ]; then
      rel="."
    fi
    short_head="$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || printf '%s' "${head:0:7}")"
    dirty_count="$(git -C "$wt" status --short 2>/dev/null | wc -l | tr -d ' ')"

    status_class="ok"
    detail="Clean."
    if [ "$dirty_count" != "0" ]; then
      status_class="attention"
      detail="$dirty_count dirty file(s)."
    fi

    printf '          <tr>\n'
    printf '            <td><strong>%s</strong><br><span class="muted">%s</span></td>\n' "$(printf '%s' "$rel" | html_escape)" "$(printf '%s' "$branch" | html_escape)"
    printf '            <td><code>%s</code></td>\n' "$(printf '%s' "$short_head" | html_escape)"
    printf '            <td><span class="%s">%s</span></td>\n' "$status_class" "$status_class"
    printf '            <td>%s</td>\n' "$dirty_count"
    printf '            <td>%s</td>\n' "$detail"
    printf '          </tr>\n'
  done
}

stage_rows_html() {
  roadmap_dirs | while IFS= read -r dir; do
    local readme="$dir/README.md"
    local id
    local title
    local status
    local stage
    local owner
    local slug

    [ -f "$readme" ] || continue
    id="$(frontmatter_value "$readme" "id" "?")"
    title="$(frontmatter_value "$readme" "title" "$(basename "$dir")")"
    status="$(frontmatter_value "$readme" "status" "unknown")"
    stage="$(frontmatter_value "$readme" "stage" "unknown")"
    owner="$(frontmatter_value "$readme" "owner" "unknown")"
    slug="$(basename "$dir")"

    printf '          <tr>\n'
    printf '            <td>%s</td><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td><td><a href="%s">open</a></td>\n' \
      "$(printf '%s' "$id" | html_escape)" \
      "$(printf '%s' "$title" | html_escape)" \
      "$(printf '%s' "$stage" | html_escape)" \
      "$(printf '%s' "$status" | html_escape)" \
      "$(printf '%s' "$owner" | html_escape)" \
      "$(file_url "$dir")"
    printf '          </tr>\n'
  done
}

recent_commits_html() {
  git log --date=short --pretty=format:'%h%x09%ad%x09%s' --max-count=8 | while IFS=$'\t' read -r sha date subject; do
    printf '          <li><code>%s</code> <span class="muted">%s</span> %s</li>\n' \
      "$(printf '%s' "$sha" | html_escape)" \
      "$(printf '%s' "$date" | html_escape)" \
      "$(printf '%s' "$subject" | html_escape)"
  done
}

runtime_messages_html() {
  local files
  files="$(find "$REPO/.meta/multipass/runtime/inbox/pending" -maxdepth 1 -type f -print 2>/dev/null | sort || true)"

  if [ -z "$files" ]; then
    printf '%s\n' '          <li><span class="ok">No pending Multi-Pass runtime messages.</span></li>'
    return
  fi

  printf '%s\n' "$files" | while IFS= read -r file; do
    printf '          <li><a href="%s">%s</a> <span class="muted">%s</span></li>\n' \
      "$(file_url "$file")" \
      "$(basename "$file" | html_escape)" \
      "$(relative_path "$file" | html_escape)"
  done
}

refresh_selectors

prototype_count="$(find "$ROADMAP_DIR" -path '*/prototypes/*.html' -type f | wc -l | tr -d ' ')"
new_prototype_count="$(find "$ROADMAP_DIR" -path '*/prototypes/*.html' -type f -mtime -1 | wc -l | tr -d ' ')"
open_question_count="$(find "$ROADMAP_DIR" -maxdepth 3 -type f -name 'open-questions.md' | wc -l | tr -d ' ')"
open_question_class="$(count_class "$open_question_count")"
runtime_pending_count="$(count_files "$REPO/.meta/multipass/runtime/inbox/pending")"
runtime_pending_class="$(count_class "$runtime_pending_count")"

next_user_item="$(section_value "Next User Item" "Item" | html_escape)"
next_user_feature="$(section_value "Next User Item" "Feature" | html_escape)"
next_user_action="$(section_value "Next User Item" "Action" | tr -d '`' | html_escape)"
next_user_why="$(section_value "Next User Item" "Why" | html_escape)"
next_agent_item="$(section_value "Next Agent Item" "Item" | html_escape)"
next_agent_feature="$(section_value "Next Agent Item" "Feature" | html_escape)"
next_agent_action="$(section_value "Next Agent Item" "Action" | tr -d '`' | html_escape)"
next_agent_why="$(section_value "Next Agent Item" "Why" | html_escape)"

cat > "$OUT" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Roadmap Dashboard</title>
  <style>
    :root {
      --bg: #f6f6f6;
      --panel: #fff;
      --text: #1d1d1f;
      --muted: #666a70;
      --border: #cfd2d6;
      --stub: #ebedef;
      --accent: #0f6bff;
      --attention: #9b4a00;
      --ok: #0f6b3d;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.45;
    }
    header, main { max-width: 1220px; margin: 0 auto; padding: 24px; }
    header { padding-bottom: 8px; }
    h1, h2, h3, p { margin-top: 0; }
    h1 { margin-bottom: 6px; font-size: 28px; }
    h2 { margin-bottom: 12px; font-size: 18px; }
    h3 { margin-bottom: 8px; font-size: 15px; }
    a { color: var(--accent); text-decoration: none; }
    a:hover, a:focus { text-decoration: underline; }
    code {
      padding: 1px 4px;
      background: var(--stub);
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 13px;
    }
    ul { margin: 0; padding-left: 20px; }
    li + li { margin-top: 6px; }
    .muted { color: var(--muted); }
    .ok { color: var(--ok); }
    .attention { color: var(--attention); }
    .summary, .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 12px;
      margin-bottom: 18px;
    }
    .panel, .summary-item {
      border: 1px solid var(--border);
      background: var(--panel);
      padding: 16px;
    }
    .wide { grid-column: 1 / -1; }
    .label {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .value { margin-top: 4px; font-size: 18px; font-weight: 700; }
    .prototype-list { display: grid; gap: 12px; }
    .prototype-group {
      border: 1px dashed var(--border);
      padding: 12px;
      background: #fbfbfb;
    }
    .tag {
      display: inline-block;
      margin-left: 6px;
      padding: 1px 6px;
      border: 1px solid currentColor;
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
    }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td {
      border-bottom: 1px solid var(--border);
      padding: 8px 6px;
      text-align: left;
      vertical-align: top;
    }
    th {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
  </style>
</head>
<body>
  <header>
    <h1>Roadmap Dashboard</h1>
    <p class="muted">Generated ${NOW_LOCAL} by <code>scripts/roadmap/build-dashboard.sh</code>. Selectors are refreshed before rendering.</p>
  </header>

  <main>
    <section class="summary">
      <div class="summary-item">
        <div class="label">Prototype Files</div>
        <div class="value">${prototype_count}</div>
      </div>
      <div class="summary-item">
        <div class="label">New Prototype Files</div>
        <div class="value">${new_prototype_count}</div>
      </div>
      <div class="summary-item">
        <div class="label">Open Questions</div>
        <div class="value ${open_question_class}">${open_question_count}</div>
      </div>
      <div class="summary-item">
        <div class="label">Runtime Pending</div>
        <div class="value ${runtime_pending_class}">${runtime_pending_count}</div>
      </div>
    </section>

    <section class="grid">
      <div class="panel">
        <h2>Next For You</h2>
        <p><strong>Item ${next_user_item}: ${next_user_feature}</strong></p>
        <p><code>${next_user_action}</code></p>
        <p class="muted">${next_user_why}</p>
      </div>
      <div class="panel">
        <h2>Next PM Agent Item</h2>
        <p><strong>Item ${next_agent_item}: ${next_agent_feature}</strong></p>
        <p><code>${next_agent_action}</code></p>
        <p class="muted">${next_agent_why}</p>
      </div>
      <div class="panel">
        <h2>Runtime Messages</h2>
        <ul>
$(runtime_messages_html)
        </ul>
      </div>
    </section>

    <section class="panel wide">
      <h2>Worktree State</h2>
      <table>
        <thead>
          <tr>
            <th>Worktree</th>
            <th>HEAD</th>
            <th>State</th>
            <th>Dirty</th>
            <th>Detail</th>
          </tr>
        </thead>
        <tbody>
$(worktree_rows_html)
        </tbody>
      </table>
    </section>

    <section class="panel wide">
      <h2>Prototype Links</h2>
      <div class="prototype-list">
$(prototype_groups_html)
      </div>
    </section>

    <section class="grid">
      <div class="panel">
        <h2>Recent Commits</h2>
        <ul>
$(recent_commits_html)
        </ul>
      </div>
      <div class="panel">
        <h2>Source Files</h2>
        <ul>
          <li><a href="$(file_url "$ROADMAP_DIR/next-actions.md")">Roadmap next actions</a></li>
        </ul>
      </div>
    </section>

    <section class="panel wide">
      <h2>Roadmap Stages</h2>
      <table>
        <thead>
          <tr>
            <th>Item</th>
            <th>Feature</th>
            <th>Stage</th>
            <th>Status</th>
            <th>Owner</th>
            <th>Folder</th>
          </tr>
        </thead>
        <tbody>
$(stage_rows_html)
        </tbody>
      </table>
    </section>
  </main>
</body>
</html>
HTML

echo "Wrote $OUT"
