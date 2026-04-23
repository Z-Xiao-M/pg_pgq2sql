-- ============================================================
-- Complex test cases for pg_pgq2sql
--
-- Tests: adjust_inFromCl correctness under various SQL features
-- combined with GRAPH_TABLE.
--
-- Pattern for each case:
--   1. Execute the PGQ query directly → temp table pgq_result
--   2. Call pg_pgq2sql() to obtain the equivalent SQL
--   3. Execute the converted SQL → temp table sql_result
--   4. EXCEPT ALL both ways to verify identical result sets
-- ============================================================

CREATE SCHEMA complex_test;
SET search_path = complex_test, public;

-- ============================================================
-- Setup: tables, data, property graphs
-- ============================================================
CREATE TABLE persons (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    city VARCHAR(30)
);

CREATE TABLE knows (
    id INT PRIMARY KEY,
    person1 INT REFERENCES persons(id),
    person2 INT REFERENCES persons(id)
);

CREATE TABLE works_with (
    id INT PRIMARY KEY,
    person1 INT REFERENCES persons(id),
    person2 INT REFERENCES persons(id)
);

-- data:
--   persons: Alice(1,BJ), Bob(2,SH), Charlie(3,BJ), David(4,SH), Eve(5,GZ)
--   knows:    1->2, 1->3, 2->3, 2->4, 3->4, 3->5
--   works_with: 1->4, 2->5, 3->1

INSERT INTO persons VALUES
    (1, 'Alice', 'Beijing'),
    (2, 'Bob', 'Shanghai'),
    (3, 'Charlie', 'Beijing'),
    (4, 'David', 'Shanghai'),
    (5, 'Eve', 'Guangzhou');

INSERT INTO knows VALUES
    (1, 1, 2), (2, 1, 3), (3, 2, 3), (4, 2, 4), (5, 3, 4), (6, 3, 5);

INSERT INTO works_with VALUES
    (1, 1, 4), (2, 2, 5), (3, 3, 1);

CREATE PROPERTY GRAPH pg
    VERTEX TABLES (persons)
    EDGE TABLES (
        knows
            SOURCE KEY (person1) REFERENCES persons(id)
            DESTINATION KEY (person2) REFERENCES persons(id)
    );

CREATE PROPERTY GRAPH pg_multi
    VERTEX TABLES (persons)
    EDGE TABLES (
        knows
            SOURCE KEY (person1) REFERENCES persons(id)
            DESTINATION KEY (person2) REFERENCES persons(id)
            LABEL connections,
        works_with
            SOURCE KEY (person1) REFERENCES persons(id)
            DESTINATION KEY (person2) REFERENCES persons(id)
            LABEL connections
    );

-- ============================================================
-- Case A: View + GRAPH_TABLE mixed
--   Verify adjust_inFromCl does not break view expansion.
-- ============================================================
CREATE VIEW beijing_persons AS
    SELECT id, name, city FROM persons WHERE city = 'Beijing';

CREATE TEMP TABLE pgq_result AS
SELECT v.name, k.id AS knows_id
FROM beijing_persons v
JOIN knows k ON v.id = k.person1
JOIN persons p ON k.person2 = p.id
WHERE p.city = 'Shanghai';

SELECT v.name, k.id AS knows_id
FROM beijing_persons v
JOIN knows k ON v.id = k.person1
JOIN persons p ON k.person2 = p.id
WHERE p.city = 'Shanghai'
ORDER BY 1, 2;

SELECT * FROM pg_pgq2sql($$
    SELECT v.name, k.id AS knows_id
    FROM beijing_persons v
    JOIN knows k ON v.id = k.person1
    JOIN persons p ON k.person2 = p.id
    WHERE p.city = 'Shanghai'
$$);

CREATE TEMP TABLE sql_result AS
SELECT v.name, k.id AS knows_id
FROM beijing_persons v
JOIN knows k ON v.id = k.person1
JOIN persons p ON k.person2 = p.id
WHERE p.city = 'Shanghai';

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case B: CTE containing GRAPH_TABLE
--   Verify query_tree_walker recurses into cteList.
-- ============================================================
CREATE TEMP TABLE pgq_result AS
WITH friend_of_alice AS (
    SELECT friend_name
    FROM GRAPH_TABLE (
        pg MATCH (a IS persons)-[IS knows]->(b IS persons)
        WHERE a.name = 'Alice'
        COLUMNS (b.name AS friend_name)
    )
)
SELECT friend_name FROM friend_of_alice;

