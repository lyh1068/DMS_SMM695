-- SQLite
CREATE TABLE employees (
  emp_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  dept TEXT,
  salary REAL
);

CREATE TABLE department (
  dept_id INTEGER PRIMARY KEY,
  dept_name TEXT NOT NULL
);

INSERT INTO employees (emp_id, name, dept, salary)
VALUES
  (1, 'Alice', 'Engineering', 95000),
  (2, 'Bob', 'Sales', 80000),
  (3, 'Carol', 'Engineering', 100000);

INSERT INTO department (dept_id, dept_name)
VALUES
  (10, 'Engineering'),
  (20, 'Sales');

ALTER TABLE employees ADD COLUMN dept_id INTEGER;
UPDATE employees
SET dept_id = (
  SELECT dept_id
  FROM department
  WHERE department.dept_name = employees.dept
);

SELECT name, salary FROM employees
WHERE dept = 'Engineering';

INSERT INTO employees VALUES (4, 'David', 'HR', 100000, 3);
INSERT INTO department VALUES (4, 'Finance');

SELECT e.name, d.dept_name
FROM employees e
INNER JOIN department d ON e.dept_id = d.dept_id;

SELECT e.name, d.dept_name
FROM employees e
LEFT JOIN department d ON e.dept_id = d.dept_id;

SELECT e.name, d.dept_name
FROM employees e
FULL OUTER JOIN department d ON e.dept_id = d.dept_id;

SELECT e.name, d.dept_name
FROM employees e
CROSS JOIN department d
WHERE e.dept_id = d.dept_id

UNION ALL

SELECT e.name, NULL
FROM employees e
WHERE NOT EXISTS (
  SELECT 1
  FROM department d
  WHERE d.dept_id = e.dept_id
)

UNION ALL
SELECT NULL, d.dept_name
FROM department d
WHERE NOT EXISTS (
  SELECT 1
  FROM employees e
  WHERE e.dept_id = d.dept_id
);
