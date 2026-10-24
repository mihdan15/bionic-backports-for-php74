#!/usr/bin/env bash
# Verify a pin's source files three independent ways before building:
#   1. against the hashes in the pin
#   2. the upstream tarball against php.net's published checksum
#   3. against Sury's GPG-signed index saved with the pin
# Usage: scripts/verify-sources.sh pins/7.4.33-31 work/sources
set -euo pipefail
PIN=$(cd "${1:?pin directory}" && pwd)
SRC=$(cd "${2:?source directory}" && pwd)
PY=${PYTHON:-python3}
. "$PIN/pin.env"
fail() { echo "FAIL: $*" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "[1/3] files match the pinned hashes"
(cd "$SRC" && sha256sum -c --quiet "$PIN/sources.sha256") || fail "hash mismatch against the pin"

echo "[2/3] upstream tarball matches php.net"
orig=$(awk '/\.orig\.tar\.xz$/ {print $2}' "$PIN/sources.sha256")
want=$(curl -fsSL "https://www.php.net/releases/index.php?json&version=$PHP_VERSION" \
    | "$PY" -c "import json, sys; d = json.load(sys.stdin); print([s['sha256'] for s in d['source'] if s['filename'] == 'php-$PHP_VERSION.tar.xz'][0])" | tr -d '\r')
have=$(sha256sum "$SRC/$orig" | cut -d' ' -f1)
[ "$want" = "$have" ] || fail "$orig does not match php.net ($have != $want)"

echo "[3/3] files are listed in Sury's signed index ($SURY_DIST)"
curl -fsSL https://packages.sury.org/php/apt.gpg -o "$tmp/sury.gpg"
mkdir "$tmp/gnupg" && chmod 700 "$tmp/gnupg" 2>/dev/null || true
fpr=$(gpg --homedir "$tmp/gnupg" --no-default-keyring --keyring "$tmp/sury.gpg" --with-colons --fingerprint 2>/dev/null \
    | awk -F: '/^fpr/ {print $10; exit}')
[ "$fpr" = "$SURY_KEY_FPR" ] || fail "Sury key fingerprint $fpr is not the pinned $SURY_KEY_FPR"
gpgv --keyring "$tmp/sury.gpg" "$PIN/InRelease" 2>&1 | grep -q 'Good signature' || fail "InRelease signature"
idx=$(awk '/^SHA256:/ {x=1; next} /^[A-Za-z]/ {x=0} x && $3 == "main/source/Sources.gz" {print $1}' "$PIN/InRelease")
[ "$(sha256sum "$PIN/Sources.gz" | cut -d' ' -f1)" = "$idx" ] || fail "Sources.gz does not match InRelease"
"$PY" - "$PIN/Sources.gz" "$SURY_VERSION" <<'PY' | tr -d '\r' > "$tmp/index.sha256"
import gzip, sys
path, version = sys.argv[1], sys.argv[2]
for stanza in gzip.open(path, "rt", encoding="utf-8").read().split("\n\n"):
    lines = stanza.splitlines()
    if "Package: php7.4" in lines and f"Version: {version}" in lines:
        start = [l.rstrip() for l in lines].index("Checksums-Sha256:") + 1
        for line in lines[start:]:
            if not line.startswith(" "):
                break
            sha, _size, name = line.split()
            print(f"{sha}  {name}")
PY
[ -s "$tmp/index.sha256" ] || fail "$SURY_VERSION is not in the saved index"
(cd "$SRC" && sha256sum -c --quiet "$tmp/index.sha256") || fail "files do not match Sury's signed index"
cmp -s <(sort "$PIN/sources.sha256") <(sort "$tmp/index.sha256") || fail "the pin lists different files than Sury's index"

echo "OK: all $(wc -l < "$PIN/sources.sha256") source files verified"