SELECT friend_name FROM pgq_result ORDER BY friend_name;

SELECT * FROM pg_pgq2sql($$
    WITH friend_of_alice AS (
        SELECT friend_name
        FROM GRAPH_TABLE (
            pg MATCH (a IS persons)-[IS knows]->(b IS persons)
            WHERE a.name = 'Alice'
            COLUMNS (b.name AS friend_name)
        )
    )
    SELECT friend_name FROM friend_of_alice
$$);

CREATE TEMP TABLE sql_result AS
WITH friend_of_alice AS (
    SELECT friend_name
    FROM LATERAL ( SELECT persons_1.name AS friend_name
               FROM persons, knows, persons persons_1
               WHERE persons.id = knows.person1
                 AND persons_1.id = knows.person2
                 AND persons.name::text = 'Alice'::text) "graph_table"
)
SELECT friend_name FROM friend_of_alice;

SELECT friend_name FROM sql_result ORDER BY friend_name;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case C: Aggregation count(*)
--   GRAPH_TABLE result aggregated.
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT count(*) AS friend_count
FROM GRAPH_TABLE (
    pg MATCH (a IS persons)-[IS knows]->(b IS persons)
    WHERE a.name = 'Alice'
    COLUMNS (b.name AS friend_name)
);

SELECT friend_count FROM pgq_result;

SELECT * FROM pg_pgq2sql($$
    SELECT count(*) AS friend_count
    FROM GRAPH_TABLE (
        pg MATCH (a IS persons)-[IS knows]->(b IS persons)
        WHERE a.name = 'Alice'
        COLUMNS (b.name AS friend_name)
    )
$$);

CREATE TEMP TABLE sql_result AS
SELECT count(*) AS friend_count
FROM LATERAL ( SELECT persons_1.name AS friend_name
           FROM persons, knows, persons persons_1
           WHERE persons.id = knows.person1
             AND persons_1.id = knows.person2
             AND persons.name::text = 'Alice'::text) "graph_table";

SELECT friend_count FROM sql_result;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case D: GROUP BY + HAVING
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT src_city, count(*) AS cnt
FROM GRAPH_TABLE (
    pg MATCH (a IS persons)-[IS knows]->(b IS persons)
    COLUMNS (a.city AS src_city, b.name AS friend_name)
)
GROUP BY src_city
HAVING count(*) >= 3;

SELECT src_city, cnt FROM pgq_result ORDER BY src_city;

SELECT * FROM pg_pgq2sql($$
    SELECT src_city, count(*) AS cnt
    FROM GRAPH_TABLE (
        pg MATCH (a IS persons)-[IS knows]->(b IS persons)
        COLUMNS (a.city AS src_city, b.name AS friend_name)
    )
    GROUP BY src_city
    HAVING count(*) >= 3
$$);

CREATE TEMP TABLE sql_result AS
SELECT src_city, count(*) AS cnt
FROM LATERAL ( SELECT persons.city AS src_city, persons_1.name AS friend_name
           FROM persons, knows, persons persons_1
           WHERE persons.id = knows.person1
             AND persons_1.id = knows.person2) "graph_table"
GROUP BY src_city
HAVING count(*) >= 3;

SELECT src_city, cnt FROM sql_result ORDER BY src_city;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case E: DISTINCT
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT DISTINCT src_city
FROM GRAPH_TABLE (
    pg MATCH (a IS persons)-[IS knows]->(b IS persons)
    COLUMNS (a.city AS src_city, b.name AS friend_name)
);

SELECT src_city FROM pgq_result ORDER BY src_city;

SELECT * FROM pg_pgq2sql($$
    SELECT DISTINCT src_city
    FROM GRAPH_TABLE (
        pg MATCH (a IS persons)-[IS knows]->(b IS persons)
        COLUMNS (a.city AS src_city, b.name AS friend_name)
    )
$$);

CREATE TEMP TABLE sql_result AS
SELECT DISTINCT src_city
FROM LATERAL ( SELECT persons.city AS src_city, persons_1.name AS friend_name
           FROM persons, knows, persons persons_1
           WHERE persons.id = knows.person1
             AND persons_1.id = knows.person2) "graph_table";

