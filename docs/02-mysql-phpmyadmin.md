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

## 2.7 Prove the app user is restricted
```bash
$M -h 127.0.0.1 -u ssb_app -p ssb_inventory -e "DROP TABLE items;"
$M -h 127.0.0.1 -u ssb_app -p -e "SHOW DATABASES;"
```
Expected: `ERROR 1142 (42000): DROP command denied to user 'ssb_app'@…` for table `items`,
and `SHOW DATABASES` lists only `information_schema` and `ssb_inventory`.

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
| `screenshots/02-queries.png` | 2.6 – CRUD output as `ssb_app` |
| `screenshots/02-privilege-denied.png` | 2.7 – DROP denied + limited SHOW DATABASES |
