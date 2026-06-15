-- Week 5: Graph Thinking + Recursive SQL + Apache AGE
-- This script is designed to run in PostgreSQL with Apache AGE installed.
-- It includes:
-- 1. Relational graph storage with adjacency lists
-- 2. Recursive CTE examples
-- 3. Apache AGE graph creation, inspection, and Cypher queries
-- 4. Rosetta examples: the SAME question in recursive SQL and in Cypher
-- 5. A small knowledge graph and Graph-RAG style retrieval queries
--
-- Verified against apache/age:release_PG16_1.6.0.
-- Run end-to-end:
--   docker exec -i apache_age psql -U postgres -d demo < code/week5.sql

CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Clean up relational examples.
DROP TABLE IF EXISTS graph_edges;
DROP TABLE IF EXISTS graph_nodes;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS friendships;

-- Clean up AGE graphs if they already exist (keeps the script re-runnable).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'movie_graph') THEN
    PERFORM ag_catalog.drop_graph('movie_graph', true);
  END IF;
  IF EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'social_graph') THEN
    PERFORM ag_catalog.drop_graph('social_graph', true);
  END IF;
  IF EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'books_graph') THEN
    PERFORM ag_catalog.drop_graph('books_graph', true);
  END IF;
  IF EXISTS (SELECT 1 FROM ag_catalog.ag_graph WHERE name = 'org_graph') THEN
    PERFORM ag_catalog.drop_graph('org_graph', true);
  END IF;
END
$$;

-- --------------------------------------------------------------------------
-- RELATIONAL GRAPH STORAGE
-- --------------------------------------------------------------------------

CREATE TABLE graph_nodes (
  id INT PRIMARY KEY,
  label VARCHAR(100),
  node_type VARCHAR(50)
);

CREATE TABLE graph_edges (
  id INT PRIMARY KEY,
  from_node INT REFERENCES graph_nodes(id),
  to_node INT REFERENCES graph_nodes(id),
  relationship VARCHAR(50)
);

INSERT INTO graph_nodes VALUES
  (1, 'Alice', 'Person'),
  (2, 'Bob', 'Person'),
  (3, 'TechCorp', 'Company'),
  (4, 'NYC', 'City');

INSERT INTO graph_edges VALUES
  (1, 1, 2, 'KNOWS'),
  (2, 1, 3, 'WORKS_AT'),
  (3, 3, 4, 'HAS_OFFICE');

SELECT * FROM graph_nodes ORDER BY id;
SELECT * FROM graph_edges ORDER BY id;

SELECT n.label AS knows_person
FROM graph_edges e
JOIN graph_nodes n ON e.to_node = n.id
WHERE e.from_node = (SELECT id FROM graph_nodes WHERE label = 'Alice')
  AND e.relationship = 'KNOWS';

SELECT city.label AS inferred_city
FROM graph_edges e1
JOIN graph_edges e2 ON e1.to_node = e2.from_node
JOIN graph_nodes city ON e2.to_node = city.id
WHERE e1.from_node = (SELECT id FROM graph_nodes WHERE label = 'Alice')
  AND e1.relationship = 'WORKS_AT'
  AND e2.relationship = 'HAS_OFFICE';

-- --------------------------------------------------------------------------
-- RECURSIVE CTE EXAMPLES
-- --------------------------------------------------------------------------

CREATE TABLE employees (
  id INT PRIMARY KEY,
  name VARCHAR(255),
  manager_id INT REFERENCES employees(id)
);

INSERT INTO employees VALUES
  (1, 'Alice', NULL),
  (2, 'Bob', 1),
  (3, 'Charlie', 1),
  (4, 'David', 2),
  (5, 'Eve', 2),
  (6, 'Frank', 3);

SELECT * FROM employees ORDER BY id;

-- Recursive CTE: all subordinates of Alice, with depth.
WITH RECURSIVE subordinates AS (
  SELECT id, name, manager_id, 1 AS depth
  FROM employees
  WHERE manager_id = (SELECT id FROM employees WHERE name = 'Alice')

  UNION ALL

  SELECT e.id, e.name, e.manager_id, s.depth + 1
  FROM employees e
  JOIN subordinates s ON e.manager_id = s.id
)
SELECT *
FROM subordinates
ORDER BY depth, id;

CREATE TABLE friendships (
  person1 VARCHAR(255),
  person2 VARCHAR(255),
  PRIMARY KEY (person1, person2)
);

