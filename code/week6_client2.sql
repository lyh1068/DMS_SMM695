-- ============================================================
-- Week 6 Lab: Client 2 (Session B)
-- Run this while Client 1 is sleeping (pg_sleep) to demonstrate
-- concurrent update behaviour under different isolation levels.
-- ============================================================

-- This script is designed to be run twice:
--   Run 1: during Client 1's READ COMMITTED wait
--   Run 2: during Client 1's REPEATABLE READ wait

-- Small delay so Session A is definitely in its pg_sleep window
SELECT pg_sleep(3);

BEGIN;

UPDATE iso_inventory
SET quantity = 8
WHERE product_id = 1;

SELECT 'Client 2: updated quantity to 8 (not yet visible)' AS note, quantity
FROM iso_inventory WHERE product_id = 1;

COMMIT;

SELECT 'Client 2: committed. quantity is now 8.' AS note;

BEGIN; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT SUM(value) FROM mytab WHERE class = 2;  -- 300
INSERT INTO mytab VALUES (1, 300);
COMMIT;

ROLLBACK;
