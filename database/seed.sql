-- =============================================================================
-- seed.sql – sample data (no real/company data).
-- This is the "provided SQL file" imported through phpMyAdmin:
--   phpMyAdmin → select database ssb_inventory → Import → choose this file → Import
-- CLI alternative:
--   /opt/lampp/bin/mysql -u root -p ssb_inventory < database/seed.sql
--
-- Re-runnable: an existing SKU is updated instead of failing on the UNIQUE key.
-- =============================================================================

INSERT INTO items (sku, name, category, quantity, unit_price) VALUES
    ('LAP-001', 'Dell Latitude 5440 Laptop',      'Hardware',    12, 68500.00),
    ('LAP-002', 'Lenovo ThinkPad E14',            'Hardware',     7, 61200.00),
    ('MON-001', 'LG 24" IPS Monitor',             'Hardware',    20, 11800.00),
    ('KBD-001', 'Logitech K120 Keyboard',         'Accessories', 45,   650.00),
    ('MSE-001', 'Logitech M90 Mouse',             'Accessories', 60,   399.00),
    ('HDS-001', 'Jabra Evolve2 30 Headset',       'Accessories',  3,  5400.00),
    ('NET-001', 'TP-Link 8-Port Gigabit Switch',  'Networking',   5,  1999.00),
    ('NET-002', 'Cat6 Patch Cable 2m',            'Networking',  80,   149.00),
    ('LIC-001', 'Office Suite Licence (1 year)',  'Software',    25,  6200.00),
    ('UPS-001', 'APC 600VA UPS',                  'Hardware',     2,  3450.00)
ON DUPLICATE KEY UPDATE
    name       = VALUES(name),
    category   = VALUES(category),
    quantity   = VALUES(quantity),
    unit_price = VALUES(unit_price);

SELECT COUNT(*) AS seeded_rows FROM items;
