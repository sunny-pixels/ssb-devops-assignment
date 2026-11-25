# Phase 1 – LAMPP Setup & Checks (Assignment section A)

Target: Ubuntu 24.04 VM `ssb-lamp` (192.168.198.133) · XAMPP for Linux 8.2.12
(Apache 2.4.58 · MariaDB 10.4.32 · PHP 8.2.12 · phpMyAdmin 5.2.1)

---

## 1.1 Install XAMPP for Linux
```bash
cd /tmp
wget -O xampp-installer.run \
  "https://sourceforge.net/projects/xampp/files/XAMPP%20Linux/8.2.12/xampp-linux-x64-8.2.12-0-installer.run/download"
ls -lh xampp-installer.run            # ~160 MB
chmod +x xampp-installer.run
sudo ./xampp-installer.run --mode text
```
Installer answers: Core files **Y** · Developer files **n** · install to `/opt/lampp` **Y**.
(Repeatable alternative: `sudo ./xampp-installer.run --mode unattended`.)

## 1.2 Service control (start / stop / status)
```bash
sudo /opt/lampp/lampp start          # Apache + MySQL + ProFTPD
sudo /opt/lampp/lampp status
sudo /opt/lampp/lampp stopftp        # FTP not needed – reduce attack surface
sudo /opt/lampp/lampp stop
sudo /opt/lampp/lampp startapache
sudo /opt/lampp/lampp startmysql
```
Individual: `startapache|stopapache|startmysql|stopmysql|reloadapache|restart`.

### Managed by systemd (start on boot)
```bash
sudo cp ~/ssb-devops-assignment/systemd/lampp.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo /opt/lampp/lampp stop            # hand control over to systemd
sudo systemctl enable --now lampp
systemctl status lampp --no-pager
```

## 1.3 Ports in use
```bash
sudo ss -tlnp | grep -E ':(80|443|3306)\s'
```
| Port | Service |
|---|---|
| 80 | Apache HTTP |
| 443 | Apache HTTPS (self-signed) |
| 3306 | MariaDB (`mysqld`) |

## 1.4 Log & config locations
| What | Path |
|---|---|
| Apache access log | `/opt/lampp/logs/access_log` |
| Apache error log (also PHP errors) | `/opt/lampp/logs/error_log` |
| PHP error log (if set) | `grep ^error_log /opt/lampp/etc/php.ini` |
| MariaDB error log | `/opt/lampp/var/mysql/<hostname>.err` |
| Apache config | `/opt/lampp/etc/httpd.conf`, `etc/extra/httpd-xampp.conf` |
| PHP config | `/opt/lampp/etc/php.ini` |
| MariaDB config | `/opt/lampp/etc/my.cnf` |
| Web root | `/opt/lampp/htdocs` |

Live tail while testing: `sudo tail -f /opt/lampp/logs/error_log`

## 1.5 Secure the defaults
XAMPP ships with an **empty MySQL root password**. Set one immediately:
```bash
sudo /opt/lampp/lampp security
```
- XAMPP pages password → **y**, set one
- MySQL/phpMyAdmin `root` password → **y**, set a strong one (store it in a password manager, never in Git)
- ProFTPD password → **y** (FTP stays stopped anyway)

phpMyAdmin is `Require local` by default. Allow **only the Windows host** (192.168.198.1), not the whole network:
```bash
F=/opt/lampp/etc/extra/httpd-xampp.conf
sudo cp "$F" "$F.orig"
grep -n "Require local" "$F"
sudo sed -i 's/^\(\s*\)Require local\s*$/\1Require local\n\1Require ip 192.168.198.1/' "$F"
grep -n -A1 "Require local" "$F"
sudo /opt/lampp/lampp reloadapache   # or: sudo systemctl reload lampp
```

### MySQL: loopback-only TCP instead of `skip-networking`
`lampp security` "secures" MySQL by appending `skip-networking` to `my.cnf`, which
turns TCP off entirely (`ss` shows no 3306; error log shows `port: 0`). The app and
scripts connect via `DB_HOST=127.0.0.1`, so they would get *Connection refused*.
Keep TCP, but bind it to loopback only – unreachable from the network, usable locally:
```bash
F=/opt/lampp/etc/my.cnf
sudo cp "$F" "$F.orig"
sudo sed -i 's/^skip-networking$/#skip-networking\nbind-address=127.0.0.1/' "$F"
grep -nE 'skip-networking|bind-address' "$F"
sudo systemctl restart lampp
sudo ss -tlnp | grep 3306                     # → 127.0.0.1:3306 (not *:3306)
/opt/lampp/bin/mysql -h 127.0.0.1 -P 3306 -u root -p -e "SELECT 'tcp ok' AS result;"
```
| State | `ss` shows | Verdict |
|---|---|---|
| XAMPP default | `*:3306` | reachable from the whole network ✗ |
| after `lampp security` | nothing (`port: 0`) | safe, but app TCP connections fail ✗ |
| `bind-address=127.0.0.1` | `127.0.0.1:3306` | local-only and usable ✓ |

