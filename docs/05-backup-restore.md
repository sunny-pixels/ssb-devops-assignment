# Phase 5 – Backup & Restore (Assignment section F + cron bonus)

| What | How | Where |
|---|---|---|
| Database | `mysqldump` as read-only user `ssb_backup` → gzip | `~/backups/ssb_db_ssb_inventory_<ts>.sql.gz` |
| App files | `tar` of the deployed folder | `~/backups/ssb_files_<ts>.tar.gz` |
| Integrity | gzip test, "Dump completed" footer, table/file count, SHA-256 | `<file>.sha256` |
| Retention | delete backups older than `BACKUP_RETENTION_DAYS` (7) – **only after a successful run** | – |
| Schedule | cron, daily 02:30 | `cron/ssb-backup.cron` |
| Restore | into a **separate test DB**, then compare row counts + `CHECKSUM TABLE` with live | `scripts/restore.sh` |

**Safety choices:** backup dir `700`, files `600` (`umask 077`) · DB password passed via a
temporary option file, never on the command line (`ps` would show it) · written as `.part`
and renamed only after verification, so a failed run never leaves a "valid-looking" backup ·
`flock` prevents a manual run overlapping the cron run · restore defaults to a test DB;
restoring over live requires typing the DB name.

**What a DB backup does not contain:** MySQL users/grants (in the `mysql` system DB – recreate
with `create-db-user.sh`) and `/etc/ssb-app/app.env` (recreate from `.env`). Code is best
restored by redeploying a Git tag; the files tarball is for when the repo itself is lost.

---

## 5.1 Backup DB user (read-only)
```bash
cd ~/ssb-devops-assignment && git pull
grep -q '^BACKUP_DB_USER=' .env || printf '\nBACKUP_DB_USER=ssb_backup\n' >> .env
grep -q '^BACKUP_DB_PASS=' .env || \
  printf 'BACKUP_DB_PASS=%s\n' "$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)" >> .env
grep -c '^BACKUP_DB_' .env                     # → 2  (don't print the values)
./scripts/create-db-user.sh backup             # MySQL ROOT password
```
Expected: `ssb_backup` @ `localhost` and `127.0.0.1` with `LOCK TABLES,SELECT,SHOW VIEW,TRIGGER`.

## 5.2 Run a backup
```bash
./scripts/backup.sh
ls -la ~/backups
zcat "$(ls -t ~/backups/ssb_db_*.sql.gz | head -1)" \
  | grep -E '^(-- (MariaDB dump|Host|Server version|Dump completed)|DROP TABLE|CREATE TABLE|INSERT INTO)' | cut -c1-110
```

## 5.3 Run it the way cron does (minimal environment)
Cron has no login shell, almost no `PATH` and no `.bashrc`; testing like this catches that early.
```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/bash -c "$HOME/ssb-devops-assignment/scripts/backup.sh"
```

## 5.4 Restore into a test database and verify
```bash
./scripts/restore.sh --latest                  # MySQL ROOT password
```
Verifies the checksum, gzip and dump footer, (re)creates `ssb_inventory_restore_test`,
imports, then prints per table: restored rows · live rows · `MATCH` if `CHECKSUM TABLE` is identical.

## 5.5 Verify the files backup
```bash
F="$(ls -t ~/backups/ssb_files_*.tar.gz | head -1)"
mkdir -p /tmp/restore-files && tar -xzf "$F" -C /tmp/restore-files
diff -r /tmp/restore-files/ssb-app /opt/lampp/htdocs/ssb-app && echo "files backup identical to live"
rm -rf /tmp/restore-files
```

## 5.6 Retention
Fake two 10-day-old backups, run a backup, watch them get deleted:
```bash
touch -d '10 days ago' ~/backups/ssb_db_ssb_inventory_20261115-023000.sql.gz \
                       ~/backups/ssb_files_20261115-023000.tar.gz
ls -la ~/backups
./scripts/backup.sh                            # step 4/4 → "deleted …20261115…"
```

## 5.7 Schedule with cron
```bash
mkdir -p logs
crontab -l 2>/dev/null || echo "(no crontab yet)"
crontab cron/ssb-backup.cron
crontab -l
```

## 5.8 Clean up the test database
```bash
/opt/lampp/bin/mysql -u root -p -e 'DROP DATABASE ssb_inventory_restore_test;'
```

---

## Exact commands without the scripts
```bash
# Backup – database (password from an option file, not the command line)
/opt/lampp/bin/mysqldump --defaults-extra-file=/path/backup.cnf \
    --single-transaction --quick --no-tablespaces --default-character-set=utf8mb4 \
    ssb_inventory | gzip -9 > ~/backups/ssb_db_ssb_inventory_$(date +%Y%m%d-%H%M%S).sql.gz

# Backup – files
tar -C /opt/lampp/htdocs -czf ~/backups/ssb_files_$(date +%Y%m%d-%H%M%S).tar.gz ssb-app

# Restore – database into a new test DB
/opt/lampp/bin/mysql -u root -p -e "CREATE DATABASE ssb_inventory_restore_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
zcat ~/backups/ssb_db_ssb_inventory_<ts>.sql.gz | /opt/lampp/bin/mysql -u root -p ssb_inventory_restore_test
/opt/lampp/bin/mysql -u root -p -e "SELECT COUNT(*) FROM ssb_inventory_restore_test.items;
                                    CHECKSUM TABLE ssb_inventory_restore_test.items, ssb_inventory.items;"

# Restore – files (disaster case; normally redeploy a Git tag with deploy.sh)
sudo tar -xzf ~/backups/ssb_files_<ts>.tar.gz -C /opt/lampp/htdocs
```
| Option | Why |
|---|---|
| `--single-transaction` | consistent snapshot of InnoDB tables **without locking** the app |
| `--quick` | stream rows instead of buffering whole tables in memory |
| `--no-tablespaces` | avoids needing the global PROCESS privilege |
| no `--databases` | dump has no `CREATE DATABASE`/`USE`, so it can be restored into **any** DB name |

---

## Evidence
| File | Shows |
|---|---|
| `screenshots/05-backup-user.png` | 5.1 – read-only grants for `ssb_backup` |
| `screenshots/05-backup-run.png` | 5.2 – backup output + `ls -la ~/backups` (700/600) |
| `screenshots/05-dump-contents.png` | 5.2 – dump header, DROP/CREATE TABLE, INSERT, footer |
| `screenshots/05-cron-env-run.png` | 5.3 – backup works in a cron-like environment |
| `screenshots/05-restore.png` | 5.4 – restore + verification table (MATCH) |
| `screenshots/05-files-verify.png` | 5.5 – files backup identical to live |
| `screenshots/05-retention.png` | 5.6 – old backups deleted |
| `screenshots/05-crontab.png` | 5.7 – installed crontab |
