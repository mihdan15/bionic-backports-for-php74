# bionic-backports-for-php74

Unofficial rebuilds of the `php7.4` packages from [deb.sury.org](https://deb.sury.org) for
**Ubuntu 18.04 (bionic)**. They include Sury's backports of the fixes for
**CVE-2026-109618** and **CVE-2026-109619** (remote code execution, CVSS 9.8), which upstream
PHP fixed in 8.2.35, 8.3.36, 8.4.27 and 8.5.12.

> [!WARNING]
> PHP 7.4 and Ubuntu 18.04 are end-of-life. These packages buy time for an upgrade; they are
> not long-term security support. This project is not affiliated with the PHP Group or with
> deb.sury.org.

## Who this is for

Servers that run PHP 7.4 from the `ondrej/php` PPA on Ubuntu 18.04. That PPA no longer
publishes packages for 18.04, so `apt` cannot deliver these fixes.

## Install

1. Download `php7.4-ubuntu18.04-amd64.tar.xz` and `SHA256SUMS` from a
   [release](../../releases). Pick a specific tag; don't script the `latest` URL.
2. Check where the file was built and that it is intact (needs the GitHub CLI):

   ```
   gh attestation verify php7.4-ubuntu18.04-amd64.tar.xz --repo mihdan15/bionic-backports-for-php74
   sha256sum -c --ignore-missing SHA256SUMS
   ```

3. Save the PHP packages you have now, so you can roll back:

   ```
   sudo apt-get install dpkg-repack
   sudo bash tools/save-rollback-packages.sh
   ```

4. Extract, simulate, and upgrade only the PHP 7.4 packages that are already installed:

   ```
   mkdir php7.4 && tar -xJf php7.4-ubuntu18.04-amd64.tar.xz -C php7.4 && cd php7.4
   sha256sum -c SHA256SUMS
   sudo apt-get install -s --only-upgrade ./*.deb
   sudo DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1 apt-get install -y --only-upgrade \
     -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold ./*.deb
   sudo systemctl restart php7.4-fpm apache2
   php -v
   ```

   The simulation should upgrade only `php7.4` packages and remove nothing.

### What to expect

- **Restart Apache yourself.** The upgrade restarts PHP-FPM, but Apache keeps the old
  `mod_php` in memory until it is restarted.
- **Your configuration is kept.** With `--force-confold`, files you changed stay as they are.
  Files you never changed, such as `php-fpm.conf`, get the new defaults. The new
  `php-fpm.conf` comments out the `pid` line; this is harmless because the systemd unit tracks
  the process itself.
- **`php.ini` is kept.** The new defaults are saved next to it as `php.ini.ucf-dist`.
- **No telemetry.** Sury's optional DNS telemetry code is not compiled into these builds.
- **Not included:** third-party (PECL) extensions.

## Roll back

```
cd rollback-php7.4-YYYYMMDD
sudo apt-get install --allow-downgrades ./*.deb
sudo systemctl restart php7.4-fpm apache2
```

## How the packages are made

Every release is built by GitHub Actions from a pin in `pins/`:

1. **Pin.** `scripts/pin-sources.sh` records Sury's source package and keeps a copy of Sury's
   GPG-signed index (`InRelease` and `Sources.gz`), so the pin can be checked again later.
2. **Verify the sources.** `scripts/verify-sources.sh` checks the files three ways: against the
   pin, the PHP tarball against php.net's published checksum, and every file against Sury's
   signed index (key `1505 8500 A023 5D97 F5D1 0063 B188 E2B6 95BD 4743`).
3. **Verify the fix.** `scripts/verify-patch.sh` compares Sury's CVE patch with the upstream
   php-src commit and prints any differences.
4. **Build.** `build/build.sh` builds Sury's packaging in a clean `ubuntu:18.04` container,
   with only small compatibility changes for the older toolchain.
5. **Test.** `tests/smoke-test.sh` installs the packages in a fresh container and checks the
   version, the modules, a short runtime script, and that no telemetry is compiled in.
6. **Release.** The packages are published with `SHA256SUMS` and a build provenance attestation.

You can repeat steps 2 and 3 yourself:

```
bash scripts/fetch-sources.sh pins/7.4.33-31 work/sources
bash scripts/verify-sources.sh pins/7.4.33-31 work/sources
bash scripts/verify-patch.sh pins/7.4.33-31 work/sources
```

### Known patch differences in pin 7.4.33-31

Sury's `0164-Avoid-state-corruption-via-bailout.patch` matches upstream commit `712e60f9` in
15 of 17 files. In `main/main.c` and `main/rfc1867.c` it leaves out lines that Sury's packaging
already has from earlier backports: the `max_multipart_body_parts` limit (CVE-2023-0662,
patch `0062`) and an `isspace()` cast.

## Maintaining

When Sury publishes a new `php7.4` revision:

1. Pin it: `bash scripts/pin-sources.sh 7.4.33-32 bookworm`.
2. Read Sury's changelog. For a security fix, set `UPSTREAM_PATCH_COMMIT` and `CVE_PATCH` in
   the new `pin.env`.
3. Point `PIN` in `.github/workflows/build.yml` to the new pin, reset `REVISION` to `1`, and
   add a `CHANGELOG.md` entry.
4. Open a pull request; CI verifies, builds and tests it. After merging, push a signed tag such
   as `v7.4.33-32.1` to publish a release.

Repository settings: set the Actions variables `MAINTAINER_NAME` and `MAINTAINER_EMAIL`, and
turn on private vulnerability reporting.

## License

The scripts are MIT licensed (see `LICENSE`). The built packages contain PHP, licensed under
the PHP License 3.01, and Sury's Debian packaging. See `NOTICE.md`.
