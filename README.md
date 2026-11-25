# SSB Digital – Junior DevOps / Web Operations Take-Home

A small Core PHP + MySQL application run on a LAMPP stack, with repeatable
rsync deployment, database/file backups, restore verification, sensible
permissions and a documented troubleshooting exercise.

> Status: **work in progress** – sections are filled in phase by phase.

## Environment
| Item | Value |
|---|---|
| Host | Windows 11 + VMware Workstation |
| Guest | Ubuntu Server 24.04 LTS (`ssb-lamp`) |
| Stack | XAMPP for Linux (LAMPP) – Apache, MariaDB, PHP 8, phpMyAdmin |

## Repository layout
```
app/          Core PHP application (config kept outside Git)
database/     schema, sample data, CRUD query examples
scripts/      deploy.sh, backup.sh, restore.sh, healthcheck.sh
apache/       virtual host config
cron/         scheduled backup example
docs/         setup guides, permissions, incident note
screenshots/  evidence
systemd/      lampp.service (start stack on boot)
.github/      CI workflow (PHP lint, ShellCheck, secret scan)
```

## Contents
0. [VM preparation](docs/00-vm-setup.md)
1. [LAMPP setup & checks](docs/01-lampp-setup.md)
2. [MySQL + phpMyAdmin](docs/02-mysql-phpmyadmin.md)
3. [Core PHP application](docs/03-php-app.md)
4. Rsync deployment & release flow — _todo_
5. Backup & restore — _todo_
6. Security & permissions — _todo_
7. Troubleshooting / incident note — _todo_
8. Bonus: CI, vhost, cron, health check — _todo_
