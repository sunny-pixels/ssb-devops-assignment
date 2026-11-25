<?php
/**
 * Data access + validation for the `items` table.
 * All queries use prepared statements – user input is never concatenated into SQL.
 */
declare(strict_types=1);

const ITEM_FIELDS = ['sku', 'name', 'category', 'quantity', 'unit_price'];

/** @return list<array<string,mixed>> */
function all_items(): array
{
    return db()->query(
        'SELECT id, sku, name, category, quantity, unit_price, updated_at FROM items ORDER BY id'
    )->fetchAll();
}

/** @return array<string,mixed>|null */
function find_item(int $id): ?array
{
    $stmt = db()->prepare(
        'SELECT id, sku, name, category, quantity, unit_price FROM items WHERE id = ?'
    );
    $stmt->execute([$id]);
    return $stmt->fetch() ?: null;
}

/** @param array<string,string> $f */
function create_item(array $f): void
{
    $stmt = db()->prepare(
        'INSERT INTO items (sku, name, category, quantity, unit_price)
         VALUES (:sku, :name, :category, :quantity, :unit_price)'
    );
    $stmt->execute($f);
}

/** @param array<string,string> $f */
function update_item(int $id, array $f): void
{
    $stmt = db()->prepare(
        'UPDATE items
            SET sku = :sku, name = :name, category = :category,
                quantity = :quantity, unit_price = :unit_price
          WHERE id = :id'
    );
    $stmt->execute($f + ['id' => $id]);
}

/**
 * Take only the expected fields from a request array, as trimmed strings.
 *
 * @param array<string,mixed> $src
 * @return array<string,string>
 */
function item_form_from(array $src): array
{
    $form = [];
    foreach (ITEM_FIELDS as $field) {
        $value        = $src[$field] ?? '';
        $form[$field] = is_scalar($value) ? trim((string) $value) : '';
    }
    $form['sku'] = strtoupper($form['sku']);
    return $form;
}

/**
 * @param array<string,string> $f
 * @return list<string> human-readable errors (empty = valid)
 */
function validate_item(array $f): array
{
    $errors = [];
    if (!preg_match('/^[A-Z0-9][A-Z0-9-]{1,31}$/', $f['sku'])) {
        $errors[] = 'SKU: 2–32 characters, letters, digits and dashes (e.g. LAP-003).';
    }
    if ($f['name'] === '' || mb_strlen($f['name']) > 100) {
        $errors[] = 'Name is required (max 100 characters).';
    }
    if ($f['category'] === '' || mb_strlen($f['category']) > 50) {
        $errors[] = 'Category is required (max 50 characters).';
    }
    if (!ctype_digit($f['quantity']) || (int) $f['quantity'] > 1_000_000) {
        $errors[] = 'Quantity must be a whole number from 0 to 1,000,000.';
    }
    if (!preg_match('/^\d{1,8}(\.\d{1,2})?$/', $f['unit_price'])) {
        $errors[] = 'Unit price must be a number with up to 2 decimals (e.g. 1499.00).';
    }
    return $errors;
}
