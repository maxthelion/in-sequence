#!/usr/bin/env bash
set -euo pipefail
ROOT="Resources/StarterSamples"
OUT="$ROOT/manifest.json"
VERSION=${VERSION:-$(git describe --tags --always 2>/dev/null || echo "unknown")}

python3 - "$ROOT" "$VERSION" <<'PY' > "$OUT"
import hashlib, json, os, sys
root = sys.argv[1]
version = sys.argv[2]
entries = {}
for dirpath, _, filenames in os.walk(root):
    for fname in sorted(filenames):
        if fname == "manifest.json":
            continue
        if not fname.lower().endswith((".wav", ".aif", ".aiff", ".caf")):
            continue
        full = os.path.join(dirpath, fname)
        rel = os.path.relpath(full, root)
        with open(full, "rb") as f:
            h = hashlib.sha256(f.read()).hexdigest()
        entries[rel] = h
print(json.dumps({"files": entries, "version": version}, indent=2, sort_keys=True))
PY

echo "Wrote $OUT"