INSERT INTO friendships VALUES
  ('Alice', 'Bob'),
  ('Bob', 'Charlie'),
  ('Charlie', 'David'),
  ('Alice', 'Eve'),
  ('Eve', 'Frank'),
  ('Frank', 'David');

SELECT * FROM friendships ORDER BY person1, person2;

-- Recursive CTE: all paths from Alice to David (tracks the visited set
-- to avoid cycles, and caps the hop count for safety).
WITH RECURSIVE paths AS (
  SELECT person1, person2, 1 AS hops, ARRAY[person1, person2]::text[] AS path
  FROM friendships
  WHERE person1 = 'Alice'

  UNION ALL

  SELECT p.person1, f.person2, p.hops + 1,
         p.path || f.person2::text
  FROM paths p
  JOIN friendships f ON p.person2 = f.person1
  WHERE NOT f.person2 = ANY(p.path)
    AND p.hops < 10
)
SELECT person1, person2, hops, path
FROM paths
WHERE person2 = 'David'
ORDER BY hops;

-- --------------------------------------------------------------------------
-- APACHE AGE: CREATE AND INSPECT A GRAPH
-- --------------------------------------------------------------------------

SELECT * FROM ag_catalog.create_graph('movie_graph');

SELECT * FROM ag_catalog.ag_graph ORDER BY name;

SELECT * FROM cypher('movie_graph', $$
  CREATE (:Person {name: 'Tom Hanks', born: 1956})
$$) AS (v agtype);

SELECT * FROM cypher('movie_graph', $$
  CREATE (:Person {name: 'Meg Ryan', born: 1961})
$$) AS (v agtype);

SELECT * FROM cypher('movie_graph', $$
  CREATE (:Person {name: 'Nora Ephron', born: 1941})
$$) AS (v agtype);

SELECT * FROM cypher('movie_graph', $$
  CREATE (:Movie {title: 'Sleepless in Seattle', released: 1993})
$$) AS (v agtype);

SELECT * FROM cypher('movie_graph', $$
  MATCH (tom:Person {name: 'Tom Hanks'}),
        (meg:Person {name: 'Meg Ryan'}),
        (nora:Person {name: 'Nora Ephron'}),
        (movie:Movie {title: 'Sleepless in Seattle'})
  CREATE (tom)-[:ACTED_IN {role: 'Sam Baldwin'}]->(movie),
         (meg)-[:ACTED_IN {role: 'Annie Reed'}]->(movie),
         (nora)-[:DIRECTED]->(movie)
  RETURN movie
$$) AS (movie agtype);

SELECT name, kind, relation
FROM ag_catalog.ag_label
WHERE relation::text LIKE 'movie_graph.%'
ORDER BY id;

SELECT * FROM cypher('movie_graph', $$
  MATCH (v)
  RETURN v
$$) AS (v agtype);

SELECT * FROM cypher('movie_graph', $$
  MATCH (:Movie {title: 'Sleepless in Seattle'})<-[:ACTED_IN]-(actor:Person)
  RETURN actor.name
$$) AS (actor_name agtype);

SELECT * FROM cypher('movie_graph', $$
  MATCH (director:Person)-[:DIRECTED]->(:Movie {title: 'Sleepless in Seattle'})
  RETURN director.name
$$) AS (director_name agtype);

SELECT * FROM cypher('movie_graph', $$
  MATCH (actor:Person)-[:ACTED_IN]->(movie:Movie)<-[:DIRECTED]-(director:Person)
  RETURN actor.name, movie.title, director.name
$$) AS (actor_name agtype, movie_title agtype, director_name agtype);

-- --------------------------------------------------------------------------
-- ROSETTA STONE: THE SAME QUESTION IN RECURSIVE SQL AND IN CYPHER
-- --------------------------------------------------------------------------
-- The employees table above is the org chart. Here we mirror the SAME data
-- as a graph (org_graph) so we can ask the same questions both ways.

SELECT * FROM ag_catalog.create_graph('org_graph');

SELECT * FROM cypher('org_graph', $$
  CREATE (a:Emp {name: 'Alice'}),
         (b:Emp {name: 'Bob'}),
         (c:Emp {name: 'Charlie'}),
         (d:Emp {name: 'David'}),
         (e:Emp {name: 'Eve'}),
         (f:Emp {name: 'Frank'})
  CREATE (a)-[:MANAGES]->(b),
         (a)-[:MANAGES]->(c),
         (b)-[:MANAGES]->(d),
         (b)-[:MANAGES]->(e),
         (c)-[:MANAGES]->(f)
$$) AS (v agtype);

