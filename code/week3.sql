-- =============================================================================
-- Week 3: Kimball Dimensional Modelling
-- Based on "The Data Warehouse Toolkit, 3rd Edition" by Kimball & Ross
-- Canonical example: Retail Sales (Chapter 3 / Ch. 2 in earlier editions)
-- =============================================================================
-- Run against the demo container:
--   docker exec -i postgres16 psql -U postgres -d demo < code/week3.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- =============================================================================
-- STEP 0: Clean up previous runs
-- =============================================================================

DROP TABLE IF EXISTS fact_retail_sales CASCADE;
DROP TABLE IF EXISTS dim_date        CASCADE;
DROP TABLE IF EXISTS dim_product     CASCADE;
DROP TABLE IF EXISTS dim_store       CASCADE;
DROP TABLE IF EXISTS dim_customer    CASCADE;
DROP TABLE IF EXISTS dim_promotion   CASCADE;

-- =============================================================================
-- STEP 1: Dimension tables
-- Kimball always builds dimensions first, fact table last.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dim_date
-- Kimball calls the date dimension "the most important dimension in the DW".
-- It is pre-populated entirely at build time - never joined to a live calendar.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 3.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key        INTEGER      PRIMARY KEY,   -- surrogate: YYYYMMDD integer
    full_date       DATE         NOT NULL,
    day_of_week     VARCHAR(10)  NOT NULL,       -- 'Monday', 'Tuesday', ...
    day_num_in_week SMALLINT     NOT NULL,       -- 1 = Sunday
    day_num_in_month SMALLINT    NOT NULL,
    day_num_in_year  SMALLINT    NOT NULL,
    calendar_week   SMALLINT     NOT NULL,       -- ISO week number
    calendar_month  VARCHAR(10)  NOT NULL,       -- 'January', 'February', ...
    month_num       SMALLINT     NOT NULL,       -- 1-12
    calendar_quarter CHAR(2)     NOT NULL,       -- 'Q1', 'Q2', 'Q3', 'Q4'
    calendar_year   SMALLINT     NOT NULL,
    is_weekend      BOOLEAN      NOT NULL DEFAULT FALSE
);

-- Pre-populate dim_date for Q1 2024
INSERT INTO dim_date (
    date_key, full_date, day_of_week, day_num_in_week,
    day_num_in_month, day_num_in_year, calendar_week,
    calendar_month, month_num, calendar_quarter, calendar_year, is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER                             AS date_key,
    d::DATE                                                     AS full_date,
    TO_CHAR(d, 'Day')                                           AS day_of_week,
    EXTRACT(DOW FROM d)::SMALLINT + 1                           AS day_num_in_week,
    EXTRACT(DAY  FROM d)::SMALLINT                              AS day_num_in_month,
    EXTRACT(DOY  FROM d)::SMALLINT                              AS day_num_in_year,
    EXTRACT(WEEK FROM d)::SMALLINT                              AS calendar_week,
    TO_CHAR(d, 'Month')                                         AS calendar_month,
    EXTRACT(MONTH FROM d)::SMALLINT                             AS month_num,
    'Q' || EXTRACT(QUARTER FROM d)::TEXT                        AS calendar_quarter,
    EXTRACT(YEAR FROM d)::SMALLINT                              AS calendar_year,
    EXTRACT(DOW FROM d) IN (0, 6)                               AS is_weekend
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-03-31'::DATE,
    '1 day'
) AS d;

-- Verify
SELECT date_key, full_date, day_of_week, calendar_month, calendar_quarter
FROM dim_date
LIMIT 5;

-- -----------------------------------------------------------------------------
-- dim_product
-- Kimball's retail example: SKU-level grain with a product hierarchy
-- (SKU → Category → Department) embedded as flat columns (denormalised).
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 3.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_product (
    product_key         SERIAL       PRIMARY KEY,   -- surrogate key
    product_sku         VARCHAR(20)  NOT NULL,       -- natural / operational key
    product_description VARCHAR(255) NOT NULL,
    brand               VARCHAR(100),
    category            VARCHAR(100) NOT NULL,
    department          VARCHAR(100) NOT NULL,
    package_type        VARCHAR(50),
    is_low_fat          BOOLEAN      NOT NULL DEFAULT FALSE,
    is_recyclable       BOOLEAN      NOT NULL DEFAULT FALSE,
    unit_price          NUMERIC(10,2)
);

