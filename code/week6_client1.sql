-- ============================================================
-- Week 6 Lab: Client 1 (Session A)
-- Run each numbered section in order.
-- Follow the comments to coordinate with Client 2 (Session B).
-- ============================================================

-- ── 0) SHARED SETUP ─────────────────────────────────────────
-- Run this block ONCE to create the demo tables.

DROP TABLE IF EXISTS iso_inventory CASCADE;
CREATE TABLE iso_inventory (
  product_id INT PRIMARY KEY,
  name       TEXT NOT NULL,
  quantity   INT  NOT NULL
);
INSERT INTO iso_inventory VALUES (1, 'Laptop', 10);

DROP TABLE IF EXISTS accounts CASCADE;
CREATE TABLE accounts (
  name    TEXT PRIMARY KEY,
  balance NUMERIC(12,2) NOT NULL
);
INSERT INTO accounts VALUES ('Alice', 1000.00), ('Bob', 500.00), ('Wally', 500.00);

-- ── 1) READ COMMITTED DEMO ───────────────────────────────────
-- PostgreSQL default isolation level.
-- Expected: two SELECTs in the same transaction CAN return
-- different values if another transaction commits between them.
-- (PG docs §13.2.1: "two successive SELECT commands can see
--  different data, even though they are within a single
--  transaction")

BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT 'RC: first read (expect 10)' AS note, quantity
FROM iso_inventory WHERE product_id = 1;

-- >>> NOW run week6_client2.sql in Session B and wait for it to commit.
SELECT pg_sleep(8);

SELECT 'RC: second read (expect 8 after client 2 committed)' AS note, quantity
FROM iso_inventory WHERE product_id = 1;

COMMIT;

-- Reset for next test
UPDATE iso_inventory SET quantity = 10 WHERE product_id = 1;

-- ── 2) REPEATABLE READ DEMO ──────────────────────────────────
-- Snapshot fixed at transaction start.
-- Expected: both SELECTs return the same value (10) even after
-- Session B commits an update.
-- (PG docs §13.2.2: "successive SELECT commands within a single
--  transaction see the same data")

BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT 'RR: first read (expect 10)' AS note, quantity
FROM iso_inventory WHERE product_id = 1;

-- >>> NOW run week6_client2.sql in Session B again.
SELECT pg_sleep(8);

SELECT 'RR: second read (still expect 10, snapshot is fixed)' AS note, quantity
FROM iso_inventory WHERE product_id = 1;

COMMIT;

-- After transaction ends: new statement sees latest committed value
SELECT 'After RR commit, fresh statement sees latest (expect 8)' AS note, quantity
FROM iso_inventory WHERE product_id = 1;

-- ── 3) SAVEPOINT DEMO ───────────────────────────────────────
-- Direct from PG tutorial §3.4 (Alice / Bob / Wally example).
-- Result: Alice -100, Wally +100, Bob unchanged.

BEGIN;
UPDATE accounts SET balance = balance - 100.00 WHERE name = 'Alice';
SAVEPOINT my_savepoint;
UPDATE accounts SET balance = balance + 100.00 WHERE name = 'Bob';
-- oops, wrong account
ROLLBACK TO my_savepoint;
UPDATE accounts SET balance = balance + 100.00 WHERE name = 'Wally';
COMMIT;

SELECT name, balance FROM accounts ORDER BY name;
-- Alice: 900.00  Bob: 500.00  Wally: 600.00

CREATE TABLE mytab (class INT, value INT);
INSERT INTO mytab VALUES (1,10),(1,20),(2,100),(2,200);

BEGIN; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT SUM(value) FROM mytab WHERE class = 1;  -- 30
INSERT INTO mytab VALUES (2, 30);
COMMIT;