-- =============================================================================
-- create-backup-user.sql – read-only user for mysqldump (scripts/backup.sh).
--
-- __BACKUP_DB_PASS__ is a placeholder: the real password lives only in .env.
-- Run via:  ./scripts/create-db-user.sh backup
--
-- Why a separate user: backups (and the cron job) never need root, and never need
-- to write – so a leaked backup credential cannot change or delete data.
-- =============================================================================

CREATE USER IF NOT EXISTS 'ssb_backup'@'localhost' IDENTIFIED BY '__BACKUP_DB_PASS__';
CREATE USER IF NOT EXISTS 'ssb_backup'@'127.0.0.1' IDENTIFIED BY '__BACKUP_DB_PASS__';
ALTER USER 'ssb_backup'@'localhost' IDENTIFIED BY '__BACKUP_DB_PASS__';
ALTER USER 'ssb_backup'@'127.0.0.1' IDENTIFIED BY '__BACKUP_DB_PASS__';

-- Exactly what mysqldump needs for one database:
--   SELECT       read the rows
--   SHOW VIEW    dump view definitions
--   TRIGGER      dump triggers
--   LOCK TABLES  consistent dump of non-InnoDB tables (InnoDB uses --single-transaction)
GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES ON ssb_inventory.* TO 'ssb_backup'@'localhost';
GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES ON ssb_inventory.* TO 'ssb_backup'@'127.0.0.1';

-- Evidence (not SHOW GRANTS – in MariaDB 10.4 it also prints the password hash)
SELECT GRANTEE, TABLE_SCHEMA, GROUP_CONCAT(PRIVILEGE_TYPE ORDER BY PRIVILEGE_TYPE) AS privileges
FROM information_schema.SCHEMA_PRIVILEGES
WHERE GRANTEE LIKE '''ssb_backup''@%'
GROUP BY GRANTEE, TABLE_SCHEMA;
