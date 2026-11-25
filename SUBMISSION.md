# Submission – Junior DevOps / Web Operations Take-Home

**Repository:** https://github.com/sunny-pixels/ssb-devops-assignment
(start with the [README](README.md); tested release tag `v1.0.0`)

**What is complete**
- All required sections A–H, each with a step-by-step guide in `docs/` and screenshot or
  terminal evidence in `screenshots/` (all 8 items of the suggested evidence checklist).
- Required deliverables: Core PHP app + SQL schema/sample data, `deploy.sh` (rsync with
  pre-flight checks, dry-run preview, excludes, changed-files-only) and `backup.sh`
  (mysqldump + files, checksums, retention), plus `restore.sh` with verification against
  the live database, and a 5–10 line incident note (INC-001).
- All four optional bonus items: GitHub Actions CI (php -l on PHP 8.2, ShellCheck, secret
  scan – green), an Apache virtual host, a daily cron backup with retention, and
  `healthcheck.sh` that exits non-zero on failure.
- Along the way, nine insecure or broken XAMPP defaults were found and fixed (e.g. MySQL
  listening on all interfaces, an open `test` database with an anonymous account), each
  documented with evidence.

**Known limitations**
- Runs on a single local VM over HTTP; XAMPP's self-signed certificate is left unchanged
  and no host firewall is configured.
- Backups are stored on the same VM (no off-site copy); alerts go to log/syslog only.
- Deployment updates files in place (no release-folder/symlink switch for zero downtime).
- The app has no login, as an internal tool; XAMPP bundles its own OpenSSL/MariaDB
  versions, which a production server would replace with updated distro packages.

**Environment:** Windows 11 host → VMware Workstation → Ubuntu Server 24.04 LTS VM, XAMPP
for Linux 8.2.12 (Apache 2.4.58, MariaDB 10.4.32, PHP 8.2.12, phpMyAdmin 5.2.1).

**Approximate time spent:** about 4–5 hours.