-- Q: "Who are all of Alice's reports (any depth)?"
-- Recursive SQL version is the `subordinates` CTE above.
-- Cypher version is a single variable-length pattern:
SELECT * FROM cypher('org_graph', $$
  MATCH (m:Emp {name: 'Alice'})-[:MANAGES*]->(report:Emp)
  RETURN report.name
$$) AS (report_name agtype);

-- Same question, but also returning the depth (length of the path).
SELECT * FROM cypher('org_graph', $$
  MATCH p = (m:Emp {name: 'Alice'})-[:MANAGES*1..3]->(report:Emp)
  RETURN report.name, length(p) AS depth
  ORDER BY length(p), report.name
$$) AS (report_name agtype, depth agtype);

-- --------------------------------------------------------------------------
-- APACHE AGE: VARIABLE-LENGTH PATHS  (enriched social graph)
-- --------------------------------------------------------------------------
-- The KNOWS edges below intentionally mirror the `friendships` table, so the
-- recursive-SQL path query and the Cypher path query return the same answer.

SELECT * FROM ag_catalog.create_graph('social_graph');

SELECT * FROM cypher('social_graph', $$
  CREATE (a:Person {name: 'Alice'}),
         (b:Person {name: 'Bob'}),
         (c:Person {name: 'Charlie'}),
         (d:Person {name: 'David'}),
         (e:Person {name: 'Eve'}),
         (f:Person {name: 'Frank'})
  CREATE (a)-[:KNOWS]->(b),
         (b)-[:KNOWS]->(c),
         (c)-[:KNOWS]->(d),
         (a)-[:KNOWS]->(e),
         (e)-[:KNOWS]->(f),
         (f)-[:KNOWS]->(d)
  CREATE (a)-[:WORKS_AT]->(co:Company {name: 'TechCorp'})
  CREATE (co)-[:HAS_OFFICE]->(:City {name: 'NYC'})
$$) AS (v agtype);

-- Exactly two hops from Alice.
SELECT * FROM cypher('social_graph', $$
  MATCH (:Person {name: 'Alice'})-[:KNOWS*2]->(friend)
  RETURN friend.name
$$) AS (friend_name agtype);

-- "People you may know": friends-of-friends Alice is not already connected to.
SELECT * FROM cypher('social_graph', $$
  MATCH (a:Person {name: 'Alice'})-[:KNOWS*1..2]->(candidate:Person)
  WHERE candidate <> a
    AND NOT exists((a)-[:KNOWS]->(candidate))
  RETURN DISTINCT candidate.name
$$) AS (suggestion agtype);

-- Cypher version of the recursive `paths` query: all routes Alice -> David.
SELECT * FROM cypher('social_graph', $$
  MATCH p = (:Person {name: 'Alice'})-[:KNOWS*]->(:Person {name: 'David'})
  RETURN nodes(p) AS path_nodes, length(p) AS hops
  ORDER BY length(p)
$$) AS (path_nodes agtype, hops agtype);

-- Two-hop reasoning chain: Alice -[:WORKS_AT]-> TechCorp -[:HAS_OFFICE]-> NYC.
SELECT * FROM cypher('social_graph', $$
  MATCH (person:Person {name: 'Alice'})-[:WORKS_AT]->(company)-[:HAS_OFFICE]->(city)
  RETURN city.name
$$) AS (city_name agtype);

-- --------------------------------------------------------------------------
-- KNOWLEDGE GRAPH + GRAPH-RAG STYLE RETRIEVAL
-- --------------------------------------------------------------------------
-- A small science-fiction knowledge graph: authors, books, genres, countries,
-- topics, plus INFLUENCED and CITES edges. Big enough that multi-hop questions
-- return real answers.

SELECT * FROM ag_catalog.create_graph('books_graph');

-- Step A: create the core nodes (matches the "nodes" slide).
SELECT * FROM cypher('books_graph', $$
  CREATE (:Author {name:'Isaac Asimov'}), (:Author {name:'William Gibson'}),
         (:Book {title:'Foundation', year:1951}),
         (:Book {title:'I, Robot', year:1950}),
         (:Book {title:'Neuromancer', year:1984}),
         (:Country {name:'Russia'}), (:Genre {name:'Science Fiction'})
$$) AS (v agtype);

