-- PostgreSQL examples for Week 2: SQL logic and modelling.
-- This script is organized in the same order as the slide deck.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 1. PostgreSQL tutorial-style examples: subqueries and joins
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS weather CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

CREATE TABLE weather (
  city VARCHAR(80),
  temp_lo INT,
  temp_hi INT,
  prcp REAL,
  date DATE
);

CREATE TABLE cities (
  name VARCHAR(80),
  location POINT
);

INSERT INTO weather VALUES
  ('San Francisco', 46, 50, 0.25, '1994-11-27');

INSERT INTO weather (city, temp_lo, temp_hi, prcp, date) VALUES
  ('San Francisco', 43, 57, 0.0, '1994-11-29');

INSERT INTO weather (date, city, temp_hi, temp_lo) VALUES
  ('1994-11-29', 'Hayward', 54, 37);

INSERT INTO cities VALUES
  ('San Francisco', '(-194.0, 53.0)');

-- Subquery example from the PostgreSQL tutorial.
SELECT city
FROM weather
WHERE temp_lo = (
  SELECT max(temp_lo) FROM weather
);

-- LEFT JOIN from the PostgreSQL tutorial.
SELECT w.city, w.temp_lo, w.temp_hi, c.location
FROM weather w
LEFT JOIN cities c ON w.city = c.name;

-- ---------------------------------------------------------------------------
-- 2. PostgreSQL documentation-style relationship examples
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS weather_fk CASCADE;
DROP TABLE IF EXISTS cities_fk CASCADE;

CREATE TABLE cities_fk (
  name VARCHAR(80) PRIMARY KEY,
  location POINT
);

CREATE TABLE weather_fk (
  city VARCHAR(80) REFERENCES cities_fk(name),
  temp_lo INT,
  temp_hi INT,
  prcp REAL,
  date DATE
);

INSERT INTO cities_fk VALUES
  ('San Francisco', '(-194.0, 53.0)'),
  ('Hayward', '(10.0, 20.0)');

INSERT INTO weather_fk VALUES
  ('San Francisco', 46, 50, 0.25, '1994-11-27'),
  ('San Francisco', 43, 57, 0.0, '1994-11-29'),
  ('Hayward', 37, 54, NULL, '1994-11-29');

-- Many-to-one from the PostgreSQL foreign-key tutorial pattern.
SELECT c.name, COUNT(w.city) AS weather_rows
FROM cities_fk c
LEFT JOIN weather_fk w ON w.city = c.name
GROUP BY c.name
ORDER BY c.name;

DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS orders_docs CASCADE;

CREATE TABLE products (
  product_no INTEGER PRIMARY KEY,
  name TEXT,
  price NUMERIC(10, 2)
);

CREATE TABLE orders_docs (
  order_id INTEGER PRIMARY KEY,
  shipping_address TEXT
);

CREATE TABLE order_items (
  product_no INTEGER REFERENCES products,
  order_id INTEGER REFERENCES orders_docs,
  quantity INTEGER,
  PRIMARY KEY (product_no, order_id)
);

INSERT INTO products VALUES
  (1, 'Laptop', 1200.00),
  (2, 'Mouse', 20.00),
  (3, 'Monitor', 300.00);

INSERT INTO orders_docs VALUES
  (1001, 'London'),
  (1002, 'Manchester');

INSERT INTO order_items VALUES
  (1, 1001, 1),
  (2, 1001, 2),
  (3, 1002, 1);

-- Many-to-many from the PostgreSQL constraints documentation pattern.
SELECT oi.order_id, p.name, oi.quantity
FROM order_items oi
JOIN products p ON p.product_no = oi.product_no
ORDER BY oi.order_id, p.product_no;

-- ---------------------------------------------------------------------------
-- 3. PostgreSQL documentation-style CTE examples
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS orders CASCADE;

CREATE TABLE orders (
  region TEXT,
  product TEXT,
  quantity INTEGER,
  amount NUMERIC(10, 2)
);

