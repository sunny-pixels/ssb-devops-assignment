<?php
/**
 * Database connection (PDO, MySQL/MariaDB).
 * One shared connection per request; errors are thrown as PDOException.
 */
declare(strict_types=1);

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $c   = app_config();
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
        $c['DB_HOST'],
        (int) $c['DB_PORT'],
        $c['DB_NAME']
    );

    $pdo = new PDO($dsn, $c['DB_USER'], $c['DB_PASS'], [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION, // fail loudly, never silently
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,                  // real server-side prepared statements
        PDO::ATTR_TIMEOUT            => 3,                      // seconds – don't hang if MySQL is down
    ]);

    return $pdo;
}
