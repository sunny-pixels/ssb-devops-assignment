-- =============================================================================
-- create-app-user.sql – dedicated, least-privilege user for the PHP app.
--
-- __DB_PASS__ is a placeholder: the real password lives only in .env (git-ignored).
-- Do NOT run this file directly – use scripts/create-db-user.sh, which reads .env,
-- validates the password and substitutes it before piping to mysql.
--
-- Two host entries because MariaDB treats them separately:
--   'localhost'  → Unix-socket connections
--   '127.0.0.1'  → TCP connections (the app uses DB_HOST=127.0.0.1)
-- =============================================================================

CREATE USER IF NOT EXISTS 'ssb_app'@'localhost' IDENTIFIED BY '__DB_PASS__';
CREATE USER IF NOT EXISTS 'ssb_app'@'127.0.0.1' IDENTIFIED BY '__DB_PASS__';

-- Re-running the script rotates the password to whatever is in .env now
ALTER USER 'ssb_app'@'localhost' IDENTIFIED BY '__DB_PASS__';
ALTER USER 'ssb_app'@'127.0.0.1' IDENTIFIED BY '__DB_PASS__';

-- Data access only (CRUD) on this one database.
-- No DROP / ALTER / CREATE / GRANT, no access to other databases.
GRANT SELECT, INSERT, UPDATE, DELETE ON ssb_inventory.* TO 'ssb_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON ssb_inventory.* TO 'ssb_app'@'127.0.0.1';

-- Evidence. (Not SHOW GRANTS: in MariaDB 10.4 it also prints the password hash.)
SELECT GRANTEE, TABLE_SCHEMA, GROUP_CONCAT(PRIVILEGE_TYPE ORDER BY PRIVILEGE_TYPE) AS privileges
FROM information_schema.SCHEMA_PRIVILEGES
WHERE GRANTEE LIKE '''ssb_app''@%'
GROUP BY GRANTEE, TABLE_SCHEMA;
