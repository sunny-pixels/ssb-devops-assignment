-- =============================================================================
-- queries.sql – basic CRUD, run as the APP user (not root) to prove its grants:
--   /opt/lampp/bin/mysql -h 127.0.0.1 -u ssb_app -p ssb_inventory --table --verbose < database/queries.sql
--
-- Works on a temporary row (DEMO-001), so the seed data is left as it was.
-- =============================================================================

-- 1) SELECT – read rows. Lists every item, newest id first. Changes nothing.
SELECT id, sku, name, category, quantity, unit_price
FROM items
ORDER BY id DESC;

-- 2) SELECT with WHERE – filter rows. Items low on stock (fewer than 5 left).
SELECT sku, name, quantity
FROM items
WHERE quantity < 5
ORDER BY quantity;

-- 3) INSERT – add a new row. id, created_at and updated_at are filled in automatically.
INSERT INTO items (sku, name, category, quantity, unit_price)
VALUES ('DEMO-001', 'Demo USB-C Hub', 'Accessories', 10, 1499.00);

SELECT id, sku, name, quantity, unit_price, created_at
FROM items
WHERE sku = 'DEMO-001';

-- 4) UPDATE – change existing rows. The WHERE clause limits it to one row;
--    without WHERE it would change EVERY row. updated_at refreshes automatically.
UPDATE items
SET quantity = quantity - 3, unit_price = 1399.00
WHERE sku = 'DEMO-001';

SELECT sku, quantity, unit_price, updated_at
FROM items
WHERE sku = 'DEMO-001';

-- 5) DELETE – remove rows. Again, WHERE is what keeps this to a single row.
DELETE FROM items
WHERE sku = 'DEMO-001';

-- Confirm it is gone and the table is back to the seed data
SELECT COUNT(*) AS demo_rows_left FROM items WHERE sku = 'DEMO-001';
SELECT COUNT(*) AS total_items FROM items;
