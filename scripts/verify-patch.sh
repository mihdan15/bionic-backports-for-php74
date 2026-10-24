#!/usr/bin/env bash
# Compare the CVE patch shipped in Sury's packaging with the upstream php-src commit.
# Prints, per file, whether the added and removed lines are identical. Differences are
# expected where Sury already carries an earlier backport touching the same code;
# review them, and document them in the release notes.
# Usage: scripts/verify-patch.sh pins/7.4.33-31 work/sources
set -euo pipefail
PIN=$(cd "${1:?pin directory}" && pwd)
SRC=$(cd "${2:?source directory}" && pwd)
PY=${PYTHON:-python3}
. "$PIN/pin.env"
[ -n "$UPSTREAM_PATCH_COMMIT" ] && [ -n "$CVE_PATCH" ] || { echo "UPSTREAM_PATCH_COMMIT and CVE_PATCH must be set in pin.env" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tar -xJf "$SRC"/*.debian.tar.xz -C "$tmp"
[ -f "$tmp/debian/patches/$CVE_PATCH" ] || { echo "debian/patches/$CVE_PATCH not found" >&2; exit 1; }
curl -fsSL "https://github.com/$UPSTREAM_REPO/commit/$UPSTREAM_PATCH_COMMIT.diff" -o "$tmp/upstream.diff"

"$PY" - "$tmp/debian/patches/$CVE_PATCH" "$tmp/upstream.diff" <<'PY'
import collections, re, sys

def changed_lines(path):
    files, current = collections.defaultdict(collections.Counter), None
    for line in open(path, encoding="utf-8", errors="replace"):
        match = re.match(r"^\+\+\+ (?:b/)?(\S+)", line)
        if match:
            current = match.group(1)
        elif current and line[:1] in "+-" and not line.startswith("---"):
            files[current][line[0] + line[1:].rstrip()] += 1
    return files

sury, upstream = changed_lines(sys.argv[1]), changed_lines(sys.argv[2])
same = 0
for name in sorted((set(sury) | set(upstream)) - {"NEWS"}):
    a, b = sury.get(name, collections.Counter()), upstream.get(name, collections.Counter())
    if a == b:
        same += 1
        continue
    print(f"DIFFERS  {name}")
    for line in (a - b).elements():
        print(f"   only in Sury     {line[:120]}")
    for line in (b - a).elements():
        print(f"   only upstream    {line[:120]}")
print(f"{same} files identical to the upstream commit (NEWS ignored)")
PY
