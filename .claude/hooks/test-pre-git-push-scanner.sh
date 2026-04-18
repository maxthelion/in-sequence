#!/usr/bin/env bash
# Black-box test for pre-git-push-scanner.py. Feeds hook-shaped JSON on
# stdin and asserts FIRE vs SKIP. Does NOT invoke xcodebuild — exercises
# only the parser path of pre-git-push.sh.
#
# Run locally: bash .claude/hooks/test-pre-git-push-scanner.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$HERE/pre-git-push-scanner.py"

if [ ! -f "$SCANNER" ]; then
  echo "scanner not found at $SCANNER" >&2
  exit 2
fi

PASS=0
FAIL=0

assert() {
  local expected="$1" cmd="$2"
  local json got kind
  json="$(/usr/bin/python3 -c 'import json,sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$cmd")"
  got="$(printf '%s' "$json" | /usr/bin/python3 "$SCANNER")"
  kind="${got%% *}"
  if [ "$kind" = "$expected" ]; then
    printf "  PASS %-6s %s\n" "$got" "$cmd"
    PASS=$((PASS + 1))
  else
    printf "  FAIL expected=%-4s got=%-10s cmd=%s\n" "$expected" "$got" "$cmd"
    FAIL=$((FAIL + 1))
  fi
}

echo "# FIRE cases (real git push invocations)"
assert FIRE 'git push'
assert FIRE 'git push origin main'
assert FIRE 'git push --force'
assert FIRE 'echo done && git push origin main'
assert FIRE 'echo safe; git push origin main'
assert FIRE '(git push origin main)'
assert FIRE 'bash -c "git push origin main"'
assert FIRE 'sh -c "git push"'
assert FIRE 'sudo git push origin main'
assert FIRE 'GIT_DIR=/tmp/foo git push origin main'
assert FIRE 'FOO=bar BAZ=qux git push'
assert FIRE 'true || git push'
assert FIRE 'false | git push'
assert FIRE 'git push --dry-run'
assert FIRE 'git push origin main --dry-run'
assert FIRE 'git push --help'

echo ""
echo "# SKIP cases (no real git push)"
assert SKIP 'echo "git push in a string"'
assert SKIP "echo 'git push in singles'"
assert SKIP 'echo hello'
assert SKIP 'git status'
assert SKIP 'grep "git push" README.md'
assert SKIP '# git push'
assert SKIP 'echo no push here'
assert SKIP 'ls -la'
assert SKIP 'git pull origin main'

echo ""
echo "# Results: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
