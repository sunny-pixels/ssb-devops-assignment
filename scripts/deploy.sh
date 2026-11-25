#!/usr/bin/env bash
# deploy.sh – deploy the PHP app from the Git working copy to the Apache web root with rsync.
#
#   ./scripts/deploy.sh            validate → dry-run preview → confirm → deploy → health check
#   ./scripts/deploy.sh --dry-run  validate + preview only (changes nothing)
#   ./scripts/deploy.sh --yes      deploy without the confirmation prompt (automation)
#
# Settings come from .env: SOURCE_DIR, DEPLOY_DIR, LAMPP_HOME, APP_URL.
# Run as your normal user – sudo is used only for the steps that need it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
APP_ENV_FILE="${APP_ENV_FILE:-/etc/ssb-app/app.env}"   # DB config read by PHP (Phase 3)
WEB_USER="${WEB_USER:-daemon}"                          # XAMPP's Apache runs as daemon:daemon
WEB_GROUP="${WEB_GROUP:-daemon}"
DEPLOY_LOG="$REPO_ROOT/logs/deploy.log"

# Never shipped to the web root. Excluded paths are also protected from --delete.
EXCLUDES=(
    .git/ .gitignore .gitattributes          # version control
    .env '*.env' '.env.*'                    # secrets / config
    logs/ '*.log'                            # logs
    backups/ '*.sql' '*.sql.gz' '*.tar.gz'   # local backups and dumps
    '*.bak' '*.orig' '*.swp' '*~'            # editor / temp files
    .DS_Store Thumbs.db .vscode/ .idea/
    REVISION                                 # written by this script after each deploy
)

die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf '  WARNING: %s\n' "$*" >&2; }
step() { printf '\n[%s] %s\n' "$1" "$2"; }

MODE=deploy
case "${1:-}" in
    "")            ;;
    --dry-run|-n)  MODE=dry-run ;;
    --yes|-y)      MODE=yes ;;
    --help|-h)     sed -n '2,9p' "$0"; exit 0 ;;
    *)             die "unknown option '$1' (use --dry-run, --yes or --help)" ;;
esac

# -----------------------------------------------------------------------------
step 1/6 "Pre-flight checks"
(( EUID != 0 )) || die "run as your normal user, not root – the script calls sudo where needed"

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found – run: cp .env.example .env && chmod 640 .env"
set -a; # shellcheck disable=SC1090
. "$ENV_FILE"; set +a

for var in SOURCE_DIR DEPLOY_DIR LAMPP_HOME APP_URL; do
    [[ -n "${!var:-}" ]] || die "$var is not set in $ENV_FILE"
done
SOURCE_DIR="${SOURCE_DIR%/}"
DEPLOY_DIR="${DEPLOY_DIR%/}"

for cmd in rsync curl git sudo find; do
    command -v "$cmd" >/dev/null || die "required command '$cmd' is not installed"
done
PHP="$LAMPP_HOME/bin/php"
[[ -x "$PHP" ]] || die "PHP CLI not found at $PHP (check LAMPP_HOME)"

[[ -d "$SOURCE_DIR" ]] || die "SOURCE_DIR $SOURCE_DIR does not exist"
for f in index.php health.php .htaccess inc/.htaccess inc/bootstrap.php inc/config.php inc/db.php; do
    [[ -f "$SOURCE_DIR/$f" ]] || die "required file missing in source: $SOURCE_DIR/$f"
done

# --delete removes files in the target, so be strict about where the target is
[[ -d "$LAMPP_HOME/htdocs" ]] || die "web root $LAMPP_HOME/htdocs does not exist"
[[ "$DEPLOY_DIR" == "$LAMPP_HOME"/htdocs/?* && "$DEPLOY_DIR" != *..* ]] \
    || die "DEPLOY_DIR must be a sub-folder of $LAMPP_HOME/htdocs (got '$DEPLOY_DIR')"
[[ "$SOURCE_DIR" != "$DEPLOY_DIR" ]] || die "SOURCE_DIR and DEPLOY_DIR are the same folder"

sudo test -f "$APP_ENV_FILE" \
    || die "app config $APP_ENV_FILE is missing – see docs/03-php-app.md step 3.2"
sudo -u "$WEB_USER" test -r "$APP_ENV_FILE" \
    || die "$APP_ENV_FILE is not readable by the web server user '$WEB_USER'"

echo "  ok  source  $SOURCE_DIR"
echo "  ok  target  $DEPLOY_DIR"
echo "  ok  config  $APP_ENV_FILE (readable by $WEB_USER)"

