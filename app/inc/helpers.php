<?php
/**
 * Small helpers: output escaping, session, CSRF, flash messages, redirects.
 */
declare(strict_types=1);

/** Escape for HTML output – every value printed into the page goes through this. */
function e(string|int|float|null $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function start_session(): void
{
    if (session_status() === PHP_SESSION_NONE) {
        session_name('ssb_app');
        session_set_cookie_params(['httponly' => true, 'samesite' => 'Lax']);
        session_start();
    }
}

/** Per-session token that every form must send back (blocks cross-site form posts). */
function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function verify_csrf(): void
{
    $sent = $_POST['csrf'] ?? '';
    if (!is_string($sent) || !hash_equals(csrf_token(), $sent)) {
        http_response_code(400);
        exit('Invalid form token – reload the page and try again.');
    }
}

function flash(string $message, string $type = 'success'): void
{
    $_SESSION['flash'] = ['message' => $message, 'type' => $type];
}

/** @return array{message:string,type:string}|null */
function take_flash(): ?array
{
    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    return $flash;
}

/** Post/Redirect/Get: after a successful POST, redirect so a refresh doesn't resubmit. */
function redirect(string $url): never
{
    header('Location: ' . $url, true, 303);
    exit;
}

function render_error_page(string $message): void
{
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>SSB Inventory – error</title><link rel="stylesheet" href="assets/style.css"></head>'
        . '<body><main class="container"><h1>SSB Inventory</h1>'
        . '<div class="flash flash-error">' . e($message) . '</div>'
        . '<p class="muted">The details have been written to the server error log.</p>'
        . '</main></body></html>';
}
