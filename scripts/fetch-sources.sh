#!/usr/bin/env bash
# Download the files of a pin from deb.sury.org.
# Usage: scripts/fetch-sources.sh pins/7.4.33-31 work/sources
set -euo pipefail
PIN=${1:?pin directory}
DEST=${2:?destination directory}
. "$PIN/pin.env"

mkdir -p "$DEST"
while read -r _ file; do
    curl -fsSL --retry 3 "$SURY_POOL_URL/$file" -o "$DEST/$file"
done < "$PIN/sources.sha256"
echo "downloaded $(wc -l < "$PIN/sources.sha256") files into $DEST"
