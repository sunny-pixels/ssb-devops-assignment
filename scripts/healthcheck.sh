#!/usr/bin/env bash
# healthcheck.sh – is the stack up? Checks Apache, MySQL, the app and backups.
# Exit 0 = healthy, 1 = at least one check failed (usable from cron / monitoring).
#
#   ./scripts/healthcheck.sh        one line per check
#   ./scripts/healthcheck.sh -q     quiet: print only on failure (for cron)
set -uo pipefail          # no -e: run every check, then decide

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
QUIET=0; [[ "${1:-}" == "-q" ]] && QUIET=1

[[ -f "$ENV_FILE" ]] || { echo "$(date '+%F %T') FAIL  $ENV_FILE not found"; exit 1; }
set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a
LAMPP_HOME="${LAMPP_HOME:-/opt/lampp}"
APP_URL="${APP_URL:-http://localhost/ssb-app}"
MAX_BACKUP_AGE_H="${MAX_BACKUP_AGE_H:-26}"     # daily cron + 2 h slack
DISK_LIMIT_PCT="${DISK_LIMIT_PCT:-90}"

results=(); failed=0
pass() { results+=("  ok    $1"); }
fail() { results+=("  FAIL  $1"); failed=$((failed + 1)); }
listening() { [[ -n "$(ss -Htln "sport = :$1" 2>/dev/null)" ]]; }

# ---- Apache -----------------------------------------------------------------
if pgrep -f "$LAMPP_HOME/bin/httpd" >/dev/null && listening 80; then
    pass "apache   running, port 80 listening"
else
    fail "apache   not running or port 80 not listening"
fi

# ---- MySQL (ping as the read-only backup user; password via temp option file) ----
if listening "${DB_PORT:-3306}"; then
    cnf="$(mktemp)"
    printf '[client]\nuser=%s\npassword=%s\nhost=%s\nport=%s\n' \
        "${BACKUP_DB_USER:-}" "${BACKUP_DB_PASS:-}" "${DB_HOST:-127.0.0.1}" "${DB_PORT:-3306}" > "$cnf"
    # mysqladmin ping exits 0 whenever the server is up – even if the login is refused
    if out="$("$LAMPP_HOME/bin/mysqladmin" --defaults-extra-file="$cnf" --connect-timeout=3 ping 2>&1)"; then
        if [[ "$out" == *alive* ]]; then
            pass "mysql    $out"
        else
            pass "mysql    server up (ping login refused – check BACKUP_DB_* in .env)"
        fi
    else
        fail "mysql    port open but server not answering: ${out##*: }"
    fi
    rm -f "$cnf"
else
    fail "mysql    port ${DB_PORT:-3306} not listening (stopped?)"
fi

# ---- App (health.php checks PHP extensions, config and the DB as the app user) ----
body="$(curl -s --max-time 5 -w '\n%{http_code}' "$APP_URL/health.php" 2>/dev/null)"
code="${body##*$'\n'}"
if [[ "$code" == 200 ]] && grep -q '"status": "ok"' <<< "$body"; then
    pass "app      $APP_URL/health.php → 200"
else
    db="$(grep -o '"database": "[^"]*"' <<< "$body" || true)"
    fail "app      $APP_URL/health.php → HTTP ${code:-000} ${db}"
fi

# ---- Backups ----------------------------------------------------------------
latest="$(find "${BACKUP_DIR:-/nonexistent}" -maxdepth 1 -name 'ssb_db_*.sql.gz' -printf '%T@\n' 2>/dev/null | sort -n | tail -1)"
if [[ -n "$latest" ]]; then
    age_h=$(( ( $(date +%s) - ${latest%.*} ) / 3600 ))
    if (( age_h <= MAX_BACKUP_AGE_H )); then
        pass "backup   latest DB backup is ${age_h} h old"
    else
        fail "backup   latest DB backup is ${age_h} h old (> ${MAX_BACKUP_AGE_H} h – cron not running?)"
    fi
else
    fail "backup   no DB backup found in ${BACKUP_DIR:-?}"
fi

# ---- Disk -------------------------------------------------------------------
for path in "$LAMPP_HOME" "${BACKUP_DIR:-$HOME}"; do
    use="$(df --output=pcent "$path" 2>/dev/null | tail -1 | tr -dc '0-9')"
    if [[ -n "$use" ]] && (( use < DISK_LIMIT_PCT )); then
        pass "disk     $path ${use}% used"
    else
        fail "disk     $path ${use:-?}% used (limit ${DISK_LIMIT_PCT}%)"
    fi
done

# ---- Report -----------------------------------------------------------------
if (( failed > 0 || QUIET == 0 )); then
    echo "$(date '+%F %T') healthcheck $(hostname): $([[ $failed -eq 0 ]] && echo HEALTHY || echo "UNHEALTHY ($failed failed)")"
    printf '%s\n' "${results[@]}"
fi
(( failed == 0 ))
