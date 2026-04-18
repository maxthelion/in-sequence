# Critical: unbalanced-quote fallback false-FIREs on any string containing "git push"

**File:** `.claude/hooks/pre-git-push-scanner.py`, lines 88–91 (fallback branch in `find_push`)
**Severity:** Critical

## What's wrong

```python
try:
    tokens = shlex.split(space_operators(source), posix=True)
except ValueError:
    return ("git push" in source, "")
```

Any `shlex.ValueError` (e.g. unclosed quote) falls back to a raw substring probe. Examples that false-FIRE today:

- `echo "git push` — unclosed double quote. Returns FIRE.
- `echo "this hook rejects git push"` — benign description. If a stray quote appears (typo, truncation, copy-paste), it falls back and fires.

Consequence: a harmless `echo` or `printf` describing the hook triggers a 30-second `xcodebuild test` and blocks the bash call. UX regression.

## What would be right

On `shlex.ValueError`, apply a boundary-aware regex instead of substring:

```python
BOUNDARY_RE = re.compile(r'(?:^|[\s;&|({`\n])git\s+push(?:\s|$|[;&|)}\n])')
return (bool(BOUNDARY_RE.search(source)), "")
```

Still conservative (fires on typos that look like a real push) but rejects the in-string case. If a fresh Claude lands and edits this regex, keep the boundary classes in sync with `space_operators`.

## Acceptance

- `echo "git push` → SKIP (unclosed quote, no real push at a boundary).
- `echo "pushes via 'git push'"` → SKIP.
- `git push "unclosed` → FIRE (real push, despite the broken arg).
- `grep "git push" README.md` → SKIP.
