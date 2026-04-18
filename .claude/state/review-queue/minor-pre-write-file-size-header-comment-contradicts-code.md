# Minor: pre-write-file-size.sh header comment contradicts implementation

**File:** `.claude/hooks/pre-write-file-size.sh`, lines 5–12
**Severity:** Minor

## What's wrong

The top-of-file comment says:

```
# For Edit:  uses the current file size (lines) as a lower bound — catches
#            already-too-large files; doesn't prevent a single edit from
#            pushing a file from 999→1001 but that's fine, the next edit
#            will catch it. (A full simulate-the-edit path is not worth the
#            complexity; ...)
```

But the Python below **does** simulate the edit (it opens the file, applies
`body.replace(old, new, 1)` or with `replace_all`, and counts lines of the
result). Verified manually: an Edit that inserts 1100 padding lines on a
95-line file reports "would be 1195 lines" and blocks.

The comment describes an older, simpler design. Reader of the file gets a
false mental model.

## What would be right

Rewrite the comment to match what the code does:

```
# For Write: uses the proposed `content` directly.
# For Edit:  reads the current file, applies the old_string→new_string
#            replacement (honouring replace_all), and counts lines of the
#            simulated result. If the file is unreadable (e.g. target
#            doesn't exist yet), fail open.
```

## Acceptance

- Comment matches behaviour visible in the Python block.
