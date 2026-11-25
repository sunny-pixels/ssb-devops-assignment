# Phase 2 – MySQL + phpMyAdmin (Assignment section C)

Database `ssb_inventory` · table `items` · app user `ssb_app` (CRUD only, never root).

| File | Purpose | Run as |
|---|---|---|
| [`database/schema.sql`](../database/schema.sql) | create database + `items` table | root (CLI) |
| [`database/create-app-user.sql`](../database/create-app-user.sql) | least-privilege app user (password placeholder) | root, via `scripts/create-db-user.sh` |
| [`database/seed.sql`](../database/seed.sql) | 10 sample rows – the file imported in phpMyAdmin | root (phpMyAdmin) |
| [`database/queries.sql`](../database/queries.sql) | SELECT / INSERT / UPDATE / DELETE with explanations | **ssb_app** (CLI) |

All commands run on the VM, from the repo:
```bash
cd ~/ssb-devops-assignment && git pull
M=/opt/lampp/bin/mysql            # XAMPP's client (not on PATH by default)
```

---

## 2.1 Create the database and table (root)
```bash
$M -u root -p --table < database/schema.sql
```
Output ends with `SHOW TABLES` → `items` and the `DESCRIBE items` column list.

## 2.2 Create `.env` with the app password (never committed)
```bash
cp .env.example .env
chmod 640 .env                                  # owner rw, group r, others nothing
PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
sed -i "s|^DB_PASS=.*|DB_PASS=$PASS|" .env
unset PASS
grep -c '^DB_PASS=change_me' .env               # → 0 (placeholder replaced)
ls -l .env                                      # → -rw-r----- ssbadmin ssbadmin
git status --short                              # .env must NOT appear (git-ignored)
```

## 2.3 Create the app user (least privilege)
```bash
chmod +x scripts/create-db-user.sh
./scripts/create-db-user.sh                     # prompts for the MySQL ROOT password
```
The script fails clearly if `.env` is missing, `DB_PASS` is still `change_me`, too short,
or contains characters that would break the SQL. Expected result:

| GRANTEE | TABLE_SCHEMA | privileges |
|---|---|---|
| `'ssb_app'@'127.0.0.1'` | ssb_inventory | DELETE,INSERT,SELECT,UPDATE |
| `'ssb_app'@'localhost'` | ssb_inventory | DELETE,INSERT,SELECT,UPDATE |

Why two hosts: MariaDB matches `localhost` for socket connections and `127.0.0.1` for
TCP. The app connects over TCP to `127.0.0.1` (MySQL is bound to loopback – Phase 1).

## 2.4 phpMyAdmin – import the provided SQL file
Browser on Windows → **http://192.168.198.133/phpmyadmin** → log in as `root`.
1. Left panel → click **ssb_inventory**
2. Top tab **Import** → *Choose File* → `D:\Project_New\Devops_Task\database\seed.sql`
3. Leave defaults (Format: SQL) → **Import** (bottom)
4. Green banner: *"Import has been successfully finished, N queries executed"*
5. Click table **items** → **Browse** → 10 rows

## 2.5 phpMyAdmin – export a backup
1. Select **ssb_inventory** → tab **Export**
2. Export method **Quick**, Format **SQL** → **Export**
3. Browser downloads `ssb_inventory.sql` → move it to
   `D:\Project_New\Devops_Task\screenshots\02-phpmyadmin-export.sql`