INSERT INTO dim_product
    (product_sku, product_description, brand, category, department,
     package_type, is_low_fat, is_recyclable, unit_price)
VALUES
    ('SKU-1001', 'Laptop Pro 15"',   'TechCo',  'Computers',    'Electronics', 'Box',   FALSE, FALSE, 999.99),
    ('SKU-1002', 'Wireless Mouse',   'TechCo',  'Accessories',  'Electronics', 'Box',   FALSE, TRUE,   24.99),
    ('SKU-1003', 'USB-C Hub 7-port', 'ConnectX','Accessories',  'Electronics', 'Bag',   FALSE, TRUE,   49.99),
    ('SKU-2001', 'Ergonomic Chair',  'ErgoWork', 'Seating',      'Furniture',   'Flat',  FALSE, FALSE,  249.99),
    ('SKU-2002', 'Standing Desk',    'ErgoWork', 'Desks',        'Furniture',   'Flat',  FALSE, FALSE,  399.99),
    ('SKU-3001', 'Notebook A5',      'Stationery Co', 'Notebooks', 'Stationery', 'Pack', FALSE, TRUE,    4.99),
    ('SKU-3002', 'Ballpoint Pens x10','Stationery Co','Pens',   'Stationery',  'Pack',  FALSE, TRUE,    3.99);

-- -----------------------------------------------------------------------------
-- dim_store
-- Kimball's retail store dimension with a geographic hierarchy.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 3.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_store (
    store_key       SERIAL       PRIMARY KEY,
    store_name      VARCHAR(100) NOT NULL,
    store_number    VARCHAR(20)  NOT NULL,
    store_manager   VARCHAR(100),
    district        VARCHAR(100) NOT NULL,
    region          VARCHAR(100) NOT NULL,
    country         VARCHAR(100) NOT NULL DEFAULT 'UK',
    total_sq_ft     INTEGER,
    open_date       DATE
);

INSERT INTO dim_store (store_name, store_number, store_manager, district, region, country, total_sq_ft, open_date)
VALUES
    ('London City',      'S001', 'Jane Smith',    'Central London', 'London',    'UK', 5000, '2010-03-01'),
    ('Manchester Deansgate', 'S002', 'Bob Jones', 'Central MCR',    'North West','UK', 4200, '2012-06-15'),
    ('Birmingham Centre','S003', 'Maria Kowalski','Central Brum',   'Midlands',  'UK', 3800, '2015-09-10'),
    ('Edinburgh Royal',  'S004', 'Sean MacGregor','East Scotland',  'Scotland',  'UK', 3100, '2018-01-20');

-- -----------------------------------------------------------------------------
-- dim_customer  (SCD Type 2 ready)
-- Kimball adds effective date columns to handle Slowly Changing Dimensions.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 5.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_key        SERIAL       PRIMARY KEY,   -- surrogate (changes on SCD2 update)
    customer_durable_id VARCHAR(20)  NOT NULL,       -- natural / durable key (stable)
    full_name           VARCHAR(255) NOT NULL,
    email               VARCHAR(255),
    gender              VARCHAR(10),
    birth_date          DATE,
    city                VARCHAR(100),
    country             VARCHAR(100),
    segment             VARCHAR(50),                 -- 'Premium', 'Standard', 'Budget'
    -- SCD Type 2 tracking columns (Kimball, DW Toolkit Ch. 5)
    effective_date      DATE         NOT NULL DEFAULT CURRENT_DATE,
    expiry_date         DATE         NOT NULL DEFAULT '9999-12-31',
    is_current          BOOLEAN      NOT NULL DEFAULT TRUE
);

-- Kimball advises a dedicated "unknown" member (key = 0) for referential integrity.
INSERT INTO dim_customer
    (customer_key, customer_durable_id, full_name, email, gender, birth_date,
     city, country, segment, effective_date, expiry_date, is_current)
VALUES
    (0, 'UNKNOWN', 'Unknown Customer', NULL, NULL, NULL, NULL, NULL, NULL,
     '1900-01-01', '9999-12-31', TRUE);

