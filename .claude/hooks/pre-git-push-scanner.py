#!/usr/bin/env python3
"""Scan a Bash-tool command for a real `git push` invocation.

Invoked by pre-git-push.sh with the hook JSON on stdin. Emits one line:

    FIRE <rest-args-of-push-statement>    if a real git push is present
    SKIP                                   otherwise

Detection runs two passes, logically OR'd:

1. **Shlex-based token scan.** Handles compound commands (``&&``, ``||``,
   ``;``, ``|``, subshell parens, braces), env-var prefixes (``FOO=bar``),
   prefix words that pass through (``sudo``, ``exec``, ``command``, ``env``,
   ``time``, ``nice``, ``nohup``), and recursive invocations
   (``bash -c "…"``, ``sh -c``, ``zsh -c``, ``eval "…"``). This pass also
   extracts the rest-args of the push statement so the outer hook can honour
   ``--dry-run`` / ``--help``.
2. **Boundary-aware regex.** A fallback that catches forms the token scan
   can't easily parse: heredocs (``bash <<EOF\\ngit push\\nEOF``), backtick
   command substitution, newline-separated statements, unbalanced-quote
   commands shlex rejects. Regex cannot extract rest-args reliably — if this
   is the only pass that fires, rest-args is empty (and the ``--dry-run``
   check treats the push conservatively, i.e. runs tests).

The two-pass design is documented in the project's code-review-checklist
"enumerate the surface" rule — the structure here *is* the test table.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import sys


# Matches ``VAR=value`` at a statement boundary. Assignment semantics
# apply only to that one command: ``FOO=bar git push`` runs ``git push``
# with ``FOO=bar`` exported.
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# Statement-boundary tokens as emitted by ``shlex.split`` after
# ``space_operators`` has spaced them out.
BOUNDARIES = {"&&", "||", ";", "|", "&", "(", ")", "{", "}"}

# Prefix words that delegate to the remaining command preserving semantics.
# Treated the same as ``VAR=val`` — skip them at a boundary.
PREFIX_SKIP = {"sudo", "exec", "command", "env", "time", "nice", "nohup"}

# Words that take ``-c "inner"`` and re-execute the inner string as a shell
# command. Recurse into the inner string.
SHELL_RECURSE = {"bash", "sh", "zsh", "dash", "ksh"}

# Words that take remaining args and re-evaluate them as a shell command.
# Recurse into the joined args (up to the next statement boundary).
EVAL_LIKE = {"eval"}

# Boundary-aware regex probe. Matches ``git push`` where the preceding
# character is a boundary (start of string, whitespace — including newline —
# or a shell metachar we recognise) AND the following character is a
# boundary. The ``\n`` inclusion is what catches heredoc bodies; the
# backtick inclusion catches command substitution. We do NOT include ``"``
# or ``'`` — in-string occurrences must stay SKIP.
BOUNDARY_RE = re.compile(
    r"(?:^|[\s;&|({`])git\s+push(?:\s|$|[;&|)}`])"
)


def space_operators(s: str) -> str:
    """Insert spaces around shell operators at top level (outside quotes) so
    ``shlex.split`` treats them as standalone tokens.

    Operator set: ``&&``, ``||``, ``;``, ``|``, ``&``, ``(``, ``)``, ``{``,
    ``}``, backtick, newline. Without this step ``;git push`` and
    ``(git push`` arrive as fused tokens, backticks survive as part of
    a token, and multi-statement scripts collapse to one."""
    out = []
    in_single = in_double = False
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == "'" and not in_double:
            in_single = not in_single
            out.append(ch)
            i += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            out.append(ch)
            i += 1
            continue
        if in_single or in_double:
            out.append(ch)
            i += 1
            continue
        two = s[i:i + 2]
        if two in ("&&", "||"):
            out.append(" " + two + " ")
            i += 2
            continue
        if ch in ";|&(){}`\n":
            out.append(" " + ch + " ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def strip_comments(s: str) -> str:
    """Drop anything after an unquoted ``#``."""
    out = []
    in_single = in_double = False
    for ch in s:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not (in_single or in_double):
            break
        out.append(ch)
    return "".join(out).strip()


def _scan_tokens(tokens: list[str]) -> tuple[bool, str]:
    """Walk the token list looking for `git push` at a statement boundary."""
    n = len(tokens)
    i = 0
    at_boundary = True  # first position is a boundary
    while i < n:
        if at_boundary:
            # Skip env-var assignments and transparent prefix words.
            while i < n and (ENV_ASSIGN.match(tokens[i]) or tokens[i] in PREFIX_SKIP):
                i += 1
            if i >= n:
                break

            tok = tokens[i]
            if tok == "git" and i + 1 < n and tokens[i + 1] == "push":
                trimmed = []
                for t in tokens[i + 2:]:
                    if t in BOUNDARIES:
                        break
                    trimmed.append(t)
                return (True, " ".join(trimmed))

            # bash -c "inner" / sh -c "inner" / zsh -c "inner" → recurse.
            if tok in SHELL_RECURSE:
                j = i + 1
                while j < n and tokens[j].startswith("-") and tokens[j] != "-c":
                    j += 1
                if j < n and tokens[j] == "-c" and j + 1 < n:
                    found, rest = find_push(tokens[j + 1])
                    if found:
                        return (True, rest)

            # eval <args…> → concat up to next boundary, recurse.
            if tok in EVAL_LIKE:
                args = []
                j = i + 1
                while j < n and tokens[j] not in BOUNDARIES:
                    args.append(tokens[j])
                    j += 1
                if args:
                    found, rest = find_push(" ".join(args))
                    if found:
                        return (True, rest)

        tok = tokens[i]
        at_boundary = tok in BOUNDARIES
        i += 1

    return (False, "")


def find_push(source: str) -> tuple[bool, str]:
    """Return (found, rest_args) for the first real git push in source.

    Runs both passes: the shlex token scan first (precise; can extract
    rest-args), then the boundary regex (coarser; catches heredocs, backticks,
    newlines, unbalanced-quote commands). Token result wins if it fires.
    """
    source = strip_comments(source)
    if not source:
        return (False, "")

    token_result: tuple[bool, str] = (False, "")
    try:
        tokens = shlex.split(space_operators(source), posix=True)
    except ValueError:
        tokens = None
    if tokens is not None:
        token_result = _scan_tokens(tokens)
        if token_result[0]:
            return token_result

    # Fallback: boundary regex on the raw source. Empty rest — downstream
    # will conservatively run tests rather than honour --dry-run.
    if BOUNDARY_RE.search(source):
        return (True, "")

    return (False, "")


def main() -> int:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        print("SKIP")
        return 0
    cmd = (payload.get("tool_input", {}) or {}).get("command", "") or ""
    found, rest = find_push(cmd)
    if found:
        print("FIRE " + rest)
    else:
        print("SKIP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