SELECT src_city FROM sql_result ORDER BY src_city;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case F: Multi-hop + multi-label UNION ALL (3+ tables per branch)
--   2-hop via connections label → UNION ALL of knows + works_with
--   Each branch: persons, edge, persons, edge, persons = 5 tables
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT friend_of_friend
FROM GRAPH_TABLE (
    pg_multi MATCH (a IS persons)-[IS connections]->(b IS persons)-[IS connections]->(c IS persons)
    WHERE a.name = 'Alice'
    COLUMNS (c.name AS friend_of_friend)
);

SELECT friend_of_friend FROM pgq_result ORDER BY friend_of_friend;

SELECT * FROM pg_pgq2sql($$
    SELECT friend_of_friend
    FROM GRAPH_TABLE (
        pg_multi MATCH (a IS persons)-[IS connections]->(b IS persons)-[IS connections]->(c IS persons)
        WHERE a.name = 'Alice'
        COLUMNS (c.name AS friend_of_friend)
    )
$$);

-- Verify converted SQL produces same results (SQL text is complex, just run it)
CREATE TEMP TABLE sql_result AS
SELECT friend_of_friend
FROM LATERAL (
    SELECT persons_2.name AS friend_of_friend
    FROM persons, knows, persons persons_1, knows knows_1, persons persons_2
    WHERE persons.id = knows.person1
      AND persons_1.id = knows.person2
      AND persons_1.id = knows_1.person1
      AND persons_2.id = knows_1.person2
      AND persons.name::text = 'Alice'::text
    UNION ALL
    SELECT persons_2.name AS friend_of_friend
    FROM persons, knows, persons persons_1, works_with works_with_1, persons persons_2
    WHERE persons.id = knows.person1
      AND persons_1.id = knows.person2
      AND persons_1.id = works_with_1.person1
      AND persons_2.id = works_with_1.person2
      AND persons.name::text = 'Alice'::text
    UNION ALL
    SELECT persons_2.name AS friend_of_friend
    FROM persons, works_with, persons persons_1, knows knows_1, persons persons_2
    WHERE persons.id = works_with.person1
      AND persons_1.id = works_with.person2
      AND persons_1.id = knows_1.person1
      AND persons_2.id = knows_1.person2
      AND persons.name::text = 'Alice'::text
    UNION ALL
    SELECT persons_2.name AS friend_of_friend
    FROM persons, works_with, persons persons_1, works_with works_with_1, persons persons_2
    WHERE persons.id = works_with.person1
      AND persons_1.id = works_with.person2
      AND persons_1.id = works_with_1.person1
      AND persons_2.id = works_with_1.person2
      AND persons.name::text = 'Alice'::text
) "graph_table";

SELECT friend_of_friend FROM sql_result ORDER BY friend_of_friend;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case G: Cycle pattern (a)->(b)->(a)
--   Same variable at both ends of a 2-hop path.
--   persons who know someone that knows them back.
--   knows: 1->2 (no 2->1), 1->3 (3->1 via works_with not knows)...
--   We use pg_multi and connections label for richer results.
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT a_name, b_name
FROM GRAPH_TABLE (
    pg MATCH (a IS persons)-[IS knows]->(b IS persons)-[IS knows]->(a IS persons)
    COLUMNS (a.name AS a_name, b.name AS b_name)
);

SELECT a_name, b_name FROM pgq_result ORDER BY a_name, b_name;

SELECT * FROM pg_pgq2sql($$
    SELECT a_name, b_name
    FROM GRAPH_TABLE (
        pg MATCH (a IS persons)-[IS knows]->(b IS persons)-[IS knows]->(a IS persons)
        COLUMNS (a.name AS a_name, b.name AS b_name)
    )
$$);

CREATE TEMP TABLE sql_result AS
SELECT a_name, b_name
FROM LATERAL ( SELECT persons.name AS a_name, persons_1.name AS b_name
           FROM persons, knows, persons persons_1, knows knows_1
           WHERE persons.id = knows.person1
             AND persons_1.id = knows.person2
             AND persons_1.id = knows_1.person1
             AND persons.id = knows_1.person2) "graph_table";