-- Step B: connect the core nodes with typed edges (matches the "edges" slide).
SELECT * FROM cypher('books_graph', $$
  MATCH (asimov:Author {name:'Isaac Asimov'}), (gibson:Author {name:'William Gibson'}),
        (foundation:Book {title:'Foundation'}), (irobot:Book {title:'I, Robot'}),
        (neuro:Book {title:'Neuromancer'}), (russia:Country {name:'Russia'}),
        (scifi:Genre {name:'Science Fiction'})
  CREATE (asimov)-[:WROTE]->(foundation), (asimov)-[:WROTE]->(irobot),
         (gibson)-[:WROTE]->(neuro), (asimov)-[:BORN_IN]->(russia),
         (foundation)-[:IN_GENRE]->(scifi), (irobot)-[:IN_GENRE]->(scifi),
         (neuro)-[:IN_GENRE]->(scifi),
         (asimov)-[:INFLUENCED]->(gibson), (neuro)-[:CITES]->(irobot)
$$) AS (v agtype);

-- Step C: extra nodes/edges (Arthur C. Clarke, another book, topics) so the
-- knowledge graph is richer than the minimal core shown on the slides.
SELECT * FROM cypher('books_graph', $$
  MATCH (irobot:Book {title:'I, Robot'}), (neuro:Book {title:'Neuromancer'}),
        (scifi:Genre {name:'Science Fiction'})
  CREATE (clarke:Author {name:'Arthur C. Clarke'})-[:BORN_IN]->(:Country {name:'United Kingdom'}),
         (clarke)-[:WROTE]->(rama:Book {title:'Rendezvous with Rama', year:1973}),
         (rama)-[:IN_GENRE]->(scifi),
         (irobot)-[:HAS_TOPIC]->(:Topic {name:'Robots'}),
         (neuro)-[:HAS_TOPIC]->(:Topic {name:'Cyberspace'})
$$) AS (v agtype);

-- (1) Multi-hop reasoning question:
--     "Which science-fiction books were written by authors born in Russia?"
SELECT * FROM cypher('books_graph', $$
  MATCH (:Country {name: 'Russia'})<-[:BORN_IN]-(a:Author)
        -[:WROTE]->(b:Book)-[:IN_GENRE]->(:Genre {name: 'Science Fiction'})
  RETURN a.name AS author, b.title AS book
$$) AS (author agtype, book agtype);

-- (2) Connection / path retrieval: "How is Isaac Asimov related to William Gibson?"
--     AGE 1.6.0 has no shortestPath(); we emulate it with a bounded
--     variable-length match ordered by path length, taking the first result.
SELECT * FROM cypher('books_graph', $$
  MATCH p = (a:Author {name: 'Isaac Asimov'})-[*1..4]-(b:Author {name: 'William Gibson'})
  RETURN nodes(p) AS path_nodes, length(p) AS hops
  ORDER BY length(p)
  LIMIT 1
$$) AS (path_nodes agtype, hops agtype);

-- (3) Neighborhood / context retrieval: pull the 1-2 hop subgraph around a book.
--     This is the structured "context" you would hand to an LLM for grounding.
SELECT * FROM cypher('books_graph', $$
  MATCH (b:Book {title: 'Neuromancer'})-[*1..2]-(ctx)
  RETURN DISTINCT label(ctx) AS kind, ctx
$$) AS (kind agtype, ctx agtype);

-- (4) Aggregated context: assemble a per-author fact bundle.
SELECT * FROM cypher('books_graph', $$
  MATCH (a:Author {name: 'Isaac Asimov'})-[:WROTE]->(b:Book)
  WITH a, collect(b.title) AS books, count(*) AS book_count
  RETURN a.name AS author, book_count, books
$$) AS (author agtype, book_count agtype, books agtype);

-- (5) Original simple query still works against the richer graph.
SELECT * FROM cypher('books_graph', $$
  MATCH (author:Author)-[:WROTE]->(book:Book)-[:IN_GENRE]->(:Genre {name: 'Science Fiction'})
  RETURN author.name, book.title, book.year
  ORDER BY book.year
$$) AS (author_name agtype, book_title agtype, pub_year agtype);