INSERT INTO dim_customer
    (customer_durable_id, full_name, email, gender, birth_date,
     city, country, segment, effective_date, expiry_date, is_current)
VALUES
    ('C001', 'Alice Brown',   'alice@example.com',   'F', '1990-05-12', 'London',     'UK', 'Premium',  '2024-01-01', '9999-12-31', TRUE),
    ('C002', 'Bob Williams',  'bob@example.com',     'M', '1985-11-03', 'Manchester', 'UK', 'Standard', '2024-01-01', '9999-12-31', TRUE),
    ('C003', 'Carol Davis',   'carol@example.com',   'F', '1992-07-22', 'Birmingham', 'UK', 'Budget',   '2024-01-01', '9999-12-31', TRUE),
    ('C004', 'David Wilson',  'david@example.com',   'M', '1978-03-30', 'Edinburgh',  'UK', 'Premium',  '2024-01-01', '9999-12-31', TRUE);

-- -----------------------------------------------------------------------------
-- dim_promotion
-- Kimball's retail example includes a promotion dimension.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 3.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_promotion (
    promotion_key   SERIAL       PRIMARY KEY,
    promotion_name  VARCHAR(100) NOT NULL,
    promo_type      VARCHAR(50),     -- 'Temporary Price Reduction', 'Ad', 'Coupon'
    price_reduction NUMERIC(5,2)     -- percentage discount
);

-- "No Promotion" placeholder (surrogate key = 0 pattern)
INSERT INTO dim_promotion (promotion_key, promotion_name, promo_type, price_reduction)
VALUES (0, 'No Promotion', NULL, 0.00);

INSERT INTO dim_promotion (promotion_name, promo_type, price_reduction)
VALUES
    ('Winter Sale',       'Temporary Price Reduction', 15.00),
    ('Newsletter Coupon', 'Coupon',                    10.00),
    ('Weekend Ad',        'Ad',                         5.00);

-- =============================================================================
-- STEP 2: Fact table
-- Kimball's retail fact table: TRANSACTION grain (one row per line item on
-- a sales receipt). This is the most atomic and flexible grain.
-- The pos_transaction_number is a DEGENERATE DIMENSION: an operational key
-- that has no corresponding dimension table.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 3.
-- =============================================================================

CREATE TABLE fact_retail_sales (
    -- Surrogate key (optional, but helps ETL updates)
    sales_key               SERIAL        PRIMARY KEY,
    -- Foreign keys to dimension tables
    date_key                INTEGER       NOT NULL REFERENCES dim_date(date_key),
    product_key             INTEGER       NOT NULL REFERENCES dim_product(product_key),
    store_key               INTEGER       NOT NULL REFERENCES dim_store(store_key),
    customer_key            INTEGER       NOT NULL REFERENCES dim_customer(customer_key),
    promotion_key           INTEGER       NOT NULL REFERENCES dim_promotion(promotion_key),
    -- Degenerate dimension: receipt number lives on the fact with no separate dim table
    pos_transaction_number  VARCHAR(20),
    -- Additive measures (Kimball: can SUM across all dimensions)
    sales_quantity          INTEGER       NOT NULL,
    unit_price              NUMERIC(10,2) NOT NULL,
    sales_amount            NUMERIC(10,2) NOT NULL,  -- quantity * unit_price
    cost_amount             NUMERIC(10,2) NOT NULL,
    gross_profit_amount     NUMERIC(10,2) NOT NULL   -- sales_amount - cost_amount
);

-- Sample data: January 2024 transactions
INSERT INTO fact_retail_sales
    (date_key, product_key, store_key, customer_key, promotion_key,
     pos_transaction_number, sales_quantity, unit_price,
     sales_amount, cost_amount, gross_profit_amount)
