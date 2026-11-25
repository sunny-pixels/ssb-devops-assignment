# Phase 3 – Core PHP Application (Assignment section B)

A small Core PHP page (no framework) that lists items from MySQL and supports
**add** and **edit**. URL: `http://192.168.198.133/ssb-app/`

## Structure
```
app/
├── index.php          list + add form + edit form (one page)
├── health.php         JSON health check: PHP, extensions, config, database
├── .htaccess          no directory listings; never serve .env/.sql/.bak files
├── assets/style.css
└── inc/               loaded by PHP only – .htaccess denies direct web access
    ├── bootstrap.php  hide errors from visitors, log them, 503 page on DB failure
    ├── config.php     reads /etc/ssb-app/app.env (outside Git and web root)
    ├── db.php         PDO connection (exceptions, real prepared statements, 3 s timeout)
    ├── helpers.php    escaping, session, CSRF token, flash messages, redirect
    └── items.php      SQL for items + input validation
```

## Design decisions
| Concern | How it's handled |
|---|---|
| DB settings outside source | `inc/config.php` reads `/etc/ssb-app/app.env` – not in Git, not under `htdocs`, `root:daemon 640` |
| Not using root | connects as `ssb_app` (CRUD only, Phase 2) |
| SQL injection | every query is a prepared statement; `ATTR_EMULATE_PREPARES=false` |
| XSS | every printed value goes through `e()` (`htmlspecialchars`) |
| CSRF | random per-session token in each form, checked with `hash_equals` |
| Duplicate SKU | DB `UNIQUE` key; PDO error `23000` shown as a friendly message |
| Refresh re-submits form | Post/Redirect/Get (303 redirect after save) |
| Error leakage | `display_errors=0`; details → `/opt/lampp/logs/php_error_log`; user sees a generic page, HTTP 503 for DB problems |
| MySQL down | 3 s connect timeout instead of hanging; `health.php` returns 503 with the MySQL error code |

---

## 3.1 Pull and syntax-check (VM)
```bash
cd ~/ssb-devops-assignment && git pull
find app -name '*.php' -exec /opt/lampp/bin/php -l {} \;
```
Every line must say `No syntax errors detected`.

## 3.2 Install the config file outside the web root
Apache runs as `daemon` (Phase 1), so it needs read access; nobody else does.
```bash
sudo install -d -m 750 -o root -g daemon /etc/ssb-app
sudo install    -m 640 -o root -g daemon .env /etc/ssb-app/app.env
sudo ls -la /etc/ssb-app
sudo -u daemon test -r /etc/ssb-app/app.env && echo "daemon: can read"
cat /etc/ssb-app/app.env            # as ssbadmin → Permission denied (expected)
```

## 3.3 Copy the app into the web root (temporary)
```bash
sudo rsync -a --delete app/ /opt/lampp/htdocs/ssb-app/
ls -la /opt/lampp/htdocs/ssb-app /opt/lampp/htdocs/ssb-app/inc
```
> Phase 4 replaces this with `scripts/deploy.sh` (dry-run, excludes, validation).

## 3.4 Use the app (browser on Windows)
**http://192.168.198.133/ssb-app/**
1. **List** – 10 seed items; quantities under 5 shown in red.
2. **Add** – fill the form, e.g. `SKU LAP-003`, `HP ProBook 440`, `Hardware`, `4`, `58900` → *Add item* → green "Item LAP-003 added."
3. **Edit** – click *Edit* on that row → change quantity to `9` → *Save changes* → "Item LAP-003 updated."
4. **Validation** – try adding SKU `LAP-001` again → "SKU LAP-001 already exists".

> The new item got **id 12, not 11**. id 11 was used by `DEMO-001` in Phase 2 and then
> deleted – InnoDB never reuses AUTO_INCREMENT values. The rejected duplicate insert also
> consumes one, so the next item will be id 14. Gaps in ids are normal and harmless.

## 3.5 Verify from the database side
```bash
M=/opt/lampp/bin/mysql
$M -h 127.0.0.1 -u ssb_app -p ssb_inventory --table \
   -e "SELECT id, sku, name, quantity, unit_price, created_at, updated_at FROM items WHERE sku='LAP-003';"
```

## 3.6 Health check now includes the database
```bash
curl -s -w '\nHTTP %{http_code}\n' http://localhost/ssb-app/health.php
```
Expect `"config": "ok"`, `"database": "ok"`, `"items": 11`, `HTTP 200`.

## 3.7 Hardening checks
```bash
for p in inc/config.php inc/ assets/ .env app.env; do
  printf '%-16s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' http://localhost/ssb-app/$p)"
done
```
| Path | Expected | Why |
|---|---|---|
| `inc/config.php` | 403 | `inc/.htaccess` → `Require all denied` |
| `inc/` | 403 | same |
| `assets/` | 403 | `Options -Indexes` – no file listing |
| `.env` / `app.env` | 403 or 404 | never deployed; denied by pattern anyway |

---

## Evidence
| File | Shows |
|---|---|
| `screenshots/03-php-lint.png` | 3.1 – `php -l` on every file |
| `screenshots/03-config-perms.png` | 3.2 – `/etc/ssb-app` perms, daemon can read, ssbadmin denied |
| `screenshots/03-app-list.png` | 3.4 – item list in the browser |
| `screenshots/03-app-add-1.png`, `-2.png` | 3.4 – "Item LAP-003 added", new row (qty 4, red) |
| `screenshots/03-app-edit-1.png`, `-2.png` | 3.4 – "Item LAP-003 updated", qty 9, newer timestamp |
| `screenshots/03-app-validation.png` | 3.4 – duplicate SKU message |
| `screenshots/03-db-verify.png` | 3.5 – the new row seen from MySQL |
| `screenshots/03-health-hardening.png` | 3.6 – health JSON (config + database ok, 11 items, HTTP 200) · 3.7 – all five paths 403 |