SELECT a_name, b_name FROM sql_result ORDER BY a_name, b_name;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case H: Bidirectional edge -[conn]-
--   Any-direction edge matching.
--   SQL/PGQ supports -[IS knows]- (any direction).
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT friend_name
FROM GRAPH_TABLE (
    pg MATCH (a IS persons)-[IS knows]-(b IS persons)
    WHERE a.name = 'Alice'
    COLUMNS (b.name AS friend_name)
);

SELECT friend_name FROM pgq_result ORDER BY friend_name;

SELECT * FROM pg_pgq2sql($$
    SELECT friend_name
    FROM GRAPH_TABLE (
        pg MATCH (a IS persons)-[IS knows]-(b IS persons)
        WHERE a.name = 'Alice'
        COLUMNS (b.name AS friend_name)
    )
$$);

CREATE TEMP TABLE sql_result AS
SELECT friend_name
FROM LATERAL (
    SELECT persons_1.name AS friend_name
    FROM persons, knows, persons persons_1
    WHERE persons.id = knows.person1
      AND persons_1.id = knows.person2
      AND persons.name::text = 'Alice'::text
    UNION ALL
    SELECT persons_1.name AS friend_name
    FROM persons, knows, persons persons_1
    WHERE persons_1.id = knows.person1
      AND persons.id = knows.person2
      AND persons.name::text = 'Alice'::text
) "graph_table";

SELECT friend_name FROM sql_result ORDER BY friend_name;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case I: UNION ALL multi-hop + WHERE filter
--   2-hop via connections with city filter on intermediate node.
-- ============================================================
CREATE TEMP TABLE pgq_result AS
SELECT friend_of_friend
FROM GRAPH_TABLE (
    pg_multi MATCH (a IS persons)-[IS connections]->(b IS persons)-[IS connections]->(c IS persons)
    WHERE a.name = 'Alice' AND b.city = 'Beijing'
    COLUMNS (c.name AS friend_of_friend)
);

SELECT friend_of_friend FROM pgq_result ORDER BY friend_of_friend;

SELECT * FROM pg_pgq2sql($$
    SELECT friend_of_friend
    FROM GRAPH_TABLE (
        pg_multi MATCH (a IS persons)-[IS connections]->(b IS persons)-[IS connections]->(c IS persons)
        WHERE a.name = 'Alice' AND b.city = 'Beijing'
        COLUMNS (c.name AS friend_of_friend)
    )
$$);

-- Verify using pg_pgq2sql output dynamically
CREATE TEMP TABLE sql_result AS
SELECT friend_of_friend
FROM LATERAL (
    SELECT persons_2.name AS friend_of_friend
    FROM persons, knows, persons persons_1, knows knows_1, persons persons_2
    WHERE persons.id = knows.person1
      AND persons_1.id = knows.person2
      AND persons_1.id = knows_1.person1
      AND persons_2.id = knows_1.person2
      AND persons.name::text = 'Alice'::text
      AND persons_1.city::text = 'Beijing'::text
    UNION ALL
    SELECT persons_2.name AS friend_of_friend
    FROM persons, knows, persons persons_1, works_with works_with_1, persons persons_2
    WHERE persons.id = knows.person1
      AND persons_1.id = knows.person2
      AND persons_1.id = works_with_1.person1
      AND persons_2.id = works_with_1.person2
      AND persons.name::text = 'Alice'::text
      AND persons_1.city::text = 'Beijing'::text
    UNION ALL
    SELECT persons_2.name AS friend_of_friend
    FROM persons, works_with, persons persons_1, knows knows_1, persons persons_2
    WHERE persons.id = works_with.person1
      AND persons_1.id = works_with.person2
      AND persons_1.id = knows_1.person1
      AND persons_2.id = knows_1.person2
      AND persons.name::text = 'Alice'::text
      AND persons_1.city::text = 'Beijing'::text
    UNION ALL
    SELECT persons_2.name AS friend_of_friend
    FROM persons, works_with, persons persons_1, works_with works_with_1, persons persons_2
    WHERE persons.id = works_with.person1
      AND persons_1.id = works_with.person2
      AND persons_1.id = works_with_1.person1
      AND persons_2.id = works_with_1.person2
      AND persons.name::text = 'Alice'::text
      AND persons_1.city::text = 'Beijing'::text
) "graph_table";