VALUES
    -- Alice buys Laptop + Mouse in London (20240101)
    (20240101, 1, 1, 1, 0, 'TXN-0001', 1, 999.99,  999.99,  650.00, 349.99),
    (20240101, 2, 1, 1, 0, 'TXN-0001', 1,  24.99,   24.99,   10.00,  14.99),
    -- Bob buys USB Hub on promotion in Manchester (20240103)
    (20240103, 3, 2, 2, 1, 'TXN-0002', 2,  49.99,   99.98,   40.00,  59.98),
    -- Carol buys Chair + Desk in Birmingham (20240105)
    (20240105, 4, 3, 3, 0, 'TXN-0003', 1, 249.99,  249.99,  120.00, 129.99),
    (20240105, 5, 3, 3, 0, 'TXN-0003', 1, 399.99,  399.99,  200.00, 199.99),
    -- David buys Stationery in Edinburgh on coupon (20240108)
    (20240108, 6, 4, 4, 2, 'TXN-0004', 3,   4.99,   14.97,    6.00,   8.97),
    (20240108, 7, 4, 4, 2, 'TXN-0004', 2,   3.99,    7.98,    3.00,   4.98),
    -- Alice buys Desk online via London store (20240115)
    (20240115, 5, 1, 1, 3, 'TXN-0005', 1, 399.99,  399.99,  200.00, 199.99),
    -- Bob buys Laptop in Manchester (20240120)
    (20240120, 1, 2, 2, 0, 'TXN-0006', 1, 999.99,  999.99,  650.00, 349.99),
    -- Carol buys Mouse + USB Hub in Birmingham (20240122)
    (20240122, 2, 3, 3, 0, 'TXN-0007', 1,  24.99,   24.99,   10.00,  14.99),
    (20240122, 3, 3, 3, 0, 'TXN-0007', 1,  49.99,   49.99,   20.00,  29.99),
    -- David buys Laptop in Edinburgh (20240125)
    (20240125, 1, 4, 4, 1, 'TXN-0008', 1, 999.99,  999.99,  650.00, 349.99),
    -- Unknown customer walk-in (uses placeholder key 0)
    (20240130, 6, 2, 0, 0, 'TXN-0009', 5,   4.99,   24.95,   10.00,  14.95);

-- =============================================================================
-- STEP 3: Indexes
-- Kimball recommends indexing all FK columns in the fact table and
-- frequently-filtered dimension attributes.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 19.
-- =============================================================================

CREATE INDEX idx_fact_date     ON fact_retail_sales(date_key);
CREATE INDEX idx_fact_product  ON fact_retail_sales(product_key);
CREATE INDEX idx_fact_store    ON fact_retail_sales(store_key);
CREATE INDEX idx_fact_customer ON fact_retail_sales(customer_key);
CREATE INDEX idx_fact_promo    ON fact_retail_sales(promotion_key);

CREATE INDEX idx_product_category   ON dim_product(category);
CREATE INDEX idx_product_department ON dim_product(department);
CREATE INDEX idx_customer_segment   ON dim_customer(segment);
CREATE INDEX idx_store_region       ON dim_store(region);

-- =============================================================================
-- STEP 4: Analytical queries (Exercise queries from the slide deck)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Query 1: Total sales revenue by product department (Kimball retail style)
-- ---------------------------------------------------------------------------
SELECT
    p.department,
    p.category,
    SUM(f.sales_quantity)      AS total_units_sold,
    SUM(f.sales_amount)        AS total_revenue,
    SUM(f.gross_profit_amount) AS total_gross_profit,
    ROUND(
        SUM(f.gross_profit_amount) / NULLIF(SUM(f.sales_amount), 0) * 100, 2
    )                          AS gross_margin_pct
FROM fact_retail_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.department, p.category
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- Query 2: Sales by customer segment
-- ---------------------------------------------------------------------------
SELECT
    c.segment,
    COUNT(DISTINCT f.pos_transaction_number) AS num_transactions,
    SUM(f.sales_amount)                       AS total_revenue,
    ROUND(AVG(f.sales_amount), 2)             AS avg_line_item_value
FROM fact_retail_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
WHERE c.is_current = TRUE
  AND c.customer_key != 0        -- exclude the 'Unknown' placeholder
GROUP BY c.segment
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- Query 3: Monthly sales trend (using the date dimension)
-- ---------------------------------------------------------------------------
SELECT
    d.calendar_month,
    d.month_num,
    COUNT(*)               AS num_line_items,
    SUM(f.sales_amount)    AS total_revenue
FROM fact_retail_sales f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.calendar_month, d.month_num
ORDER BY d.month_num;

