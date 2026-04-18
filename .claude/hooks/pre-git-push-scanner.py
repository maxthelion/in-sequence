#!/usr/bin/env python3
"""Scan a Bash-tool command for a real `git push` invocation.

Invoked by pre-git-push.sh with the hook JSON on stdin. Emits one line:

    FIRE <rest-args-of-push-statement>    if a real git push is present
    SKIP                                   otherwise

A "real" git push is `git push` appearing at a shell statement boundary
(command start, after ``&&``/``||``/``;``/``|``/subshell, or inside a
recursive ``bash -c`` / ``sh -c`` string). Leading ``sudo`` and
``VAR=value`` env-var assignments at a boundary are skipped. Substring
occurrences inside strings/comments do NOT fire.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import sys


ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
BOUNDARIES = {"&&", "||", ";", "|", "&", "(", ")", "{", "}"}


def space_operators(s: str) -> str:
    """Insert spaces around shell operators at top level (outside quotes) so
    shlex.split treats them as standalone tokens. Without this, `;git push` and
    `(git push` arrive as fused tokens and the boundary check misses them."""
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
        if ch in ";|&(){}":
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


def find_push(source: str) -> tuple[bool, str]:
    """Return (found, rest_args) for the first real git push in source."""
    source = strip_comments(source)
    if not source:
        return (False, "")
    try:
        tokens = shlex.split(space_operators(source), posix=True)
    except ValueError:
        # Unbalanced quotes / exotic syntax — conservative: treat any
        # literal "git push" substring as a fire to avoid a silent bypass.
        return ("git push" in source, "")

    n = len(tokens)
    i = 0
    at_boundary = True  # first position is a boundary
    while i < n:
        if at_boundary:
            # Skip env-var assignments and sudo at a boundary.
            while i < n and (ENV_ASSIGN.match(tokens[i]) or tokens[i] == "sudo"):
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

            # bash -c "inner" / sh -c "inner" — recurse.
            if tok in ("bash", "sh", "zsh"):
                j = i + 1
                while j < n and tokens[j].startswith("-") and tokens[j] != "-c":
                    j += 1
                if j < n and tokens[j] == "-c" and j + 1 < n:
                    found, rest = find_push(tokens[j + 1])
                    if found:
                        return (True, rest)

        tok = tokens[i]
        at_boundary = tok in BOUNDARIES
        i += 1

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
