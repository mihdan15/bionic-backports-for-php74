#!/usr/bin/env bash
# Save the PHP 7.4 packages that are installed now as .deb files, before upgrading,
# so you can roll back even if the original packages are no longer downloadable.
# Run as root on the server. Needs dpkg-repack: apt-get install dpkg-repack
# Modified configuration files are saved as they are on disk.
#
# Usage: sudo tools/save-rollback-packages.sh [directory]
set -euo pipefail
dest=${1:-rollback-php7.4-$(date +%Y%m%d)}
command -v dpkg-repack > /dev/null || { echo "dpkg-repack is not installed" >&2; exit 1; }

packages=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null \
    | awk '$1 == "ii" {print $2}')
[ -n "$packages" ] || { echo "no installed php7.4 packages found" >&2; exit 1; }

mkdir -p "$dest"
cd "$dest"
# shellcheck disable=SC2086
dpkg-repack $packages
sha256sum ./*.deb > SHA256SUMS
echo "saved $(ls ./*.deb | wc -l) packages in $PWD"
echo "roll back with: apt-get install --allow-downgrades ./*.deb"
