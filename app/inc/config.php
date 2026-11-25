<?php
/**
 * Configuration loader.
 *
 * Settings (DB host/user/password …) are NOT in the source code. They are read from
 * an env file that lives outside Git and outside the web root:
 *
 *     /etc/ssb-app/app.env      owner root:daemon, mode 640
 *
 * The path can be overridden with an SSB_ENV_FILE environment variable
 * (e.g. `SetEnv SSB_ENV_FILE /path/app.env` in the Apache vhost).
 */
declare(strict_types=1);

final class ConfigException extends RuntimeException
{
}

const SSB_DEFAULT_ENV_FILE = '/etc/ssb-app/app.env';
const SSB_REQUIRED_KEYS    = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASS'];

/** @return array<string,string> */
function app_config(): array
{
    static $config = null;
    if ($config !== null) {
        return $config;
    }

    $file = $_SERVER['SSB_ENV_FILE'] ?? (getenv('SSB_ENV_FILE') ?: SSB_DEFAULT_ENV_FILE);

    if (!is_file($file)) {
        throw new ConfigException("Config file not found: $file");
    }
    if (!is_readable($file)) {
        throw new ConfigException("Config file not readable by the web server user: $file");
    }

    $values = parse_env_file($file);
    foreach (SSB_REQUIRED_KEYS as $key) {
        if (($values[$key] ?? '') === '') {
            throw new ConfigException("Missing required setting $key in $file");
        }
    }

    return $config = $values;
}

/**
 * Minimal KEY=VALUE parser (same format the shell scripts source).
 * Blank lines and lines starting with # are ignored; surrounding quotes are stripped.
 *
 * @return array<string,string>
 */
function parse_env_file(string $file): array
{
    $lines = file($file, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        throw new ConfigException("Could not read config file: $file");
    }

    $values = [];
    foreach ($lines as $i => $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $pos = strpos($line, '=');
        if ($pos === false) {
            throw new ConfigException(sprintf('%s line %d: expected KEY=VALUE', $file, $i + 1));
        }
        $key   = trim(substr($line, 0, $pos));
        $value = trim(substr($line, $pos + 1));
        $quote = $value[0] ?? '';
        if (strlen($value) >= 2 && ($quote === '"' || $quote === "'") && $value[-1] === $quote) {
            $value = substr($value, 1, -1);
        }
        $values[$key] = $value;
    }

    return $values;
}
