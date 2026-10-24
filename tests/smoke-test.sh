#!/bin/bash
# Install the built packages in a clean container of the target release and check
# that PHP starts, has its usual modules, and was built without telemetry.
# Runs as root with the build results mounted at /out.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get update -qq

packages="php7.4-cli php7.4-fpm php7.4-common php7.4-json php7.4-opcache php7.4-readline php7.4-curl
php7.4-gd php7.4-mbstring php7.4-mysql php7.4-xml php7.4-zip php7.4-soap php7.4-intl php7.4-sqlite3
php7.4-bcmath libapache2-mod-php7.4"
files=()
for p in $packages; do files+=(/out/"${p}"_*.deb); done
apt-get install -y -qq "${files[@]}" > /tmp/install.log 2>&1 || { tail -20 /tmp/install.log; exit 1; }

failed=0
check() {
    if eval "$2" > /dev/null 2>&1; then echo "ok    $1"; else echo "FAIL  $1"; failed=1; fi
}
check "php -v reports 7.4.33" "php -v | head -1 | grep -q '^PHP 7\.4\.33 '"
check "php-fpm configuration test" "php-fpm7.4 -t"
for m in bcmath curl dom gd intl json mbstring mysqli openssl pdo_mysql pdo_sqlite soap sodium xml zip 'Zend OPcache'; do
    check "module: $m" "php -m | grep -qx '$m'"
done
cat > /tmp/smoke.php <<'PHP'
<?php
$ok = json_decode(json_encode(['ä']))[0] === 'ä'
    && mb_strlen('äb') === 2
    && strlen(hash('sha256', 'x')) === 64
    && function_exists('sodium_crypto_box_keypair')
    && function_exists('imagecreatetruecolor')
    && function_exists('curl_init')
    && class_exists('ZipArchive') && class_exists('SoapClient') && class_exists('DOMDocument')
    && password_verify('secret', password_hash('secret', PASSWORD_DEFAULT));
exit($ok ? 0 : 1);
PHP
check "runtime: json, mbstring, hash, sodium, gd, curl, zip, soap, dom, password" "php /tmp/smoke.php"
check "no telemetry compiled in" "! grep -qai telemetry /usr/sbin/php-fpm7.4 /usr/bin/php7.4 /usr/lib/apache2/modules/libphp7.4.so"
exit $failed
