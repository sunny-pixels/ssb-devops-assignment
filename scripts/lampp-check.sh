#!/usr/bin/env bash
# lampp-check.sh – one-shot evidence report for the LAMPP stack:
# service status, versions, listening ports, log locations (+ last lines) and HTTP health.
#
# Usage:  sudo ./scripts/lampp-check.sh [APP_URL]
#         sudo ./scripts/lampp-check.sh | tee ~/lampp-check.txt
set -euo pipefail

LAMPP_HOME="${LAMPP_HOME:-/opt/lampp}"
APP_URL="${1:-${APP_URL:-http://localhost/ssb-app}}"

section() { printf '\n==================== %s ====================\n' "$1"; }
die()     { echo "ERROR: $*" >&2; exit 1; }

# ---- Pre-flight ------------------------------------------------------------
[[ $EUID -eq 0 ]]              || die "run with sudo (needed for lampp status and ss -p)"
[[ -x "$LAMPP_HOME/lampp" ]]   || die "LAMPP not found at $LAMPP_HOME (set LAMPP_HOME)"
for cmd in ss curl; do
    command -v "$cmd" >/dev/null || die "required command '$cmd' not installed"
done

section "Host"
echo "Date     : $(date '+%F %T %Z')"
echo "Hostname : $(hostname)"
# shellcheck source=/dev/null
echo "OS       : $(. /etc/os-release && echo "$PRETTY_NAME")"

section "LAMPP service status"
"$LAMPP_HOME/lampp" status

section "Component versions"
"$LAMPP_HOME/bin/httpd" -v | head -1
"$LAMPP_HOME/bin/php" -v | head -1
"$LAMPP_HOME/bin/mysql" --version

section "Listening ports (80 http, 443 https, 3306 mysql, 21 ftp)"
ss -tlnp | awk 'NR==1 || /:(80|443|3306|21)[[:space:]]/'

section "Key config files"
for f in etc/httpd.conf etc/extra/httpd-xampp.conf etc/php.ini etc/my.cnf; do
    printf '%-32s %s\n' "$f" "$([[ -f $LAMPP_HOME/$f ]] && echo present || echo MISSING)"
done
echo "Apache runs as: $(grep -E '^(User|Group) ' "$LAMPP_HOME/etc/httpd.conf" | tr '\n' ' ')"

section "Log locations"
php_err=$(grep -E '^\s*error_log\s*=' "$LAMPP_HOME/etc/php.ini" | tail -1 | cut -d= -f2- | xargs || true)
mysql_err=$(find "$LAMPP_HOME/var/mysql" -maxdepth 1 -name '*.err' 2>/dev/null | head -1 || true)
echo "Apache access : $LAMPP_HOME/logs/access_log"
echo "Apache error  : $LAMPP_HOME/logs/error_log"
echo "PHP errors    : ${php_err:-Apache error_log (php.ini error_log not set)}"
echo "MySQL error   : ${mysql_err:-not found under $LAMPP_HOME/var/mysql/}"

for log in "$LAMPP_HOME/logs/error_log" "$mysql_err"; do
    [[ -n "$log" && -f "$log" ]] || continue
    echo; echo "--- last 5 lines: $log"
    tail -n 5 "$log"
done

section "HTTP health check: $APP_URL/health.php"
code=$(curl -s -o /tmp/health.json -w '%{http_code}' "$APP_URL/health.php" || true)
echo "HTTP $code"
cat /tmp/health.json 2>/dev/null || true
rm -f /tmp/health.json

if [[ "$code" == "200" ]]; then
    echo -e "\nRESULT: PASS"
else
    echo -e "\nRESULT: FAIL"
    exit 1
fi
