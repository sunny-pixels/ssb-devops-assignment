# Phase 7 – Troubleshooting Exercise (Assignment section H)

**Scenario (simulated):** the `ssb_app` database password is rotated – changed in `.env` and in
MySQL – but the copy the web app actually reads, `/etc/ssb-app/app.env`, is not updated.
A common real-world mistake: two copies of a secret, only one changed.

## Incident note

> **INC-001 · 2026-11-25 · SSB Inventory app down (HTTP 503) · impact ≈ 4 min (13:06:48–13:10:44 IST)**
>
> - **Issue:** after rotating the `ssb_app` DB password, `http://192.168.198.133/ssb-app/` showed
>   "The database is currently unavailable" (HTTP 503); `health.php` reported `"database": "error 1045"`.
> - **Checks:** `lampp status` → MySQL running; `ss -tln` → 127.0.0.1:3306 listening; health → PHP
>   extensions and config file OK – so not a stopped service, wrong port or missing extension.
>   `php_error_log` → `SQLSTATE[HY000] [1045] Access denied for user 'ssb_app'@'localhost' (using password: YES)`;
>   MariaDB error log shows the same refusal. Comparing hashes of the `DB_PASS` lines showed
>   `.env` ≠ `/etc/ssb-app/app.env`, and the password from `.env` logs in fine.
> - **Cause:** the rotation updated `.env` and MySQL but not `/etc/ssb-app/app.env`, so the app
>   kept sending the old password.
> - **Fix:** `sudo install -m 640 -o root -g daemon .env /etc/ssb-app/app.env` – config is read per
>   request, so no restart needed; health back to 200 immediately.
> - **Prevention:** `deploy.sh` pre-flight now compares the DB settings of both files (hashes only)
>   and refuses to deploy while they differ; the rotation procedure ends with the sync + health
>   check; `healthcheck.sh` (Phase 8) can run from cron to catch a 503 within minutes.

### Timeline (from the logs and file timestamps)
| Time (IST) | Event | Source |
|---|---|---|
| 13:06:24 | `.env` rewritten with the new password; `create-db-user.sh` applies it in MySQL | `ls -l .env` |
| 13:06:48 | first failed page load – `[1045] Access denied` | `php_error_log`, MariaDB `.err` |
| 13:07:09 | `health.php` → `"database": "error 1045"`, HTTP 503 | curl |
| ~13:08 | MySQL running and listening ruled out; logs point to credentials | `lampp status`, `ss`, logs |
| ~13:09 | `DB_PASS` hashes differ; `app.env` last changed 12:23:36; `.env` password works | `sha256sum`, `ls -l`, mysql login |
| ~13:10 | `app.env` re-synced from `.env` | `sudo install` |
| 13:10:44 | `health.php` → `"database": "ok"`, 11 items, HTTP 200; deploy pre-flight passes | curl, `deploy.sh --dry-run` |

---

## Reproduce it

### 7.0 Baseline – healthy
```bash
cd ~/ssb-devops-assignment && git pull
curl -s -o /dev/null -w 'health HTTP %{http_code}\n' http://localhost/ssb-app/health.php   # → 200
```

### 7.1 Break it – rotate the password, "forget" app.env
```bash
NEW=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
sed -i "s|^DB_PASS=.*|DB_PASS=$NEW|" .env && unset NEW
./scripts/create-db-user.sh          # MySQL ROOT password → ssb_app now has the NEW password
# (the step that is "forgotten": copying .env to /etc/ssb-app/app.env)
```

### 7.2 Symptom
Browser: **http://192.168.198.133/ssb-app/** → "The database is currently unavailable".
```bash
curl -s -o /dev/null -w 'index  HTTP %{http_code}\n' http://localhost/ssb-app/
curl -s -w '\nHTTP %{http_code}\n' http://localhost/ssb-app/health.php
```

### 7.3 Investigate – rule things out, then read the logs
```bash
sudo /opt/lampp/lampp status                     # MySQL running?            → yes
ss -tln | grep 3306                              # listening on the port?     → 127.0.0.1:3306
sudo tail -n 3 /opt/lampp/logs/php_error_log     # what does PHP say?         → 1045 Access denied
sudo grep 'Access denied' /opt/lampp/var/mysql/ssb-lamp.err | tail -n 3   # MySQL side
```
Compare the two config files **without printing the password**:
```bash
grep '^DB_PASS=' .env                    | sha256sum
sudo grep '^DB_PASS=' /etc/ssb-app/app.env | sha256sum       # different hash → files out of sync
ls -l --time-style=+%T .env; sudo ls -l --time-style=+%T /etc/ssb-app/app.env   # app.env older
```
Confirm the password in `.env` is the one MySQL expects:
```bash
/opt/lampp/bin/mysql --defaults-extra-file=<(printf '[client]\nuser=ssb_app\npassword=%s\nhost=127.0.0.1\n' \
    "$(grep '^DB_PASS=' .env | cut -d= -f2)") -e "SELECT 'password in .env works' AS result;"
```
The deploy pre-flight (prevention) catches it too:
```bash
./scripts/deploy.sh --dry-run                    # → ERROR: DB settings in /etc/ssb-app/app.env differ from .env
```

### 7.4 Fix and verify
```bash
sudo install -m 640 -o root -g daemon .env /etc/ssb-app/app.env
grep '^DB_PASS=' .env | sha256sum; sudo grep '^DB_PASS=' /etc/ssb-app/app.env | sha256sum   # identical
curl -s -w '\nHTTP %{http_code}\n' http://localhost/ssb-app/health.php                      # database ok, 200
./scripts/deploy.sh --dry-run                    # pre-flight passes again
```
Browser: the item list is back.

## Why this was quick to diagnose
The app was built for it in Phase 3: errors go to the log with the exact MySQL error, the user
sees a clean 503 instead of a stack trace, `health.php` reports the MySQL error **code** per
check, and the connection has a 3 s timeout instead of hanging.

| MySQL code | Meaning | Likely cause |
|---|---|---|
| 1045 | Access denied | wrong user/password (this incident) |
| 2002 | Can't connect | MySQL stopped, or wrong host/port |
| 1049 | Unknown database | wrong `DB_NAME` |
| 1146 | Table doesn't exist | schema not created / restore incomplete |

## Evidence
| File | Shows |
|---|---|
| `screenshots/07-break.png` | 7.1 – password rotated in `.env` and MySQL |
| `screenshots/07-symptom-browser.png` | 7.2 – 503 page in the browser |
| `screenshots/07-symptom-health.png` | 7.2 – `health.php` → `"database": "error 1045"`, HTTP 503 |
| `screenshots/07-investigate-1.png` | 7.3 – MySQL running, 127.0.0.1:3306 listening, 1045 in PHP and MariaDB logs |
| `screenshots/07-investigate-2.png` | 7.3 – `DB_PASS` hashes differ, `app.env` older, `.env` password works |
| `screenshots/07-deploy-guard.png` | 7.3 – deploy refuses while configs differ |
| `screenshots/07-fix.png` | 7.4 – health `database: ok`, HTTP 200; pre-flight "DB settings match .env" |

> The hashes shown are SHA-256 of a 20-character random password line – not reversible in
> practice – and the old password they partly refer to is no longer valid.
