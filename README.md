# SSB Digital – Junior DevOps / Web Operations Take-Home

[![CI](https://github.com/sunny-pixels/ssb-devops-assignment/actions/workflows/ci.yml/badge.svg)](https://github.com/sunny-pixels/ssb-devops-assignment/actions/workflows/ci.yml)

A small Core PHP + MySQL inventory app on an XAMPP (LAMPP) stack in an Ubuntu VM, with a
validated rsync deployment, verified database/file backups and restore, least-privilege
database users, locked-down file permissions, a documented incident, CI, an Apache vhost,
cron jobs and a health check.

**Status: complete** – all sections A–H and all four optional bonus items · release tag
[`v1.0.0`](https://github.com/sunny-pixels/ssb-devops-assignment/tree/v1.0.0) ·
every step has screenshot / terminal evidence in [`screenshots/`](screenshots/).

---

## At a glance
| Brief | What was delivered | Details | Key evidence |
|---|---|---|---|
| **A** LAMPP setup | XAMPP 8.2.12 under systemd; ports, logs, phpinfo + JSON health page | [01](docs/01-lampp-setup.md) | `01-lampp-status`, `01-ports`, `01-health-curl` |
| **B** Core PHP app | list / add / edit items, PDO prepared statements, config in `/etc/ssb-app/app.env` | [03](docs/03-php-app.md) | `03-app-list`, `03-app-add-*`, `03-app-edit-*` |
| **C** MySQL + phpMyAdmin | schema, seed, app user, import/export, CRUD queries explained | [02](docs/02-mysql-phpmyadmin.md) | `02-phpmyadmin-import`, `02-queries-*` |
| **D** rsync deployment | `deploy.sh`: pre-flight, dry-run preview, excludes, only changed files | [04](docs/04-deploy-release.md) | `04-dry-run`, `04-changed-file-only` |
| **E** Git release flow | 20+ conventional commits, validating deploy script, tag `v1.0.0` | [04](docs/04-deploy-release.md) | `04-fail-clearly`, `04-tag-release` |
| **F** Backup & restore | `backup.sh` (mysqldump + tar, checksums, retention), `restore.sh` into a test DB | [05](docs/05-backup-restore.md) | `05-backup-run`, `05-restore` |
| **G** Security & permissions | no secrets in Git, 640/750 model, non-root DB users, audit script | [06](docs/06-security-permissions.md) | `06-security-audit` |
| **H** Troubleshooting | INC-001: rotated DB password, stale app config → 503 → fixed | [07](docs/07-incident-note.md) | `07-investigate-*`, `07-fix` |
| Bonus | CI (php -l, ShellCheck, secret scan) · vhost · cron backup + retention · `healthcheck.sh` | [08](docs/08-bonus.md) | `08-ci-green`, `08-vhost-test`, `08-healthcheck-fail` |

## Environment
| Item | Value |
|---|---|
| Host | Windows 11 + VMware Workstation (NAT network) |
| Guest | Ubuntu Server 24.04 LTS, hostname `ssb-lamp`, IP `192.168.198.133`, 2 vCPU / 4 GB / 25 GB |
| Stack | XAMPP for Linux 8.2.12 – Apache 2.4.58 · MariaDB 10.4.32 · PHP 8.2.12 · phpMyAdmin 5.2.1 |
| App URLs | `http://192.168.198.133/ssb-app/` · `http://ssb-app.local/` (vhost) · `…/health.php` |

## Prerequisites
- Linux host or VM (tested: Ubuntu 24.04) with `sudo`; ~2 GB free disk
- `git rsync curl cron openssl` (`sudo apt -y install git rsync curl cron openssl`)
- XAMPP for Linux 8.2.x installed to `/opt/lampp` ([01 §1.1](docs/01-lampp-setup.md))
- Paths in `.env.example` and `cron/*.cron` assume user **`ssbadmin`** and the repo at
  `~/ssb-devops-assignment` – adjust if different

## Repository layout
```
app/            Core PHP app – index.php, health.php, inc/ (config, db, helpers), .htaccess
database/       schema.sql, seed.sql, create-app-user.sql, create-backup-user.sql, queries.sql
scripts/        deploy.sh  backup.sh  restore.sh  healthcheck.sh  security-audit.sh
                create-db-user.sh  lampp-check.sh
apache/         ssb-app-vhost.conf        (name-based vhost ssb-app.local)
cron/           ssb-backup.cron (daily 02:30)  ssb-healthcheck.cron (every 5 min)
systemd/        lampp.service             (start Apache + MySQL on boot)
docs/           00–08 step-by-step guides, incident note
screenshots/    evidence (PNG + exported SQL + check report)
.github/        CI workflow
.env.example    all settings with placeholders – the real .env is git-ignored
```

---

## Quick start (fresh VM → running app)
Each step links to the full guide. Run as the normal user from the repo root.
```bash
# 1. Stack: XAMPP + systemd + hardening            → docs/01 (§1.1–1.5)
sudo /opt/lampp/lampp security                       # set MySQL root password
sudo cp systemd/lampp.service /etc/systemd/system/ && sudo systemctl daemon-reload
sudo systemctl enable --now lampp
#    + bind MySQL to 127.0.0.1, mysql_upgrade, PHP timezone, phpMyAdmin IP rule (docs/01)

# 2. Clone and create .env with generated passwords → docs/02 §2.2
git clone https://github.com/sunny-pixels/ssb-devops-assignment.git ~/ssb-devops-assignment
cd ~/ssb-devops-assignment
cp .env.example .env && chmod 640 .env
gen() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20; }
sed -i "s|^DB_PASS=.*|DB_PASS=$(gen)|; s|^BACKUP_DB_PASS=.*|BACKUP_DB_PASS=$(gen)|" .env

# 3. Database, users, sample data                   → docs/02
M=/opt/lampp/bin/mysql
$M -u root -p --table < database/schema.sql
./scripts/create-db-user.sh            # ssb_app    – CRUD only
./scripts/create-db-user.sh backup     # ssb_backup – read-only
$M -u root -p ssb_inventory < database/seed.sql     # or phpMyAdmin → Import
#    + remove XAMPP's open `test` DB and anonymous user (docs/02 §2.8)

# 4. App config outside Git and the web root        → docs/03 §3.2
sudo install -d -m 750 -o root -g daemon /etc/ssb-app
sudo install    -m 640 -o root -g daemon .env /etc/ssb-app/app.env

# 5. Deploy                                         → docs/04
./scripts/deploy.sh --dry-run
./scripts/deploy.sh

# 6. Schedule backup + health check                 → docs/05, docs/08
mkdir -p logs && cat cron/ssb-backup.cron cron/ssb-healthcheck.cron | crontab -

# 7. Verify
./scripts/healthcheck.sh && ./scripts/security-audit.sh
```
Optional: Apache vhost `ssb-app.local` – [docs/08 §8.2](docs/08-bonus.md).

## Day-to-day commands
| Task | Command | Notes |
|---|---|---|
| Deploy a change | `git pull && ./scripts/deploy.sh` | validates, previews, asks `[y/N]`, health-checks; `--dry-run`, `--yes` |
| Release | `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z && ./scripts/deploy.sh` | live revision shown in `health.php` and the page footer |
| Roll back | `git checkout v1.0.0 && ./scripts/deploy.sh && git checkout main` | |
| Backup now | `./scripts/backup.sh` | `~/backups`, 700/600, sha256, 7-day retention |
| Restore (test DB) | `./scripts/restore.sh --latest` | → `ssb_inventory_restore_test`, compares rows + `CHECKSUM TABLE` |
| Restore (live) | `./scripts/restore.sh <file.sql.gz> ssb_inventory` | asks you to type the DB name |
| Health | `./scripts/healthcheck.sh` | exit 0 healthy / 1 unhealthy; `-q` for cron |
| Security audit | `./scripts/security-audit.sh` | 20 checks, exit 1 on any failure |
| Full stack report | `sudo ./scripts/lampp-check.sh` | versions, ports, log tails, health |
| Service control | `sudo systemctl start\|stop\|reload\|status lampp` | or `sudo /opt/lampp/lampp startapache\|stopmysql\|…` |

Raw `mysqldump` / restore commands without the scripts: [docs/05 – Exact commands](docs/05-backup-restore.md#exact-commands-without-the-scripts).

---

## Troubleshooting
**Where to look**
| Log | Path |
|---|---|
| Apache access / error | `/opt/lampp/logs/access_log`, `error_log` · vhost: `ssb-app-access_log`, `ssb-app-error_log` |
| PHP / app errors | `/opt/lampp/logs/php_error_log` (lines tagged `[ssb-app]`) |
| MariaDB | `/opt/lampp/var/mysql/ssb-lamp.err` |
| Deploy / backup / health | `logs/deploy.log`, `logs/backup.log`, `logs/health.log`, `journalctl -t ssb-healthcheck` |

**Quick reference** – `health.php` reports the MySQL error code:
| Symptom | Check | Likely cause → fix |
|---|---|---|
| App 503, health `error 1045` | `php_error_log`; compare `DB_PASS` hashes of `.env` vs `app.env` | wrong/stale password → re-sync `app.env` ([INC-001](docs/07-incident-note.md)) |
| App 503, health `error 2002` | `lampp status`, `ss -tln \| grep 3306` | MySQL stopped / wrong host-port → `systemctl start lampp` |
| health `config: error` | `sudo -u daemon test -r /etc/ssb-app/app.env` | config missing / unreadable by Apache |
| `deploy.sh` refuses | read its `ERROR:` line | missing `.env`, lint error, config drift – nothing was deployed |

**Issues found and fixed while building** (each documented with evidence)
| # | Issue | Fix | Doc |
|---|---|---|---|
| 1 | PHP timezone `Europe/Berlin` (4.5 h off) | `date.timezone=Asia/Kolkata` | 01 |
| 2 | MySQL listening on `*:3306` | `bind-address=127.0.0.1` | 01 |
| 3 | `lampp security` added `skip-networking` → app can't use TCP | replaced by loopback bind | 01 |
| 4 | `mysql.column_stats` definition errors | `mysql_upgrade` | 01 |
| 5 | XAMPP `test` DB open to all users + anonymous account | dropped | 02 |
| 6 | Deploy preview showed folder-mtime "changes" | `rsync --omit-dir-times` | 04 |
| 7 | Misleading "will be deployed / -dirty" warning | separate tracked vs untracked | 04 |
| 8 | INC-001 – stale app config after password rotation | re-sync + deploy guard | 07 |
| 9 | 5 ShellCheck findings | fixed before CI went live | 08 |

## Security summary
Secrets only in git-ignored `.env` / root-owned `app.env` (CI scans the whole history) ·
app code `ssbadmin:daemon 750/640` – Apache can read, not write · nothing world-writable ·
DB users `ssb_app` (CRUD) and `ssb_backup` (read-only), root never used by the app ·
MySQL on loopback only · phpMyAdmin limited to the host IP · internals return 403.
Details and the full permission table: [docs/06](docs/06-security-permissions.md).

---

## Evidence checklist (from the brief)
| ✓ | Item | Screenshots |
|---|---|---|
| ✅ | Apache/PHP page loads | `01-phpinfo`, `01-health`, `03-app-list` |
| ✅ | phpMyAdmin login and table view | `01-phpmyadmin-login`, `02-phpmyadmin-table` |
| ✅ | SQL import/export | `02-phpmyadmin-import`, `02-phpmyadmin-export.png` + `.sql` |
| ✅ | rsync `--dry-run` output | `04-dry-run`, `04-excludes` |
| ✅ | deployed files in target folder | `04-deploy`, `04-deployed-files` |
| ✅ | mysqldump file created | `05-backup-run`, `05-dump-contents` |
| ✅ | restore verified | `05-restore`, `05-files-verify` |
| ✅ | troubleshooting evidence | `07-symptom-*`, `07-investigate-*`, `07-fix` |

## Assumptions & known limitations
- **Internal app, no login** – as described in the brief; access is limited by network, not by app accounts.
- **HTTP only** on a host-only/NAT network; XAMPP's self-signed demo certificate on 443 is left as is.
- **Single VM** – backups live on the same disk; production would copy them off-host (e.g. `rsync` to another server).
- **In-place deploy** – rsync updates files directly; a zero-downtime setup would use release folders + a symlink switch.
- **Alerts** go to a log file and syslog only (no e-mail/pager).
- No host firewall (ufw) configured; XAMPP demo pages under `htdocs/dashboard` remain on the default site.
- XAMPP bundles its own OpenSSL 1.1.1w / MariaDB 10.4 – fine for this exercise; production would use distro packages that receive security updates.

## Documentation
0. [VM preparation](docs/00-vm-setup.md)
1. [LAMPP setup & checks](docs/01-lampp-setup.md)
2. [MySQL + phpMyAdmin](docs/02-mysql-phpmyadmin.md)
3. [Core PHP application](docs/03-php-app.md)
4. [Rsync deployment & release flow](docs/04-deploy-release.md)
5. [Backup & restore](docs/05-backup-restore.md)
6. [Security & permissions](docs/06-security-permissions.md)
7. [Troubleshooting / incident note](docs/07-incident-note.md)
8. [Bonus: CI, vhost, cron, health check](docs/08-bonus.md)

Submission note: [SUBMISSION.md](SUBMISSION.md)
