#!/usr/bin/env bash
# restore.sh – restore a database backup made by backup.sh and verify it.
#
#   ./scripts/restore.sh --latest                      newest backup → ssb_inventory_restore_test
#   ./scripts/restore.sh <file.sql.gz>                 that backup   → ssb_inventory_restore_test
#   ./scripts/restore.sh <file.sql.gz|--latest> <db>   into another database
#
# Default target is a separate TEST database, so a restore can be verified without
# touching live data. Restoring into the live database (DB_NAME) asks you to type its
# name to confirm. Runs as MySQL root (password prompted) because it creates databases.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
step() { printf '\n[%s] %s\n' "$1" "$2"; }

[[ $# -ge 1 && $# -le 2 ]] || die "usage: $0 <backup.sql.gz | --latest> [target_database]"

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found"
set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a
: "${DB_NAME:?DB_NAME missing in $ENV_FILE}"
: "${BACKUP_DIR:?BACKUP_DIR missing in $ENV_FILE}"
MYSQL="${LAMPP_HOME:-/opt/lampp}/bin/mysql"
[[ -x "$MYSQL" ]] || die "mysql client not found at $MYSQL"

# -----------------------------------------------------------------------------
step 1/5 "Check the backup file"
if [[ "$1" == --latest ]]; then
    DUMP="$(find "$BACKUP_DIR" -maxdepth 1 -name "ssb_db_${DB_NAME}_*.sql.gz" | sort | tail -n 1)"
    [[ -n "$DUMP" ]] || die "no database backups found in $BACKUP_DIR"
else
    DUMP="$1"
fi
[[ -f "$DUMP" ]] || die "backup file not found: $DUMP"
echo "  file      $DUMP"

if [[ -f "$DUMP.sha256" ]]; then
    ( cd "$(dirname "$DUMP")" && sha256sum -c --quiet "$(basename "$DUMP").sha256" ) \
        || die "checksum mismatch – the backup file is corrupted or was modified"
    echo "  ok        sha256 checksum matches"
else
    echo "  warning   no .sha256 file – skipping checksum"
fi
gzip -t "$DUMP" || die "not a valid gzip file"
zcat "$DUMP" | tail -n 1 | grep -q 'Dump completed' || die "dump is incomplete"
echo "  ok        gzip valid, dump complete"

TARGET="${2:-${DB_NAME}_restore_test}"
[[ "$TARGET" =~ ^[A-Za-z0-9_]+$ ]] || die "invalid database name '$TARGET'"
echo "  target    $TARGET"

if [[ "$TARGET" == "$DB_NAME" ]]; then
    echo
    echo "  !! This OVERWRITES the LIVE database '$DB_NAME' with the backup."
    read -r -p "  Type the database name to confirm: " confirm
    [[ "$confirm" == "$DB_NAME" ]] || die "confirmation did not match – nothing changed"
fi

# -----------------------------------------------------------------------------
step 2/5 "MySQL root login"
read -r -s -p "  MySQL root password: " ROOT_PASS; echo
CNF="$(mktemp)"
trap 'rm -f "$CNF"' EXIT
printf '[client]\nuser=root\npassword=%s\n' "$ROOT_PASS" > "$CNF"
unset ROOT_PASS
sql() { "$MYSQL" --defaults-extra-file="$CNF" "$@"; }
sql -e 'SELECT 1' >/dev/null 2>&1 || die "root login failed – wrong password?"
echo "  ok"

# -----------------------------------------------------------------------------
step 3/5 "Prepare database $TARGET"
if [[ "$TARGET" == "$DB_NAME" ]]; then
    echo "  live database: tables are replaced (the dump contains DROP TABLE IF EXISTS)"
else
    sql -e "DROP DATABASE IF EXISTS \`$TARGET\`;
            CREATE DATABASE \`$TARGET\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    echo "  ok  (re)created empty database"
fi

# -----------------------------------------------------------------------------
step 4/5 "Restore"
zcat "$DUMP" | sql "$TARGET"
echo "  ok  dump imported"

# -----------------------------------------------------------------------------
step 5/5 "Verify"
mapfile -t tables < <(sql -N -B -e \
    "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$TARGET' ORDER BY TABLE_NAME;")
(( ${#tables[@]} > 0 )) || die "restored database has no tables"

printf '  %-12s %10s %10s   %s\n' "table" "restored" "live" "data checksum"
for t in "${tables[@]}"; do
    restored="$(sql -N -B -e "SELECT COUNT(*) FROM \`$TARGET\`.\`$t\`;")"
    if [[ "$TARGET" == "$DB_NAME" ]]; then
        printf '  %-12s %10s %10s   %s\n' "$t" "$restored" "-" "(restored into live)"
        continue
    fi
    live="$(sql -N -B -e "SELECT COUNT(*) FROM \`$DB_NAME\`.\`$t\`;" 2>/dev/null || echo "n/a")"
    sums="$(sql -N -B -e "CHECKSUM TABLE \`$TARGET\`.\`$t\`, \`$DB_NAME\`.\`$t\`;" 2>/dev/null | cut -f2 | sort -u | wc -l)"
    verdict=$([[ "$sums" == 1 ]] && echo "MATCH" || echo "differs (live changed since the backup?)")
    printf '  %-12s %10s %10s   %s\n' "$t" "$restored" "$live" "$verdict"
done

echo
echo "  Sample rows from $TARGET.items:"
sql --table -e "SELECT id, sku, name, quantity, unit_price FROM \`$TARGET\`.items ORDER BY id LIMIT 5;"

echo
echo "Restore of $(basename "$DUMP") into '$TARGET' complete."
[[ "$TARGET" == "$DB_NAME" ]] || echo "Remove the test copy when done:  $MYSQL -u root -p -e 'DROP DATABASE \`$TARGET\`;'"
