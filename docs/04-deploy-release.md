# Phase 4 – Rsync Deployment & Release Flow (Assignment sections D + E)

`scripts/deploy.sh` copies `app/` from the Git working copy to the Apache web root.

```
~/ssb-devops-assignment/app/      ──rsync──▶   /opt/lampp/htdocs/ssb-app/
(SOURCE_DIR, Git working copy)                 (DEPLOY_DIR, served by Apache)
```

## What the script does
| Step | Checks / actions | Fails clearly when… |
|---|---|---|
| 1 Pre-flight | `.env` loaded; `SOURCE_DIR`, `DEPLOY_DIR`, `LAMPP_HOME`, `APP_URL` set; `rsync curl git sudo find` installed; required app files present; `DEPLOY_DIR` is **inside** `htdocs` (guards `--delete`); `/etc/ssb-app/app.env` exists and Apache can read it | any of these is missing / wrong, or run as root |
| 2 Lint | `php -l` on every `.php` file | a syntax error – nothing is deployed |
| 3 Release | `git describe --tags --always --dirty` → revision; warns on uncommitted changes | – |
| 4 Preview | `rsync --dry-run --itemize-changes` – lists exactly what would change | – |
| 5 Deploy | asks `[y/N]` (or `--yes`), runs rsync, writes `REVISION` | answer is not `y` |
| 6 Verify | `curl health.php` must return 200; appends a line to `logs/deploy.log` | health ≠ 200 (exit 1) |

**rsync options**
| Option | Why |
|---|---|
| `--archive` | recurse, keep timestamps/links → unchanged files are skipped (size + mtime) |
| `--delete` | remove files from the target that were deleted in Git |
| `--itemize-changes` | one line per changed file → readable preview and audit |
| `--omit-dir-times` | ignore folder timestamps – see the note below |
| `--chown=ssbadmin:daemon --chmod=D750,F640` | deploy user owns the code, Apache can only **read** it, others nothing |
| `--exclude` | `.git/ .gitignore .gitattributes .env *.env logs/ *.log backups/ *.sql *.sql.gz *.tar.gz *.bak *.orig *.swp *~ .vscode/ .idea/ REVISION` |

Modes: `./scripts/deploy.sh` (interactive) · `--dry-run` (preview only) · `--yes` (no prompt).

---

## 4.1 Pull and show that the script fails clearly
```bash
cd ~/ssb-devops-assignment && git pull
ENV_FILE=/tmp/missing.env ./scripts/deploy.sh --dry-run    # → ERROR: /tmp/missing.env not found
sudo ./scripts/deploy.sh --dry-run                         # → ERROR: run as your normal user, not root
```

## 4.2 Dry run
```bash
./scripts/deploy.sh --dry-run
```
First run after the manual copy of Phase 3: `health.php` shows as **content changed**
(`>f.stp.g...`) and the other 12 entries as **permissions + group only** (`.f...p.g...`) – they
move from `ssbadmin:ssbadmin 644` to `ssbadmin:daemon 640` (owner stays `ssbadmin`, so no `o`).
Ends with *"Dry run only – nothing was changed."*

How to read an itemize line: `>` = file will be sent, `.` = not sent (attributes only),
`c` = created; then `s` size, `t` time, `p` permissions, `o` owner, `g` group differ.

## 4.3 Deploy
```bash
./scripts/deploy.sh                 # answer y
sudo ls -la /opt/lampp/htdocs/ssb-app /opt/lampp/htdocs/ssb-app/inc
cat logs/deploy.log
```
Ends with *"Deployed … – health check HTTP 200."*; files are `-rw-r----- ssbadmin daemon`.

> **Found while testing:** the first no-change dry run still reported `.d..t...... ./`
> (`screenshots/04-dir-mtime-noise.png`). Writing `REVISION` into the target after rsync
> bumped the folder's mtime – and any file added/removed under `app/` does the same – so the
> preview showed a "change" with no content difference. Fixed by adding `--omit-dir-times`.

## 4.4 Nothing changed → nothing transferred
```bash
./scripts/deploy.sh --dry-run       # → "Nothing to deploy"
```

## 4.5 Excludes work
Create files that must never reach the web root, then preview:
```bash
touch app/debug.log app/notes.bak
printf 'DB_PASS=fake-for-test\n' > app/.env
mkdir -p app/backups && touch app/backups/old.sql.gz
./scripts/deploy.sh --dry-run       # → still "Nothing to deploy" (none of them listed)
rm -rf app/debug.log app/notes.bak app/.env app/backups
```

Only `notes.bak` is visible to Git (`.env`, `*.log`, `backups/` are git-ignored too). The first
version of the script warned *"uncommitted changes … will be deployed (revision marked -dirty)"*
here – wrong on both counts, since the file is excluded and untracked files don't make a revision
dirty. The warning now distinguishes **edited tracked files** (→ `-dirty`) from **untracked
files** (named, "deployed unless they match an exclude").

## 4.6 Update: only the changed file is transferred
A one-file change is committed (`app/index.php`), then on the VM:
```bash
git pull
./scripts/deploy.sh --dry-run       # → exactly one line: >f.st...... index.php
./scripts/deploy.sh                 # → Number of regular files transferred: 1
```

## 4.7 Tag the tested release
After 4.6 is verified in the browser:
```bash
git tag -a v1.0.0 -m "v1.0.0 – inventory app, deploy script, DB scripts"
git push origin v1.0.0
./scripts/deploy.sh                 # no file changes; REVISION becomes v1.0.0
curl -s http://localhost/ssb-app/health.php | grep revision
```

**Rollback** to a tagged release:
```bash
git checkout v1.0.0 && ./scripts/deploy.sh && git checkout main
```

---

## Evidence
| File | Shows |
|---|---|
| `screenshots/04-fail-clearly.png` | 4.1 – missing `.env` and run-as-root both refused |
| `screenshots/04-dry-run.png` | 4.2 – itemized preview, nothing changed |
| `screenshots/04-deploy.png` | 4.3 – confirm, stats, REVISION, health 200 |
| `screenshots/04-deployed-files.png` | 4.3 – target listing (`ssbadmin daemon`, `640`/`750`) |
| `screenshots/04-dir-mtime-noise.png` | finding – folder-mtime false positive before `--omit-dir-times` |
| `screenshots/04-no-changes.png` | 4.4 – "Nothing to deploy" |
| `screenshots/04-excludes.png` | 4.5 – junk/secret files not picked up |
| `screenshots/04-changed-file-only.png` | 4.6 – one file in preview, 1 file transferred |
| `screenshots/04-tag-release.png` | 4.7 – tag pushed, health shows `v1.0.0` |
