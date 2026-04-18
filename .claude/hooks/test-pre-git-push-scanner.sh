#!/usr/bin/env bash
# Black-box test for pre-git-push-scanner.py. Feeds hook-shaped JSON on
# stdin and asserts the full scanner output (both FIRE/SKIP decision AND
# rest-args). Does NOT invoke xcodebuild — exercises only the parser.
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

_run() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$1" \
    | /usr/bin/python3 "$SCANNER"
}

# assert_eq <expected-full-line> <cmd>
assert_eq() {
  local expected="$1" cmd="$2"
  local got
  got="$(_run "$cmd")"
  if [ "$got" = "$expected" ]; then
    printf "  PASS '%s'  <=  %s\n" "$got" "$cmd"
    PASS=$((PASS + 1))
  else
    printf "  FAIL expected='%s' got='%s' cmd=%s\n" "$expected" "$got" "$cmd"
    FAIL=$((FAIL + 1))
  fi
}

# assert_kind <expected-first-token> <cmd>
# (for cases where rest-args is intentionally unchecked — e.g. regex-only hits)
assert_kind() {
  local expected="$1" cmd="$2"
  local got kind
  got="$(_run "$cmd")"
  kind="${got%% *}"
  if [ "$kind" = "$expected" ]; then
    printf "  PASS %-6s (kind only)  <=  %s\n" "$got" "$cmd"
    PASS=$((PASS + 1))
  else
    printf "  FAIL expected=%s got='%s' cmd=%s\n" "$expected" "$got" "$cmd"
    FAIL=$((FAIL + 1))
  fi
}

echo "# FIRE cases — token scan (precise; full output including rest-args)"
assert_eq 'FIRE '                   'git push'
assert_eq 'FIRE origin main'        'git push origin main'
assert_eq 'FIRE --force'            'git push --force'
assert_eq 'FIRE origin main'        'echo done && git push origin main'
assert_eq 'FIRE origin main'        'echo safe; git push origin main'
assert_eq 'FIRE origin main'        '(git push origin main)'
assert_eq 'FIRE origin main'        'bash -c "git push origin main"'
assert_eq 'FIRE '                   'sh -c "git push"'
assert_eq 'FIRE origin main'        'sudo git push origin main'
assert_eq 'FIRE origin main'        'GIT_DIR=/tmp/foo git push origin main'
assert_eq 'FIRE '                   'FOO=bar BAZ=qux git push'
assert_eq 'FIRE '                   'true || git push'
assert_eq 'FIRE '                   'false | git push'
assert_eq 'FIRE --dry-run'          'git push --dry-run'
assert_eq 'FIRE origin main --dry-run' 'git push origin main --dry-run'
assert_eq 'FIRE --help'             'git push --help'
# New: eval / command / exec / env / time prefixes
assert_eq 'FIRE origin main'        'eval "git push origin main"'
assert_eq 'FIRE '                   'eval git push'
assert_eq 'FIRE origin main'        'command git push origin main'
assert_eq 'FIRE origin main'        'exec git push origin main'
assert_eq 'FIRE '                   'env FOO=bar git push'
assert_eq 'FIRE '                   'time git push'
assert_eq 'FIRE '                   'nice git push'

echo ""
echo "# FIRE cases — regex fallback (kind-only; rest-args is empty)"
# Backtick command substitution
assert_kind FIRE '`git push`'
assert_kind FIRE 'echo `git push`'
# Newline-separated statement
assert_kind FIRE $'echo hi\ngit push'
# Heredoc body
assert_kind FIRE $'bash <<EOF\ngit push\nEOF'

echo ""
echo "# SKIP cases (no real git push)"
assert_eq 'SKIP' 'echo "git push in a string"'
assert_eq 'SKIP' "echo 'git push in singles'"
assert_eq 'SKIP' 'echo hello'
assert_eq 'SKIP' 'git status'
assert_eq 'SKIP' 'grep "git push" README.md'
assert_eq 'SKIP' '# git push'
assert_eq 'SKIP' 'echo no push here'
assert_eq 'SKIP' 'ls -la'
assert_eq 'SKIP' 'git pull origin main'
# Unbalanced-quote cases — shlex fails, regex fallback must honour boundaries
assert_eq 'SKIP' 'echo "git push'
assert_eq 'SKIP' 'echo "pushes via git push"'

echo ""
echo "# Results: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
