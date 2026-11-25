#!/usr/bin/env bash
# create-db-user.sh – create/refresh the least-privilege app DB user from .env.
#
# Reads DB_PASS from .env (never from Git), substitutes it into
# database/create-app-user.sql and runs it as MySQL root (prompts for the root password).
#
# Usage:  ./scripts/create-db-user.sh            # uses ./.env
#         ENV_FILE=/path/to/.env ./scripts/create-db-user.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
SQL_FILE="$REPO_ROOT/database/create-app-user.sql"

die() { echo "ERROR: $*" >&2; exit 1; }

# ---- Pre-flight ------------------------------------------------------------
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found – run: cp .env.example .env && chmod 640 .env"
[[ -f "$SQL_FILE" ]] || die "$SQL_FILE not found"

set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a

LAMPP_HOME="${LAMPP_HOME:-/opt/lampp}"
MYSQL="$LAMPP_HOME/bin/mysql"
[[ -x "$MYSQL" ]] || die "mysql client not found at $MYSQL (set LAMPP_HOME in .env)"

: "${DB_NAME:?DB_NAME missing in $ENV_FILE}"
: "${DB_USER:?DB_USER missing in $ENV_FILE}"
: "${DB_PASS:?DB_PASS missing in $ENV_FILE}"

[[ "$DB_NAME" == "ssb_inventory" && "$DB_USER" == "ssb_app" ]] \
    || die "create-app-user.sql is written for ssb_inventory/ssb_app; .env has $DB_NAME/$DB_USER"
[[ "$DB_PASS" != "change_me" ]] || die "DB_PASS is still the placeholder – set a real one in .env"
(( ${#DB_PASS} >= 12 ))        || die "DB_PASS must be at least 12 characters"
# Restricting the charset keeps the sed substitution and SQL quoting safe
[[ "$DB_PASS" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "DB_PASS may only contain letters, digits, '.', '_' and '-'"

# ---- Run -------------------------------------------------------------------
echo "Creating/updating MySQL user '$DB_USER' with CRUD on '$DB_NAME' (enter MySQL ROOT password)"
sed "s|__DB_PASS__|$DB_PASS|g" "$SQL_FILE" | "$MYSQL" -u root -p --table
echo "Done. The password is NOT printed – it lives only in $ENV_FILE."
