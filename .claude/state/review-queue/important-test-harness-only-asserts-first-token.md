# Important: pre-git-push-scanner test harness doesn't validate rest-args

**File:** `.claude/hooks/test-pre-git-push-scanner.sh`, lines 21–32 (`assert` function)
**Severity:** Important

## What's wrong

```bash
got="$(printf '%s' "$json" | /usr/bin/python3 "$SCANNER")"
kind="${got%% *}"
if [ "$kind" = "$expected" ]; then ...
```

The harness parses only the first whitespace-delimited token (`FIRE` or `SKIP`). If the scanner returns `FIRE` with the wrong rest-args (missing `origin`, including next-statement tokens, emitting redirectors like `<<<`), the test still passes.

Concretely: if I extended the scanner to handle here-strings (`<<<`), the test would accept `FIRE <<<` as a pass. The `--dry-run` pass-through logic in `pre-git-push.sh` depends on rest-args being accurate; a scanner that lies about rest-args silently breaks the hook.

## What would be right

Each FIRE case should declare the expected rest-args; assert full-line equality:

```bash
assert_fire() {
  local expected_rest="$1" cmd="$2"
  local json got
  json="$(… json-encode cmd …)"
  got="$(printf '%s' "$json" | /usr/bin/python3 "$SCANNER")"
  if [ "$got" = "FIRE $expected_rest" ]; then PASS; else FAIL; fi
}

assert_fire 'origin main' 'git push origin main'
assert_fire '--dry-run'   'git push --dry-run'
assert_fire ''            'git push'
...
```

Keep the SKIP-case assertion as-is (`got == "SKIP"`).

## Acceptance

- Every FIRE case specifies expected rest-args exactly.
- Wrong rest-args cause a test failure.