### MariaDB system-table mismatch (`mysql_upgrade`)
**Symptom** (`/opt/lampp/var/mysql/ssb-lamp.err`, on every phpMyAdmin page load):
```
[ERROR] Incorrect definition of table mysql.column_stats: expected column 'max_value'
        at position 4 to have type varbinary(255), found type varchar(255).
```
**Cause:** the XAMPP bundle ships `mysql.*` system tables from an older MariaDB than
its 10.4.32 server binary. **Fix** (one-off):
```bash
sudo /opt/lampp/bin/mysql_upgrade -u root -p     # all 7 phases → OK
sudo systemctl restart lampp
sudo tail -n 5 /opt/lampp/var/mysql/ssb-lamp.err # column_stats errors gone
```
> The remaining `Access denied for user 'root'@'localhost' (using password: NO)` warning
> at startup is the `lampp` script's own password-less ping – harmless.

### PHP timezone
XAMPP ships `date.timezone=Europe/Berlin`, so PHP timestamps were 4.5 h off the
VM clock (IST). Align it with the OS:
```bash
sudo sed -i 's|^date.timezone=.*|date.timezone=Asia/Kolkata|' /opt/lampp/etc/php.ini
grep -n '^date.timezone' /opt/lampp/etc/php.ini
sudo systemctl reload lampp
```
Verified: `health.php` `"time"` changed from `…+01:00` to `…+05:30`.

## 1.6 PHP verification
**phpinfo (temporary – exposes config, delete after the screenshot):**
```bash
echo '<?php phpinfo();' | sudo tee /opt/lampp/htdocs/info.php
# browse http://192.168.198.133/info.php  → screenshot
sudo rm /opt/lampp/htdocs/info.php
```

**Health page (stays – JSON, HTTP 200/503):**
```bash
sudo mkdir -p /opt/lampp/htdocs/ssb-app
sudo cp ~/ssb-devops-assignment/app/health.php /opt/lampp/htdocs/ssb-app/
curl -i http://localhost/ssb-app/health.php
```
> In Phase 4 this manual copy is replaced by `deploy.sh` (rsync).

## 1.7 One-shot evidence report
```bash
cd ~/ssb-devops-assignment
chmod +x scripts/lampp-check.sh
sudo ./scripts/lampp-check.sh | tee ~/01-lampp-check.txt
```

## Evidence
| File | Shows |
|---|---|
| `screenshots/01-lampp-status.png` | `lampp status` / `systemctl status lampp` |
| `screenshots/01-ports.png` | `ss -tlnp` with 80/443/3306 |
| `screenshots/01-phpinfo.png` | phpinfo page in browser (`01-phpinfo-cmd.png`: how it was created) |
| `screenshots/01-health.png` | `/ssb-app/health.php` JSON in browser |
| `screenshots/01-health-curl.png` | `curl -i` → `HTTP/1.1 200 OK`, all extension checks `ok`, IST time |
| `screenshots/01-phpmyadmin-login.png` | phpMyAdmin from Windows host |
| `screenshots/01-security-check.png` | `lampp security` quick check (root password set) |
| `screenshots/01-mysql-skip-networking.png` | diagnosis: no 3306 listener, `skip-networking` in `my.cnf` |
| `screenshots/01-mysql-bind-localhost.png` | fix: `127.0.0.1:3306` + `tcp ok` |
| `screenshots/01-mysql-upgrade-1.png`, `-2.png` | `mysql_upgrade` run, clean error log |
| `screenshots/01-lampp-check-1.png`, `-2.png` | first `lampp-check.sh` run (before the MySQL fixes) |
| `screenshots/01-lampp-check-final-1.png`, `-2.png` | final run: `127.0.0.1:3306`, clean MySQL log, `port: 3306`, PASS |
| `screenshots/01-lampp-check.txt` | full output of `lampp-check.sh` |
