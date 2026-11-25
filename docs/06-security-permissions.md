# Phase 6 – Security & Permissions (Assignment section G)

Most controls were put in place while building phases 1–5. This page collects them, explains
the permission model, and [`scripts/security-audit.sh`](../scripts/security-audit.sh) re-checks
all of them in one run (exit 1 if any fails).

## 1. No committed secrets
| Control | Detail |
|---|---|
| Templates only | `.env.example` holds `change_me` placeholders; real values only in `.env` |
| Git-ignored | `.env`, `*.env`, backups, dumps, logs (`.gitignore`) |
| Never in history | audit checks `git log --all -- .env` is empty and no commit contains a 12+ char `DB_PASS=` |
| Generated, never typed | passwords created with `openssl rand`, written straight into `.env`, never echoed |
| Not on the command line | scripts pass DB passwords via a temporary `600` option file (`--defaults-extra-file`), not `-p<pass>` – visible in `ps` |
| Not in output | `SHOW GRANTS` avoided (MariaDB 10.4 prints the password hash); stack traces never logged |
| Not served | `.htaccess` returns 403 for `.env`, `*.sql`, `*.gz`, `*.bak`, …; `deploy.sh` excludes them too |

## 2. Linux ownership & permissions
| Path | Owner:Group | Mode | Why |
|---|---|---|---|
| `~/ssb-devops-assignment/.env` | ssbadmin:ssbadmin | `640` | secrets for scripts; no other users |
| `/etc/ssb-app/` | root:daemon | `750` | config outside Git **and** outside the web root |
| `/etc/ssb-app/app.env` | root:daemon | `640` | Apache (`daemon`) can read, cannot change; login user cannot even read |
| `/opt/lampp/htdocs/ssb-app/` dirs | ssbadmin:daemon | `750` | deploy user writes, Apache only reads/traverses |
| `/opt/lampp/htdocs/ssb-app/` files | ssbadmin:daemon | `640` | a PHP bug cannot rewrite the code (Apache has no write bit) |
| `~/backups/` | ssbadmin:ssbadmin | `700` | dumps contain all data |
| backup files | ssbadmin:ssbadmin | `600` | `umask 077` in `backup.sh` |

- **Nothing is world-writable** (no `777`/`666`) – the app needs no writable directory at all
  (sessions go to XAMPP's own `temp/`).
- **Others get nothing** on app code, config and backups (`…0` in every mode).
- Permissions are **enforced by the deploy**, not set by hand: `rsync --chown=ssbadmin:daemon
  --chmod=D750,F640` re-applies them on every release.

Trace the whole path Apache must traverse:
```bash
namei -l /opt/lampp/htdocs/ssb-app/index.php
sudo namei -l /etc/ssb-app/app.env
```

## 3. Database accounts – least privilege, never root in the app
| Account | Rights | Used by |
|---|---|---|
| `root@localhost` | all – password set (Phase 1) | admin only: schema, users, restore |
| `ssb_app` @ localhost, 127.0.0.1 | `SELECT, INSERT, UPDATE, DELETE` on `ssb_inventory.*` | PHP app |
| `ssb_backup` @ localhost, 127.0.0.1 | `SELECT, SHOW VIEW, TRIGGER, LOCK TABLES` on `ssb_inventory.*` | `backup.sh` / cron |

Proven in Phase 2: `DROP TABLE` and reading `mysql.user` are denied for `ssb_app`.

## 4. Network exposure
| Item | State |
|---|---|
| MySQL | bound to **127.0.0.1:3306** – not reachable from the network (Phase 1) |
| phpMyAdmin | `Require local` + `Require ip 192.168.198.1` (Windows host only) |
| FTP (ProFTPD) | not started (`lampp.service` starts Apache + MySQL only) |
| App internals | `inc/` → 403, no directory listings, `display_errors=0` |

## 5. Insecure XAMPP defaults found and fixed
| # | Default | Risk | Fix | Phase |
|---|---|---|---|---|
| 1 | MySQL root with **no password** | anyone local is DB admin | `lampp security` | 1 |
| 2 | MySQL on `*:3306` | DB reachable from the LAN | `bind-address=127.0.0.1` | 1 |
| 3 | `skip-networking` added by `lampp security` | app can't connect over TCP | replaced by loopback bind | 1 |
| 4 | phpMyAdmin local-only (or all) | — | allowed for host IP only | 1 |
| 5 | wildcard `mysql.db` grant on `test`/`test_%` | every user can create tables | dropped DB + grant | 2 |
| 6 | anonymous account `''@'localhost'` | login without a username | `DROP USER` | 2 |
| 7 | `Options Indexes` on htdocs | file listings | `Options -Indexes` | 3 |
| 8 | `display_errors` on | paths/SQL leak to visitors | off in app bootstrap, logged instead | 3 |
| 9 | phpinfo test page | full config disclosure | deleted after the screenshot | 1 |

## 6. Run the audit
```bash
cd ~/ssb-devops-assignment && git pull
./scripts/security-audit.sh
```

## Known limitations (documented, out of scope for a local VM)
- HTTPS uses XAMPP's self-signed demo certificate; the app is served over HTTP on a host-only network.
- No host firewall (ufw) configured – would allow only 22/80 from the host network.
- XAMPP's bundled demo pages under `htdocs/dashboard` remain; a production host would remove them
  or use the dedicated vhost (Phase 8) with its own document root.

## Evidence
| File | Shows |
|---|---|
| `screenshots/06-security-audit.png` | all audit checks PASS |
| `screenshots/06-namei.png` | ownership/permissions along the full path |
