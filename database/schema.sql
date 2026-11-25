-- =============================================================================
-- schema.sql – database + table for the SSB inventory app
-- Run as root (one-off, idempotent):
--   /opt/lampp/bin/mysql -u root -p --table < database/schema.sql
-- =============================================================================

CREATE DATABASE IF NOT EXISTS ssb_inventory
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE ssb_inventory;

-- One table is enough for the assignment: a simple stock list.
CREATE TABLE IF NOT EXISTS items (
    id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    sku         VARCHAR(32)   NOT NULL,                 -- business key, e.g. "LAP-001"
    name        VARCHAR(100)  NOT NULL,
    category    VARCHAR(50)   NOT NULL DEFAULT 'General',
    quantity    INT UNSIGNED  NOT NULL DEFAULT 0,       -- cannot go negative
    unit_price  DECIMAL(10,2) NOT NULL DEFAULT 0.00,    -- exact money, never FLOAT
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                       ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_items_sku (sku),                      -- no duplicate SKUs
    KEY idx_items_category (category)                   -- fast filter by category
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Show the result (evidence)
SHOW TABLES;
DESCRIBE items;