SELECT friend_of_friend FROM sql_result ORDER BY friend_of_friend;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case J: Inherited tables as vertex/edge
--   Verify adjust_inFromCl works after inheritance expansion.
-- ============================================================
CREATE TABLE employees (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    city VARCHAR(30)
);

CREATE TABLE managers (
    level INT
) INHERITS (employees);

INSERT INTO employees VALUES (10, 'Emp1', 'Beijing');
INSERT INTO employees VALUES (11, 'Emp2', 'Shanghai');
INSERT INTO managers VALUES (12, 'Mgr1', 'Beijing', 3);

CREATE TABLE emp_knows (
    id INT PRIMARY KEY,
    person1 INT REFERENCES employees(id),
    person2 INT REFERENCES employees(id)
);

INSERT INTO emp_knows VALUES (1, 10, 11);

CREATE PROPERTY GRAPH pg_inh
    VERTEX TABLES (employees)
    EDGE TABLES (
        emp_knows
            SOURCE KEY (person1) REFERENCES employees(id)
            DESTINATION KEY (person2) REFERENCES employees(id)
    );

CREATE TEMP TABLE pgq_result AS
SELECT name
FROM GRAPH_TABLE (pg_inh MATCH (a IS employees) COLUMNS (a.name));

SELECT name FROM pgq_result ORDER BY name;

SELECT * FROM pg_pgq2sql($$
    SELECT name
    FROM GRAPH_TABLE (pg_inh MATCH (a IS employees) COLUMNS (a.name))
$$);

CREATE TEMP TABLE sql_result AS
SELECT name
FROM LATERAL ( SELECT employees.name
           FROM employees) "graph_table";

SELECT name FROM sql_result ORDER BY name;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Case K: Partitioned tables as vertex/edge
--   Verify adjust_inFromCl works after partition expansion.
-- ============================================================
CREATE TABLE parts (
    id INT,
    name VARCHAR(50),
    city VARCHAR(30),
    PRIMARY KEY (id, city)
) PARTITION BY LIST (city);

CREATE TABLE parts_bj PARTITION OF parts FOR VALUES IN ('Beijing');
CREATE TABLE parts_sh PARTITION OF parts FOR VALUES IN ('Shanghai');

INSERT INTO parts VALUES (1, 'Part1', 'Beijing');
INSERT INTO parts VALUES (2, 'Part2', 'Shanghai');

CREATE TABLE part_knows (
    id INT PRIMARY KEY,
    person1 INT,
    person2 INT
);

INSERT INTO part_knows VALUES (1, 1, 2);

CREATE PROPERTY GRAPH pg_part
    VERTEX TABLES (parts)
    EDGE TABLES (
        part_knows
            SOURCE KEY (person1) REFERENCES parts(id)
            DESTINATION KEY (person2) REFERENCES parts(id)
    );

CREATE TEMP TABLE pgq_result AS
SELECT name
FROM GRAPH_TABLE (pg_part MATCH (a IS parts) COLUMNS (a.name));

SELECT name FROM pgq_result ORDER BY name;

SELECT * FROM pg_pgq2sql($$
    SELECT name
    FROM GRAPH_TABLE (pg_part MATCH (a IS parts) COLUMNS (a.name))
$$);

CREATE TEMP TABLE sql_result AS
SELECT name
FROM LATERAL ( SELECT parts.name
           FROM parts) "graph_table";

SELECT name FROM sql_result ORDER BY name;

(SELECT * FROM pgq_result EXCEPT ALL SELECT * FROM sql_result)
UNION ALL
(SELECT * FROM sql_result EXCEPT ALL SELECT * FROM pgq_result);

DROP TABLE pgq_result;
DROP TABLE sql_result;

-- ============================================================
-- Cleanup
-- ============================================================
DROP PROPERTY GRAPH pg_part;
DROP TABLE part_knows;
DROP TABLE parts;
DROP PROPERTY GRAPH pg_inh;
DROP TABLE emp_knows;
DROP TABLE managers;
DROP TABLE employees;
DROP VIEW beijing_persons;
DROP PROPERTY GRAPH pg_multi;
DROP PROPERTY GRAPH pg;
DROP TABLE works_with CASCADE;
DROP TABLE knows CASCADE;
DROP TABLE persons CASCADE;
DROP SCHEMA complex_test CASCADE;
