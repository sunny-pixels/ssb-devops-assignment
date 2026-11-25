#!/usr/bin/env bash
# create-db-user.sh – create/refresh a least-privilege MySQL user from .env.
#
#   ./scripts/create-db-user.sh          # app user    ssb_app    (CRUD)      ← DB_PASS
#   ./scripts/create-db-user.sh backup   # backup user ssb_backup (read-only) ← BACKUP_DB_PASS
#
# The password is read from .env (never from Git), validated, substituted into the
# matching database/create-*-user.sql and run as MySQL root (prompts for the root password).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

die() { echo "ERROR: $*" >&2; exit 1; }

case "${1:-app}" in
    app)    SQL_FILE="$REPO_ROOT/database/create-app-user.sql"
            USER_VAR=DB_USER;        PASS_VAR=DB_PASS;        EXPECTED_USER=ssb_app
            PLACEHOLDER=__DB_PASS__ ;;
    backup) SQL_FILE="$REPO_ROOT/database/create-backup-user.sql"
            USER_VAR=BACKUP_DB_USER; PASS_VAR=BACKUP_DB_PASS; EXPECTED_USER=ssb_backup
            PLACEHOLDER=__BACKUP_DB_PASS__ ;;
    *)      die "usage: $0 [app|backup]" ;;
esac

# ---- Pre-flight ------------------------------------------------------------
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found – run: cp .env.example .env && chmod 640 .env"
[[ -f "$SQL_FILE" ]] || die "$SQL_FILE not found"

set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a

LAMPP_HOME="${LAMPP_HOME:-/opt/lampp}"
MYSQL="$LAMPP_HOME/bin/mysql"
[[ -x "$MYSQL" ]] || die "mysql client not found at $MYSQL (set LAMPP_HOME in .env)"

: "${DB_NAME:?DB_NAME missing in $ENV_FILE}"
DB_USER_VALUE="${!USER_VAR:-}"
PASS="${!PASS_VAR:-}"
[[ -n "$DB_USER_VALUE" ]] || die "$USER_VAR missing in $ENV_FILE"
[[ -n "$PASS" ]]          || die "$PASS_VAR missing in $ENV_FILE"

[[ "$DB_NAME" == "ssb_inventory" && "$DB_USER_VALUE" == "$EXPECTED_USER" ]] \
    || die "$(basename "$SQL_FILE") is written for ssb_inventory/$EXPECTED_USER; .env has $DB_NAME/$DB_USER_VALUE"
[[ "$PASS" != "change_me" ]] || die "$PASS_VAR is still the placeholder – set a real one in .env"
(( ${#PASS} >= 12 ))         || die "$PASS_VAR must be at least 12 characters"
# Restricting the charset keeps the sed substitution and SQL quoting safe
[[ "$PASS" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "$PASS_VAR may only contain letters, digits, '.', '_' and '-'"

# ---- Run -------------------------------------------------------------------
echo "Creating/updating MySQL user '$DB_USER_VALUE' on '$DB_NAME' (enter MySQL ROOT password)"
sed "s|$PLACEHOLDER|$PASS|g" "$SQL_FILE" | "$MYSQL" -u root -p --table
echo "Done. The password is NOT printed – it lives only in $ENV_FILE."
