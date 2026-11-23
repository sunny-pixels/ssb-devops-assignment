<?php
/**
 * Health endpoint – confirms Apache is serving PHP and required extensions exist.
 * Returns JSON; HTTP 200 when healthy, 503 when a check fails
 * (so curl/monitoring/healthcheck.sh can rely on the status code).
 *
 * A database check is added in Phase 3 once app config exists.
 */
declare(strict_types=1);

header('Content-Type: application/json');
header('Cache-Control: no-store');

$requiredExtensions = ['pdo_mysql', 'mysqli', 'mbstring', 'json'];

$checks = [];
foreach ($requiredExtensions as $ext) {
    $checks["ext_$ext"] = extension_loaded($ext) ? 'ok' : 'missing';
}

$healthy = !in_array('missing', $checks, true);

http_response_code($healthy ? 200 : 503);

echo json_encode([
    'status'      => $healthy ? 'ok' : 'fail',
    'php_version' => PHP_VERSION,
    'server'      => $_SERVER['SERVER_SOFTWARE'] ?? 'cli',
    'hostname'    => gethostname(),
    'checks'      => $checks,
    'time'        => date('c'),
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