-- ---------------------------------------------------------------------------
-- Query 4: CASE expression – classify orders by value tier
-- (Kimball: use CASE in SELECT for business rules / flags)
-- ---------------------------------------------------------------------------
SELECT
    p.department,
    SUM(CASE WHEN f.sales_amount > 500  THEN 1 ELSE 0 END) AS high_value_lines,
    SUM(CASE WHEN f.sales_amount BETWEEN 50 AND 500
                                        THEN 1 ELSE 0 END) AS mid_value_lines,
    SUM(CASE WHEN f.sales_amount < 50   THEN 1 ELSE 0 END) AS low_value_lines,
    COUNT(*)                                                AS total_lines
FROM fact_retail_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.department
ORDER BY total_lines DESC;

-- ---------------------------------------------------------------------------
-- Query 5: Sales by store region (regional rollup via dim_store hierarchy)
-- ---------------------------------------------------------------------------
SELECT
    s.region,
    s.store_name,
    SUM(f.sales_amount)        AS store_revenue,
    SUM(f.gross_profit_amount) AS store_profit
FROM fact_retail_sales f
JOIN dim_store s ON f.store_key = s.store_key
GROUP BY s.region, s.store_name
ORDER BY s.region, store_revenue DESC;

-- ---------------------------------------------------------------------------
-- Query 6: Promotion effectiveness
-- ---------------------------------------------------------------------------
SELECT
    pr.promotion_name,
    pr.promo_type,
    COUNT(*)               AS num_line_items,
    SUM(f.sales_amount)    AS promoted_revenue
FROM fact_retail_sales f
JOIN dim_promotion pr ON f.promotion_key = pr.promotion_key
GROUP BY pr.promotion_name, pr.promo_type
ORDER BY promoted_revenue DESC;

-- =============================================================================
-- STEP 5: SCD Type 2 demonstration
-- Kimball standard: add a new row, expire the old one.
-- Source: The Data Warehouse Toolkit, 3rd Ed., Chapter 5.
-- =============================================================================

-- Alice (C001) moves from London to Bristol on 2024-02-01:

-- 5a. Expire the current record
UPDATE dim_customer
SET
    expiry_date = '2024-01-31',
    is_current  = FALSE
WHERE customer_durable_id = 'C001'
  AND is_current = TRUE;

-- 5b. Insert the new version with updated city
INSERT INTO dim_customer
    (customer_durable_id, full_name, email, gender, birth_date,
     city, country, segment, effective_date, expiry_date, is_current)
VALUES
    ('C001', 'Alice Brown', 'alice@example.com', 'F', '1990-05-12',
     'Bristol', 'UK', 'Premium', '2024-02-01', '9999-12-31', TRUE);

-- Query current customers
SELECT customer_key, customer_durable_id, full_name, city, effective_date, is_current
FROM dim_customer
ORDER BY customer_durable_id, effective_date;

-- Query: which city did Alice live in on 2024-01-15?
SELECT customer_durable_id, full_name, city, effective_date, expiry_date
FROM dim_customer
WHERE customer_durable_id = 'C001'
  AND '2024-01-15' BETWEEN effective_date AND expiry_date;

-- =============================================================================
-- STEP 6: Conformed dimension – dim_date is shared across fact tables
-- Kimball Bus Architecture: the same dim_date can join to any fact table.
-- =============================================================================

-- Imagine a second fact table: fact_website_visits
-- Both share dim_date → they are "drillable across" without re-joining.
-- Demonstration: weekend vs weekday revenue split (using is_weekend in dim_date)
SELECT
    CASE WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*)               AS num_line_items,
    SUM(f.sales_amount)    AS total_revenue
FROM fact_retail_sales f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.is_weekend
ORDER BY d.is_weekend;

-- =============================================================================
-- All done. Summary row counts:
-- =============================================================================
SELECT
    'dim_date'         AS table_name, COUNT(*) AS rows FROM dim_date
UNION ALL SELECT 'dim_product',    COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_store',      COUNT(*) FROM dim_store
UNION ALL SELECT 'dim_customer',   COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_promotion',  COUNT(*) FROM dim_promotion
UNION ALL SELECT 'fact_retail_sales', COUNT(*) FROM fact_retail_sales
ORDER BY table_name;