INSERT INTO orders (region, product, quantity, amount) VALUES
  ('North', 'Laptop', 10, 12000.00),
  ('North', 'Mouse', 40, 800.00),
  ('South', 'Laptop', 4, 4800.00),
  ('South', 'Keyboard', 15, 1500.00),
  ('West', 'Monitor', 3, 900.00);

-- Official two-CTE pattern from the PostgreSQL docs.
WITH regional_sales AS (
  SELECT region, SUM(amount) AS total_sales
  FROM orders
  GROUP BY region
), top_regions AS (
  SELECT region
  FROM regional_sales
  WHERE total_sales > (
    SELECT SUM(total_sales) / 10 FROM regional_sales
  )
)
SELECT region
FROM top_regions
ORDER BY region;

-- ---------------------------------------------------------------------------
-- 4. Exercise dataset: authors and books
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS books CASCADE;
DROP TABLE IF EXISTS authors CASCADE;

CREATE TABLE authors (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  country TEXT NOT NULL
);

CREATE TABLE books (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  author_id INTEGER NOT NULL REFERENCES authors(id),
  published_year INTEGER,
  price NUMERIC(6, 2) NOT NULL CHECK (price >= 0)
);

INSERT INTO authors (id, name, country) VALUES
  (1, 'George Orwell', 'UK'),
  (2, 'J.K. Rowling', 'UK'),
  (3, 'Isaac Asimov', 'USA'),
  (4, 'Chimamanda Ngozi Adichie', 'Nigeria');

INSERT INTO books (id, title, author_id, published_year, price) VALUES
  (1, '1984', 1, 1949, 15.99),
  (2, 'Animal Farm', 1, 1945, 9.99),
  (3, 'Harry Potter and the Philosopher''s Stone', 2, 1997, 19.99),
  (4, 'Foundation', 3, 1951, 12.99);

-- Exercise 1: books above the average price.
SELECT title, price
FROM books
WHERE price > (
  SELECT AVG(price) FROM books
)
ORDER BY price DESC;

-- Exercise 1: books by authors from the top author country.
SELECT b.title, a.name, a.country
FROM books b
JOIN authors a ON a.id = b.author_id
WHERE a.country IN (
  SELECT country
  FROM authors
  GROUP BY country
  ORDER BY COUNT(*) DESC
  LIMIT 1
)
ORDER BY b.id;

-- Exercise 1: titles longer than the average title length.
SELECT title
FROM books
WHERE LENGTH(title) > (
  SELECT AVG(LENGTH(title)) FROM books
)
ORDER BY title;

-- Exercise 3: all authors with a book count.
SELECT a.name, COUNT(b.id) AS book_count
FROM authors a
LEFT JOIN books b ON b.author_id = a.id
GROUP BY a.id, a.name
ORDER BY a.id;

-- ---------------------------------------------------------------------------
-- 5. Index examples moved from Week 1 into Week 2
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS orders_perf CASCADE;

CREATE TABLE orders_perf (
  order_id INTEGER PRIMARY KEY,
  cust_id INTEGER NOT NULL,
  amount NUMERIC(10, 2) NOT NULL
);

INSERT INTO orders_perf (order_id, cust_id, amount)
SELECT
  gs,
  ((gs - 1) % 100) + 1,
  (((gs - 1) % 20) + 1) * 10
FROM generate_series(1, 10000) AS gs;

-- Baseline plan before adding indexes.
EXPLAIN
SELECT *
FROM orders_perf
WHERE cust_id = 42;

CREATE INDEX idx_orders_perf_cust_id
ON orders_perf(cust_id);

-- Filter query with a single-column index.
EXPLAIN
SELECT *
FROM orders_perf
WHERE cust_id = 42;

CREATE INDEX idx_orders_perf_cust_amount
ON orders_perf(cust_id, amount);

-- Filter + sort query with a composite index.
EXPLAIN
SELECT *
FROM orders_perf
WHERE cust_id = 42
ORDER BY amount
LIMIT 5;

