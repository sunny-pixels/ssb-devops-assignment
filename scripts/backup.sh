#!/usr/bin/env bash
# backup.sh – back up the database (mysqldump) and the deployed app files (tar),
# verify both, write SHA-256 checksums, then delete backups older than
# BACKUP_RETENTION_DAYS.
#
#   ./scripts/backup.sh               manual run
#   cron/ssb-backup.cron              daily at 02:30
#
# Output in $BACKUP_DIR (dir 700, files 600):
#   ssb_db_<DB_NAME>_<YYYYmmdd-HHMMSS>.sql.gz  + .sha256
#   ssb_files_<YYYYmmdd-HHMMSS>.tar.gz         + .sha256
set -euo pipefail
umask 077                                   # backups contain data – owner only

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# ---- Pre-flight ------------------------------------------------------------
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found"
set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a

for var in DB_HOST DB_PORT DB_NAME BACKUP_DB_USER BACKUP_DB_PASS \
           LAMPP_HOME DEPLOY_DIR BACKUP_DIR BACKUP_RETENTION_DAYS; do
    [[ -n "${!var:-}" ]] || die "$var is not set in $ENV_FILE"
done
[[ "$BACKUP_DB_PASS" != change_me ]] || die "BACKUP_DB_PASS is still the placeholder"
[[ "$BACKUP_RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || die "BACKUP_RETENTION_DAYS must be a whole number >= 1"

MYSQLDUMP="$LAMPP_HOME/bin/mysqldump"
[[ -x "$MYSQLDUMP" ]] || die "mysqldump not found at $MYSQLDUMP"
for cmd in gzip zcat tar sha256sum flock find; do
    command -v "$cmd" >/dev/null || die "required command '$cmd' is not installed"
done
[[ -d "$DEPLOY_DIR" ]] || die "DEPLOY_DIR $DEPLOY_DIR does not exist – nothing to back up"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Only one backup at a time (a slow manual run must not overlap the cron run)
exec 9> "$BACKUP_DIR/.backup.lock"
flock -n 9 || die "another backup is already running"

TS="$(date +%Y%m%d-%H%M%S)"
DB_FILE="$BACKUP_DIR/ssb_db_${DB_NAME}_${TS}.sql.gz"
FILES_FILE="$BACKUP_DIR/ssb_files_${TS}.tar.gz"

# Credentials go in a temporary option file, never on the command line (visible in `ps`)
CNF="$(mktemp)"
trap 'rm -f "$CNF" "$DB_FILE.part" "$FILES_FILE.part"' EXIT   # no half-written backups
printf '[client]\nuser=%s\npassword=%s\nhost=%s\nport=%s\n' \
    "$BACKUP_DB_USER" "$BACKUP_DB_PASS" "$DB_HOST" "$DB_PORT" > "$CNF"

log "Backup started → $BACKUP_DIR"

# ---- 1. Database -----------------------------------------------------------
log "[1/4] mysqldump $DB_NAME as $BACKUP_DB_USER"
"$MYSQLDUMP" --defaults-extra-file="$CNF" \
    --single-transaction --quick --no-tablespaces \
    --default-character-set=utf8mb4 \
    "$DB_NAME" | gzip -9 > "$DB_FILE.part"

gzip -t "$DB_FILE.part"                     || die "database backup is not a valid gzip file"
zcat "$DB_FILE.part" | tail -n 1 | grep -q 'Dump completed' \
                                            || die "database dump is incomplete (no 'Dump completed' footer)"
tables="$(zcat "$DB_FILE.part" | grep -c '^CREATE TABLE' || true)"
(( tables > 0 ))                            || die "database dump contains no tables"
mv "$DB_FILE.part" "$DB_FILE"
log "      ok  $(basename "$DB_FILE")  ($tables table(s), $(du -h "$DB_FILE" | cut -f1))"

# ---- 2. Application files --------------------------------------------------
log "[2/4] tar $DEPLOY_DIR"
tar -C "$(dirname "$DEPLOY_DIR")" -czf "$FILES_FILE.part" "$(basename "$DEPLOY_DIR")"
files="$(tar -tzf "$FILES_FILE.part" | grep -vc '/$' || true)"
(( files > 0 ))                             || die "files backup is empty or unreadable"
mv "$FILES_FILE.part" "$FILES_FILE"
log "      ok  $(basename "$FILES_FILE")  ($files file(s), $(du -h "$FILES_FILE" | cut -f1))"

# ---- 3. Checksums ----------------------------------------------------------
log "[3/4] sha256 checksums"
for f in "$DB_FILE" "$FILES_FILE"; do
    ( cd "$BACKUP_DIR" && sha256sum "$(basename "$f")" > "$(basename "$f").sha256" )
done
log "      ok  verify later with: cd $BACKUP_DIR && sha256sum -c <file>.sha256"

# ---- 4. Retention (only after a successful backup) -------------------------
log "[4/4] retention: delete backups older than $BACKUP_RETENTION_DAYS day(s)"
deleted="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'ssb_*' \
           -mtime +"$BACKUP_RETENTION_DAYS" -print -delete)"
if [[ -n "$deleted" ]]; then
    echo "$deleted" | while read -r f; do log "      deleted  $(basename "$f")"; done
else
    log "      nothing to delete"
fi

log "Backup finished: $(find "$BACKUP_DIR" -maxdepth 1 -name 'ssb_*.gz' | wc -l) backup file(s) kept"