**What the export contains (and doesn't):**
- `CREATE TABLE items (…)` – structure, keys, charset, AUTO_INCREMENT value
- `INSERT INTO items … VALUES …` – every row (sample data only, safe to commit)
- **Not** the database user or its grants – those live in the `mysql` system database.
  After restoring onto a new server, `create-db-user.sh` must be run again.
- **Not** `CREATE DATABASE` (Quick export of one DB) – the target DB is chosen at import time.
- Indexes and AUTO_INCREMENT are added **after** the data (`ALTER TABLE … ADD PRIMARY KEY …`,
  `AUTO_INCREMENT=11`) – faster bulk load, and new rows continue from id 11.
- Plain `CREATE TABLE` (no `IF NOT EXISTS`, no `DROP TABLE`) – importing into a database that
  already has `items` fails. Restore into an **empty/new** database (Phase 5 does exactly that).
- Wrapped in `START TRANSACTION … COMMIT` – a failed import does not leave half the rows.
- **Timestamps appear 5:30 h earlier** (`06:33:50` vs `12:03:50` in the browse view): the dump
  runs `SET time_zone = "+00:00"`, so `TIMESTAMP` values are written in UTC. On import the same
  setting is applied, so they are restored to the identical instant – nothing is lost.

## 2.6 CRUD queries as the app user
```bash
$M -h 127.0.0.1 -u ssb_app -p ssb_inventory --table --verbose < database/queries.sql
# password: the DB_PASS value →  grep ^DB_PASS .env   (don't screenshot that line)
```
| # | Statement | What it does |
|---|---|---|
| 1 | `SELECT … ORDER BY id DESC` | reads all rows; changes nothing |
| 2 | `SELECT … WHERE quantity < 5` | reads only matching rows (low stock) |
| 3 | `INSERT INTO items …` | adds row `DEMO-001`; `id`/timestamps filled automatically |
| 4 | `UPDATE items SET … WHERE sku='DEMO-001'` | changes that one row; **without WHERE it would change every row** |
| 5 | `DELETE FROM items WHERE sku='DEMO-001'` | removes that one row; same WHERE warning |

Ends with `demo_rows_left = 0` and `total_items = 10` – seed data untouched.
New row got `id = 11`, continuing from the `AUTO_INCREMENT=11` seen in the export.
(`updated_at` equals `created_at` here only because the UPDATE ran in the same second.)

## 2.7 Prove the app user is restricted
```bash
$M -h 127.0.0.1 -u ssb_app -p ssb_inventory -e "DROP TABLE items;"
$M -h 127.0.0.1 -u ssb_app -p -e "SHOW DATABASES;"
```
Expected: `ERROR 1142 (42000): DROP command denied to user 'ssb_app'@…` for table `items`,
and `SHOW DATABASES` lists only `information_schema` and `ssb_inventory`.

Note: the error names `'ssb_app'@'localhost'` although we connected over TCP to
`127.0.0.1` – MariaDB reverse-resolves the loopback address to `localhost` and matches that
account. Creating both host entries (2.3) makes the app work either way.

## 2.8 Finding: every user can see the `test` database → removed
`SHOW DATABASES` as `ssb_app` also listed **`test`**, which was never granted.
**Cause:** legacy MySQL default kept by XAMPP – a wildcard row in `mysql.db` gives *all*
users (even anonymous) full rights on `test` and `test_*`. `lampp security` does not remove
it (on a normal install `mysql_secure_installation` does).

**Inspect (root):**
```bash
$M -u root -p --table -e "
  SELECT Host, Db, User FROM mysql.db WHERE Db LIKE 'test%';
  SELECT User, Host FROM mysql.user WHERE User = '';"
```
**Fix (root):**
```bash
$M -u root -p -e "
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db IN ('test', 'test\\_%');
  DROP USER IF EXISTS ''@'localhost', ''@'ssb-lamp', ''@'%';
  FLUSH PRIVILEGES;"
```
**Found:** `%` / `test` and `%` / `test\_%` with an empty `User` (= any user from any host),
plus an **anonymous account `''@'localhost'`** – anyone on the VM could log in without a
username and write to `test`.

**Verify (app user):** `SHOW DATABASES` now lists only `information_schema` and `ssb_inventory`.

---

## Evidence
| File | Shows |
|---|---|
| `screenshots/02-schema.png` | 2.1 – `SHOW TABLES` + `DESCRIBE items` |
| `screenshots/02-env-file.png` | 2.2 – `ls -l .env` (640) + `git status` clean (do **not** show the password) |
| `screenshots/02-app-user.png` | 2.3 – script output with the privileges table |
| `screenshots/02-phpmyadmin-import.png` | 2.4 – green "Import has been successfully finished" |
| `screenshots/02-phpmyadmin-table.png` | 2.4 – `items` table browse view (10 rows) |
| `screenshots/02-phpmyadmin-export.png` | 2.5 – Export page (Quick / SQL) |
| `screenshots/02-phpmyadmin-export.sql` | 2.5 – the exported backup file |
| `screenshots/02-queries-1.png` … `-3.png` | 2.6 – CRUD output as `ssb_app` (SELECT → INSERT → UPDATE → DELETE → counts) |
| `screenshots/02-privilege-denied.png` | 2.7 – `DROP TABLE` denied for `ssb_app` |
| `screenshots/02-privilege-mysql-user.png` | 2.7 – reading `mysql.user` denied |
| `screenshots/02-show-databases-before.png` | 2.8 – finding: `test` DB visible to the app user |
| `screenshots/02-test-db-inspect.png` | 2.8 – wildcard `mysql.db` grant / anonymous users |
| `screenshots/02-show-databases-after.png` | 2.8 – after fix: only `ssb_inventory` visible |
