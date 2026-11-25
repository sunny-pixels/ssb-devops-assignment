#!/usr/bin/env bash
# security-audit.sh – re-check the security and permission controls from phases 1–5.
# Prints PASS/FAIL per check and exits 1 if any check fails.
#
#   ./scripts/security-audit.sh          (uses sudo for root-owned paths)
set -uo pipefail          # no -e: every check runs even if an earlier one fails

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
APP_ENV_DIR="/etc/ssb-app"
APP_ENV_FILE="$APP_ENV_DIR/app.env"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }
set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a
LAMPP_HOME="${LAMPP_HOME:-/opt/lampp}"
ME="$(id -un)"; MY_GROUP="$(id -gn)"

fails=0
section() { printf '\n%s\n' "$1"; }
check() {                                   # check "description" command [args…]
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  PASS  %s\n' "$desc"
    else
        printf '  FAIL  %s\n' "$desc"; fails=$((fails + 1))
    fi
}

# ---- helpers ----------------------------------------------------------------
mode_is()      { [[ "$(stat -c '%a %U:%G' "$1")" == "$2" ]]; }
sudo_mode_is() { [[ "$(sudo stat -c '%a %U:%G' "$1")" == "$2" ]]; }
none_found()   { [[ -z "$("$@" 2>/dev/null)" ]]; }   # true when the command prints nothing

git_never_tracked_env() { [[ -z "$(git -C "$REPO_ROOT" log --all --format=%h -- .env)" ]]; }
git_no_real_password()  {                   # 12+ char value after DB_PASS= in ANY commit
    ! git -C "$REPO_ROOT" rev-list --all \
        | xargs git -C "$REPO_ROOT" grep -qE '^(BACKUP_)?DB_PASS=[A-Za-z0-9._-]{12,}'
}

deploy_modes_ok() {                         # files 640, dirs 750 everywhere in the web app
    none_found find "$DEPLOY_DIR" \( -type f ! -perm 640 \) -o \( -type d ! -perm 750 \)
}
backup_modes_ok() {
    mode_is "$BACKUP_DIR" "700 $ME:$MY_GROUP" &&
    none_found find "$BACKUP_DIR" -type f ! -perm 600
}
no_world_writable() {
    none_found find "$DEPLOY_DIR" "$REPO_ROOT" "$BACKUP_DIR" -xdev -perm -o+w ! -type l &&
    [[ -z "$(sudo find "$APP_ENV_DIR" -perm -o+w 2>/dev/null)" ]]
}

http_code()     { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$APP_URL/$1"; }
web_blocked()   { [[ "$(http_code "$1")" == 403 ]]; }
env_files_blocked() { web_blocked .env && web_blocked app.env; }

mysql_only_loopback() {
    local addrs; addrs="$(ss -Htln 'sport = :3306' | awk '{print $4}')"
    [[ -n "$addrs" ]] && ! grep -qv '^127\.0\.0\.1:' <<< "$addrs"
}
mysql_as() {                                # mysql_as USER PASS "SQL" – password via temp option file
    local cnf rc; cnf="$(mktemp)"
    printf '[client]\nuser=%s\npassword=%s\nhost=%s\nport=%s\n' "$1" "$2" "$DB_HOST" "$DB_PORT" > "$cnf"
    "$LAMPP_HOME/bin/mysql" --defaults-extra-file="$cnf" -N -B -e "$3"; rc=$?
    rm -f "$cnf"; return $rc
}
only_privileges() {                         # only_privileges USER PASS 'ALLOWED','LIST'
    local extra
    extra="$(mysql_as "$1" "$2" "SELECT
        (SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES   WHERE PRIVILEGE_TYPE <> 'USAGE') +
        (SELECT COUNT(*) FROM information_schema.SCHEMA_PRIVILEGES WHERE PRIVILEGE_TYPE NOT IN ($3));")" || return 1
    [[ "$extra" == 0 ]]
}
no_test_db_visible() {
    local dbs; dbs="$(mysql_as "$DB_USER" "$DB_PASS" 'SHOW DATABASES;')" || return 1
    ! grep -qx 'test' <<< "$dbs"
}

# ---- checks -----------------------------------------------------------------
echo "Security audit – $(hostname) – $(date '+%F %T %Z')"
sudo -v || { echo "ERROR: sudo is required for the /etc/ssb-app checks" >&2; exit 1; }

section "Secrets"
check ".env is git-ignored"                              git -C "$REPO_ROOT" check-ignore -q .env
check ".env never appears in Git history"                git_never_tracked_env
check "no real DB password in any commit"                git_no_real_password
check ".env is 640 $ME:$MY_GROUP"                        mode_is "$ENV_FILE" "640 $ME:$MY_GROUP"
check "$APP_ENV_DIR is 750 root:daemon"                  sudo_mode_is "$APP_ENV_DIR" "750 root:daemon"
check "$APP_ENV_FILE is 640 root:daemon"                 sudo_mode_is "$APP_ENV_FILE" "640 root:daemon"

section "File permissions"
check "web app dir is 750 $ME:daemon"                    mode_is "$DEPLOY_DIR" "750 $ME:daemon"
check "web app files 640 / dirs 750 (Apache read-only)"  deploy_modes_ok
check "backups dir 700, backup files 600"                backup_modes_ok
check "nothing world-writable (app, repo, backups, config)" no_world_writable
check "phpinfo test page removed"                        test ! -e "$LAMPP_HOME/htdocs/info.php"

section "Web exposure"
check "inc/config.php not downloadable (403)"            web_blocked inc/config.php
check ".env / app.env not downloadable (403)"            env_files_blocked
check "no directory listing on assets/ (403)"            web_blocked assets/
check "phpMyAdmin limited to the Windows host IP"        grep -q '^\s*Require ip 192\.168\.198\.1' "$LAMPP_HOME/etc/extra/httpd-xampp.conf"

section "Database"
check "MySQL listens on 127.0.0.1 only"                  mysql_only_loopback
check "app user is not root ($DB_USER)"                  test "$DB_USER" != root
check "$DB_USER has only SELECT/INSERT/UPDATE/DELETE"    only_privileges "$DB_USER" "$DB_PASS" "'SELECT','INSERT','UPDATE','DELETE'"
check "${BACKUP_DB_USER:-ssb_backup} is read-only"       only_privileges "${BACKUP_DB_USER:-}" "${BACKUP_DB_PASS:-}" "'SELECT','SHOW VIEW','TRIGGER','LOCK TABLES'"
check "XAMPP 'test' DB gone (not visible to app user)"   no_test_db_visible

echo
if (( fails == 0 )); then
    echo "RESULT: all checks passed"
else
    echo "RESULT: $fails check(s) FAILED"; exit 1
fi
