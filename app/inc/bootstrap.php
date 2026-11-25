<?php
/**
 * Loaded first by every page: safe error handling, then config/db/helpers.
 */
declare(strict_types=1);

// Visitors never see raw PHP errors (paths, SQL, credentials in traces).
// Everything goes to the PHP error log: /opt/lampp/logs/php_error_log
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

require __DIR__ . '/config.php';
require __DIR__ . '/db.php';
require __DIR__ . '/helpers.php';
require __DIR__ . '/items.php';

set_exception_handler(static function (Throwable $e): void {
    // Message + location only – no stack trace, which could contain the DB password.
    error_log(sprintf(
        '[ssb-app] %s: %s in %s:%d',
        $e::class,
        $e->getMessage(),
        $e->getFile(),
        $e->getLine()
    ));

    $dbProblem = $e instanceof PDOException || $e instanceof ConfigException;
    if (!headers_sent()) {
        http_response_code($dbProblem ? 503 : 500);
    }
    render_error_page($dbProblem
        ? 'The database is currently unavailable. Please try again shortly.'
        : 'Something went wrong.');
});
