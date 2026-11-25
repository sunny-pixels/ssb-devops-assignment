<?php
/**
 * Health endpoint – confirms Apache serves PHP, required extensions exist,
 * the config file is readable and MySQL answers as the app user.
 * Returns JSON; HTTP 200 when healthy, 503 when any check fails
 * (so curl/monitoring/healthcheck.sh can rely on the status code).
 *
 * Failure details (e.g. "Access denied", "Connection refused") go to the PHP error
 * log; the response only shows the MySQL error code, never credentials.
 */
declare(strict_types=1);

ini_set('display_errors', '0');

require __DIR__ . '/inc/config.php';
require __DIR__ . '/inc/db.php';

header('Content-Type: application/json');
header('Cache-Control: no-store');

$checks = [];
foreach (['pdo_mysql', 'mysqli', 'mbstring', 'json'] as $ext) {
    $checks["ext_$ext"] = extension_loaded($ext) ? 'ok' : 'missing';
}

try {
    app_config();
    $checks['config'] = 'ok';
} catch (ConfigException $e) {
    error_log('[ssb-app health] ' . $e->getMessage());
    $checks['config'] = 'error';
}

if ($checks['config'] === 'ok') {
    try {
        $count = (int) db()->query('SELECT COUNT(*) FROM items')->fetchColumn();
        $checks['database'] = 'ok';
    } catch (PDOException $e) {
        // e.g. 1045 = access denied (wrong password), 2002 = MySQL down / wrong host-port,
        //      1049 = unknown database, 1146 = table missing
        error_log('[ssb-app health] ' . $e->getMessage());
        $checks['database'] = 'error ' . ($e->errorInfo[1] ?? $e->getCode());
    }
} else {
    $checks['database'] = 'skipped (no config)';
}

$healthy = !array_filter($checks, static fn (string $v): bool => $v !== 'ok');

// Written by scripts/deploy.sh – shows which Git release is live
$revisionFile = __DIR__ . '/REVISION';
$revision     = is_readable($revisionFile) ? trim((string) file_get_contents($revisionFile)) : null;

http_response_code($healthy ? 200 : 503);

echo json_encode([
    'status'      => $healthy ? 'ok' : 'fail',
    'revision'    => $revision,
    'php_version' => PHP_VERSION,
    'server'      => $_SERVER['SERVER_SOFTWARE'] ?? 'cli',
    'hostname'    => gethostname(),
    'checks'      => $checks,
    'items'       => $count ?? null,
    'time'        => date('c'),
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