# -----------------------------------------------------------------------------
step 2/6 "PHP syntax check"
lint_failed=0
while IFS= read -r -d '' file; do
    if ! out=$("$PHP" -l "$file" 2>&1); then
        echo "$out" >&2
        lint_failed=1
    fi
done < <(find "$SOURCE_DIR" -name '*.php' -print0)
(( lint_failed == 0 )) || die "PHP syntax errors – nothing deployed"
echo "  ok  $(find "$SOURCE_DIR" -name '*.php' | wc -l) PHP files"

# -----------------------------------------------------------------------------
step 3/6 "Release"
REVISION="$(git -C "$REPO_ROOT" describe --tags --always --dirty)"
modified="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no -- "$SOURCE_DIR")"
untracked="$(git -C "$REPO_ROOT" ls-files --others --exclude-standard -- "$SOURCE_DIR")"
if [[ -n "$modified" ]]; then
    warn "uncommitted edits to tracked files in app/ will be deployed (revision ends in -dirty)"
fi
if [[ -n "$untracked" ]]; then
    warn "untracked files in app/ (deployed unless they match an exclude): $(echo "$untracked" | xargs -n1 basename | paste -sd' ')"
fi
echo "  revision  $REVISION"

# -----------------------------------------------------------------------------
step 4/6 "Preview (rsync --dry-run)"
DEPLOY_OWNER="$(id -un)"
RSYNC_OPTS=(
    --archive --delete --itemize-changes
    --omit-dir-times                     # folder mtimes change whenever a file inside is
                                         # added/removed (e.g. REVISION) – not a real change
    --chown="$DEPLOY_OWNER:$WEB_GROUP"   # owner can update, Apache group can only read
    --chmod=D750,F640                    # nothing world-readable or writable
)
for pattern in "${EXCLUDES[@]}"; do
    RSYNC_OPTS+=(--exclude="$pattern")
done

changes="$(sudo rsync --dry-run "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$DEPLOY_DIR/")"

if [[ -z "$changes" ]]; then
    echo "  Nothing to deploy – $DEPLOY_DIR already matches $SOURCE_DIR."
    count=0
else
    echo "$changes" | sed 's/^/  /'
    count="$(grep -c . <<< "$changes")"
    echo "  -- $count change(s).  >f+++++++ new file · >f.st.... content changed ·"
    echo "     .f...p.g.. only permissions (p) / owner (o) / group (g) · *deleting removed from target"
fi

if [[ "$MODE" == dry-run ]]; then
    echo
    echo "Dry run only – nothing was changed."
    exit 0
fi

# -----------------------------------------------------------------------------
step 5/6 "Deploy"
if (( count > 0 )); then
    if [[ "$MODE" != yes ]]; then
        [[ -t 0 ]] || die "no terminal to confirm – re-run with --yes"
        read -r -p "  Deploy these $count change(s) to $DEPLOY_DIR? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "  Aborted – nothing changed."; exit 1; }
    fi
    sudo rsync "${RSYNC_OPTS[@]}" --stats "$SOURCE_DIR/" "$DEPLOY_DIR/" \
        | grep -E 'Number of (regular files transferred|deleted files)|Total transferred file size' \
        | sed 's/^/  /'
fi

printf '%s\n' "$REVISION" | sudo tee "$DEPLOY_DIR/REVISION" >/dev/null
sudo chown "$DEPLOY_OWNER:$WEB_GROUP" "$DEPLOY_DIR/REVISION"
sudo chmod 640 "$DEPLOY_DIR/REVISION"
echo "  ok  REVISION = $REVISION"

# -----------------------------------------------------------------------------
step 6/6 "Health check"
health_body="$(mktemp)"
trap 'rm -f "$health_body"' EXIT
code="$(curl -s -o "$health_body" -w '%{http_code}' --max-time 10 "$APP_URL/health.php" || true)"

mkdir -p "$(dirname "$DEPLOY_LOG")"
printf '%s user=%s rev=%s changes=%s health=%s\n' \
    "$(date -Iseconds)" "$DEPLOY_OWNER" "$REVISION" "$count" "$code" >> "$DEPLOY_LOG"

if [[ "$code" != 200 ]]; then
    cat "$health_body" >&2 || true
    die "deployed, but $APP_URL/health.php returned HTTP $code – check /opt/lampp/logs/php_error_log"
fi
grep -E '"(status|database|revision)"' "$health_body" | sed 's/^ */  /'
echo
echo "Deployed $REVISION to $DEPLOY_DIR – health check HTTP 200."
