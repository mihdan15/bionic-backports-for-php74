#!/usr/bin/env bash
# Pin the current php7.4 source package from deb.sury.org into pins/<label>/.
# A copy of Sury's signed index is kept with the pin, so the pin can be re-verified
# later, even after Sury publishes a newer revision.
#
# Usage: scripts/pin-sources.sh <label> [dist]
#   e.g. scripts/pin-sources.sh 7.4.33-31 bookworm
set -euo pipefail
LABEL=${1:?label, e.g. 7.4.33-31}
DIST=${2:-bookworm}
SURY_KEY_FPR=15058500A0235D97F5D10063B188E2B695BD4743
BASE=https://packages.sury.org/php
PY=${PYTHON:-python3}
OUT=pins/$LABEL

[ ! -e "$OUT" ] || { echo "$OUT already exists" >&2; exit 1; }
mkdir -p "$OUT"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$BASE/apt.gpg" -o "$tmp/sury.gpg"
mkdir "$tmp/gnupg" && chmod 700 "$tmp/gnupg" 2>/dev/null || true
fpr=$(gpg --homedir "$tmp/gnupg" --no-default-keyring --keyring "$tmp/sury.gpg" --with-colons --fingerprint 2>/dev/null \
    | awk -F: '/^fpr/ {print $10; exit}')
[ "$fpr" = "$SURY_KEY_FPR" ] || { echo "unexpected Sury key fingerprint: $fpr" >&2; exit 1; }

curl -fsSL "$BASE/dists/$DIST/InRelease" -o "$OUT/InRelease"
curl -fsSL "$BASE/dists/$DIST/main/source/Sources.gz" -o "$OUT/Sources.gz"
gpgv --keyring "$tmp/sury.gpg" "$OUT/InRelease" 2>&1 | grep -q 'Good signature' \
    || { echo "InRelease signature check failed" >&2; exit 1; }
want=$(awk '/^SHA256:/ {x=1; next} /^[A-Za-z]/ {x=0} x && $3 == "main/source/Sources.gz" {print $1}' "$OUT/InRelease")
[ "$(sha256sum "$OUT/Sources.gz" | cut -d' ' -f1)" = "$want" ] \
    || { echo "Sources.gz does not match InRelease" >&2; exit 1; }

# The newest php7.4 stanza: version, pool directory and file hashes.
"$PY" - "$OUT/Sources.gz" <<'PY' | tr -d '\r' > "$tmp/stanza"
import gzip, sys
stanzas = gzip.open(sys.argv[1], "rt", encoding="utf-8").read().split("\n\n")
php = [s for s in stanzas if s.startswith("Package: php7.4\n")]
if not php:
    sys.exit("php7.4 not found in Sources")
fields, files, cur = {}, [], None
for line in php[-1].splitlines():
    if line.startswith(" ") and cur == "Checksums-Sha256":
        sha, _size, name = line.split()
        files.append((sha, name))
    elif ":" in line and not line.startswith(" "):
        cur, _, value = line.partition(":")
        fields[cur] = value.strip()
print("VERSION", fields["Version"])
print("DIRECTORY", fields["Directory"])
for sha, name in files:
    print("FILE", sha, name)
PY

version=$(awk '$1 == "VERSION" {print $2}' "$tmp/stanza")
directory=$(awk '$1 == "DIRECTORY" {print $2}' "$tmp/stanza")
awk '$1 == "FILE" {print $2 "  " $3}' "$tmp/stanza" > "$OUT/sources.sha256"
php_version=$(sed -n 's/.*php7\.4_\([0-9.]*\)\.orig\.tar\.xz$/\1/p' "$OUT/sources.sha256")

cat > "$OUT/pin.env" <<ENV
# Pinned $(date -u +%Y-%m-%d) from $BASE/dists/$DIST
PHP_VERSION='$php_version'
SURY_DIST='$DIST'
SURY_VERSION='$version'
SURY_POOL_URL='$BASE/$directory'
SURY_KEY_FPR='$SURY_KEY_FPR'
# Fill in after reviewing the Sury changelog for the security fix this pin is for:
UPSTREAM_REPO='php/php-src'
UPSTREAM_PATCH_COMMIT=''
CVE_PATCH=''
ENV
echo "pinned $version ($(wc -l < "$OUT/sources.sha256") files) into $OUT"