-- ---------------------------------------------------------------------------
-- 6. Normalization challenge
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS enrollments_norm CASCADE;
DROP TABLE IF EXISTS courses_norm CASCADE;
DROP TABLE IF EXISTS students_norm CASCADE;
DROP TABLE IF EXISTS student_courses_denorm CASCADE;

CREATE TABLE student_courses_denorm (
  student_id INTEGER,
  student_name TEXT,
  course_id INTEGER,
  course_name TEXT,
  professor_name TEXT,
  grade INTEGER
);

INSERT INTO student_courses_denorm VALUES
  (1, 'Alice', 101, 'Math', 'Dr. Smith', 90),
  (1, 'Alice', 102, 'Physics', 'Dr. Jones', 85),
  (2, 'Bob', 101, 'Math', 'Dr. Smith', 88);

CREATE TABLE students_norm (
  student_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE courses_norm (
  course_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  professor_name TEXT NOT NULL
);

CREATE TABLE enrollments_norm (
  student_id INTEGER NOT NULL REFERENCES students_norm(student_id),
  course_id INTEGER NOT NULL REFERENCES courses_norm(course_id),
  grade INTEGER NOT NULL,
  PRIMARY KEY (student_id, course_id)
);

INSERT INTO students_norm (student_id, name)
SELECT DISTINCT student_id, student_name
FROM student_courses_denorm;

INSERT INTO courses_norm (course_id, name, professor_name)
SELECT DISTINCT course_id, course_name, professor_name
FROM student_courses_denorm;

INSERT INTO enrollments_norm (student_id, course_id, grade)
SELECT student_id, course_id, grade
FROM student_courses_denorm;

SELECT s.name, c.name AS course_name, c.professor_name, e.grade
FROM enrollments_norm e
JOIN students_norm s ON s.student_id = e.student_id
JOIN courses_norm c ON c.course_id = e.course_id
ORDER BY s.name, c.course_id;

-- ---------------------------------------------------------------------------
-- 7. Extra normalization examples: 3NF and BCNF
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS courses_3nf CASCADE;
DROP TABLE IF EXISTS lecturers_3nf CASCADE;

CREATE TABLE lecturers_3nf (
  lecturer_id INTEGER PRIMARY KEY,
  lecturer_name TEXT NOT NULL
);

CREATE TABLE courses_3nf (
  course_id INTEGER PRIMARY KEY,
  course_name TEXT NOT NULL,
  lecturer_id INTEGER NOT NULL REFERENCES lecturers_3nf(lecturer_id)
);

INSERT INTO lecturers_3nf VALUES
  (1, 'Dr. Smith'),
  (2, 'Dr. Jones');

INSERT INTO courses_3nf VALUES
  (101, 'Math', 1),
  (102, 'Physics', 2);

SELECT c.course_name, l.lecturer_name
FROM courses_3nf c
JOIN lecturers_3nf l ON l.lecturer_id = c.lecturer_id
ORDER BY c.course_id;

DROP TABLE IF EXISTS student_lecturers CASCADE;
DROP TABLE IF EXISTS lecturers_bcnf CASCADE;

CREATE TABLE lecturers_bcnf (
  lecturer_id INTEGER PRIMARY KEY,
  course_id INTEGER NOT NULL REFERENCES courses_norm(course_id)
);

CREATE TABLE student_lecturers (
  student_id INTEGER NOT NULL REFERENCES students_norm(student_id),
  lecturer_id INTEGER NOT NULL REFERENCES lecturers_bcnf(lecturer_id),
  PRIMARY KEY (student_id, lecturer_id)
);

INSERT INTO lecturers_bcnf VALUES
  (1, 101),
  (2, 102);

INSERT INTO student_lecturers VALUES
  (1, 1),
  (1, 2),
  (2, 1);

SELECT s.name, sl.lecturer_id, c.name AS course_name
FROM student_lecturers sl
JOIN students_norm s ON s.student_id = sl.student_id
JOIN lecturers_bcnf l ON l.lecturer_id = sl.lecturer_id
JOIN courses_norm c ON c.course_id = l.course_id
ORDER BY s.student_id, sl.lecturer_id;