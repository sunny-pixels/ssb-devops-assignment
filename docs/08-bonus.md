# Phase 8 – Optional Bonus Items

| Bonus item (brief) | Delivered | Evidence |
|---|---|---|
| CI job running PHP syntax checks | `.github/workflows/ci.yml` – `php -l` (PHP 8.2), **ShellCheck**, secret scan of the full history | GitHub Actions run |
| Apache virtual host | `apache/ssb-app-vhost.conf` – `ssb-app.local`, own logs, security headers | `08-vhost-*.png` |
| Cron daily DB backup with retention | `cron/ssb-backup.cron` + `backup.sh` (Phase 5) | `05-crontab.png`, `05-retention.png` |
| Health-check script, non-zero exit on failure | `scripts/healthcheck.sh` + `cron/ssb-healthcheck.cron` (every 5 min) | `08-healthcheck-*.png` |

---

## 8.1 CI – GitHub Actions
Runs on every push to `main` and on pull requests. Three independent jobs:
| Job | What it checks |
|---|---|
| **php-lint** | `php -l` on every file under `app/`, with PHP **8.2** – same version as XAMPP |
| **shellcheck** | all `scripts/*.sh` (static analysis: quoting, unsafe globs, unused vars, …) |
| **secret-scan** | `.env` never in history; no real-looking `DB_PASS=` value in **any** commit (`fetch-depth: 0`) |

Before the first push, ShellCheck was run locally and found 1 warning + 4 style/info notes
(a comma inside `--chmod=D750,F640` read as an array separator, an `A && B || C` used as
if/else, `ls` parsing, …) – all fixed, so CI starts green.

View: **GitHub → repository → Actions → CI**.

## 8.2 Apache virtual host
Name-based vhost `ssb-app.local` with the app at the web root, its own log files, version
hiding (`ServerTokens Prod`) and security headers. Because Apache sends requests matching no
`ServerName` to the **first** vhost, the file first re-creates the stock site – so
`http://192.168.198.133/ssb-app/`, `/phpmyadmin` and `deploy.sh`'s health check keep working.

```bash
cd ~/ssb-devops-assignment && git pull
grep -n 'httpd-vhosts.conf\|ssb-app-vhost' /opt/lampp/etc/httpd.conf     # stock vhosts file is commented out
sudo cp apache/ssb-app-vhost.conf /opt/lampp/etc/extra/
grep -q 'ssb-app-vhost.conf' /opt/lampp/etc/httpd.conf || \
  echo 'Include etc/extra/ssb-app-vhost.conf' | sudo tee -a /opt/lampp/etc/httpd.conf
sudo /opt/lampp/bin/httpd -t -D SSL -D PHP                                # → Syntax OK
sudo systemctl reload lampp
```
Test from the VM (the `Host:` header selects the vhost):
```bash
H='Host: ssb-app.local'
curl -s -o /dev/null -w 'ssb-app.local/              %{http_code}\n' -H "$H" http://127.0.0.1/
curl -s -o /dev/null -w 'ssb-app.local/phpmyadmin/   %{http_code}\n' -H "$H" http://127.0.0.1/phpmyadmin/
curl -s -o /dev/null -w 'ssb-app.local/inc/config.php %{http_code}\n' -H "$H" http://127.0.0.1/inc/config.php
curl -s -o /dev/null -w 'localhost/ssb-app/ (old)    %{http_code}\n' http://localhost/ssb-app/
curl -sI -H "$H" http://127.0.0.1/ | grep -iE '^(server|x-frame|x-content|referrer|x-powered)'
ls -l /opt/lampp/logs/ssb-app-*_log
```
Expected: `200`, `403`, `403`, `200`; `Server: Apache` (no versions), the three security headers,
no `X-Powered-By`.

**Browser on Windows (optional):** add to `C:\Windows\System32\drivers\etc\hosts` (as
Administrator) `192.168.198.133  ssb-app.local`, then open **http://ssb-app.local/**.

## 8.3 Health-check script
```bash
./scripts/healthcheck.sh;  echo "exit code: $?"
```
| Check | How |
|---|---|
| Apache | `httpd` process running **and** port 80 listening |
| MySQL | port listening **and** `mysqladmin ping` (as read-only `ssb_backup`) |
| App | `health.php` → HTTP 200 and `"status": "ok"` (covers PHP, config, DB as the app user) |
| Backups | newest DB backup younger than 26 h (catches a silently broken cron) |
| Disk | `/opt/lampp` and the backup disk below 90 % |

**Failure demo** – stop MySQL, check, start again:
```bash
sudo /opt/lampp/lampp stopmysql
./scripts/healthcheck.sh;  echo "exit code: $?"           # → UNHEALTHY, exit code: 1
sudo /opt/lampp/lampp startmysql
sleep 3; ./scripts/healthcheck.sh;  echo "exit code: $?"  # → HEALTHY, exit code: 0
```

**Schedule** (every 5 minutes, quiet – logs + syslog only on failure):
```bash
cat cron/ssb-backup.cron cron/ssb-healthcheck.cron | crontab -
crontab -l | grep -v '^#' | grep .
```
`lampp-check.sh` (Phase 1) stays as the verbose *evidence report*; `healthcheck.sh` is the
short, machine-friendly *monitor*.

## Evidence
| File | Shows |
|---|---|
| `screenshots/08-ci-green.png` | GitHub Actions – all three jobs passed |
| `screenshots/08-vhost-install.png` | `httpd -t` Syntax OK, reload |
| `screenshots/08-vhost-test.png` | status codes, headers, separate logs |
| `screenshots/08-healthcheck-ok.png` | all checks ok, exit 0 |
| `screenshots/08-healthcheck-fail.png` | MySQL stopped → UNHEALTHY, exit 1 → recovered |
| `screenshots/08-crontab.png` | backup + health check scheduled |
