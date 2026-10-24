# Changelog

## v7.4.33-31.1 (unreleased)

Rebuild of Sury's `php7.4` `1:7.4.33-31` for Ubuntu 18.04 amd64, as package version
`1:7.4.33-31+legacy1~ubuntu18.04.1`.

### Security

- CVE-2026-109618: remote code execution via out-of-memory corruption.
- CVE-2026-109619: remote code execution via stale global state.

Both are fixed by Sury's `0164-Avoid-state-corruption-via-bailout.patch`, a backport of php-src
commit `712e60f9` (PHP 8.2.35). This revision also carries Sury's earlier security backports
for PHP 7.4; after installing, see `/usr/share/doc/php7.4-common/changelog.Debian.gz`.

### Tested

- CI smoke test on Ubuntu 18.04.
- Before the first release, the packages were regression-tested on a copy of a production
  server running a Laravel 7.30 application (PHP 7.4.9 to 7.4.33): 52 pages, opened as two user
  roles, returned the same status codes, errors and page sizes before and after the upgrade.
  Rolling back to 7.4.9 and upgrading again also worked.
