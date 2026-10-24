#!/bin/bash
# Build Sury's php7.4 source package for an older Ubuntu or Debian release.
#
# Derived from build.sh in https://github.com/Niek/php7
# (MIT License, Copyright (c) 2026 php7 contributors; see NOTICE.md).
# Changes: own package version suffix and maintainer identity, base version read from
# the .dsc, and a pin check at the start.
#
# Runs as root inside a container (or chroot) of the target release, with:
#   /pin      the pin directory (read-only)
#   /sources  the pin's source files, verified by scripts/verify-sources.sh (read-only)
#   /out      receives the packages
# Environment: TARGET (e.g. ubuntu18.04, required), REVISION (default 1), JOBS (default 2),
#              PKG_SUFFIX (default legacy), MAINTAINER_NAME, MAINTAINER_EMAIL
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck disable=SC1091
. /etc/os-release
codename=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
: "${TARGET:?set TARGET, e.g. ubuntu18.04}"
REVISION=${REVISION:-1}
JOBS=${JOBS:-2}
PKG_SUFFIX=${PKG_SUFFIX:-legacy}
MAINTAINER_NAME=${MAINTAINER_NAME:-bionic-backports-for-php74 maintainers}
MAINTAINER_EMAIL=${MAINTAINER_EMAIL:-noreply@example.invalid}

if [ "$ID" = debian ]; then
  [ "$VERSION_ID" != 9 ] || codename=stretch
  printf '%s\n' "deb http://archive.debian.org/debian $codename main" \
    "deb http://archive.debian.org/debian-security $codename/updates main" > /etc/apt/sources.list
  echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive
else
  case "$VERSION_ID" in
    16.04|18.04|20.04) ;;
    *)
      for pocket in "$codename" "$codename-updates" "$codename-security" "$codename-backports"; do
        echo "deb http://old-releases.ubuntu.com/ubuntu $pocket main universe restricted multiverse"
      done > /etc/apt/sources.list
      ;;
  esac
fi
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get update
apt-get install -y --no-install-recommends build-essential devscripts equivs dpkg-dev ca-certificates

mkdir -p /build /out
cd /sources
sha256sum -c /pin/sources.sha256
dpkg-source --no-check -x ./*.dsc /build/php
cd /build/php

# The optional telemetry header uses newer libsodium APIs even when telemetry
# is disabled. Guard it the same way as its call sites; security patches stay intact.
sed -i 's/#include "secure_dns_telemetry.h"/#ifdef TELEMETRY_HOST\n#include "secure_dns_telemetry.h"\n#endif/' \
  sapi/apache2handler/php_functions.c sapi/fpm/fpm/fpm_main.c

# Keep Sury's packaging, including extensions, FPM units, pools and maintainer
# scripts. Adjust only compatibility with the target's native build tools/libs.
sed -i 's/php-common (>= 1:81~)/php-common (>= 1:35)/g' debian/control debian/control.in debian/php-module.control.in
if [ "$VERSION_ID" = 16.04 ]; then
  apt-get install -y --no-install-recommends -t xenial-backports debhelper
fi
# Use bundled PCRE2 where the distro predates PHP 7.4's required library API.
pcre_version=$(apt-cache policy libpcre2-dev | awk '/Candidate:/ {print $2}')
if dpkg --compare-versions "$pcre_version" lt 10.30; then
  sed -i '/libpcre2-dev (>= 10.30),/d' debian/control debian/control.in
  sed -i '/--with-external-pcre/d' debian/rules
fi
argon_version=$(apt-cache policy libargon2-dev libargon2-0-dev | awk '/Candidate:/ && $2 != "(none)" {version=$2} END {print version}')
if [ -z "$argon_version" ] || dpkg --compare-versions "$argon_version" lt '0~20161029'; then
  sed -i '/libargon2-dev | libargon2-0-dev,/d' debian/control debian/control.in
  sed -i '/--with-password-argon2=/d' debian/rules
fi
# PHP also supports legacy HTML Tidy, detected by its configure script.
sed -i 's/libtidy-dev (>= 1:5.2.0)/libtidy-dev/' debian/control debian/control.in

export DEB_BUILD_OPTIONS="nocheck parallel=$JOBS"
export DEB_BUILD_PROFILES=nocheck
export DEBFULLNAME="$MAINTAINER_NAME" DEBEMAIL="$MAINTAINER_EMAIL"
base=$(dpkg-parsechangelog -S Version)
base=${base%%+0~*}
dch --newversion "${base}+${PKG_SUFFIX}${REVISION}~${TARGET}.1" --distribution "$codename" \
  "Rebuild of Sury's php7.4 ${base} for ${TARGET}."
mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
dpkg-buildpackage -us -uc -b -j"$JOBS"
cp /build/*.deb /out/
find /build -maxdepth 1 -type f \( -name '*.buildinfo' -o -name '*.changes' \) -exec cp {} /out/ \;
dpkg-query -W -f='${binary:Package}\t${Version}\n' > /out/build-dependencies.txt
cd /out
sha256sum ./*.deb > SHA256SUMS
