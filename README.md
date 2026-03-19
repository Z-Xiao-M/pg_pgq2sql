# pg_pgq2sql

Convert SQL/PGQ (Property Graph Query) to plain SQL.

[中文](./README_CN.md) | English

`pg_pgq2sql` is a PostgreSQL extension that converts SQL/PGQ query statements back to plain SQL text after the query rewrite phase. This is useful for understanding how PostgreSQL transforms graph queries into relational queries.

## Requirements

Requires PostgreSQL master branch (SQL/PGQ is not yet in any released version).

## Installation

### Linux

Compile and install the extension:

```sh
cd contrib
git clone git@github.com:Z-Xiao-M/pg_pgq2sql.git
make && make install
```

## Getting Started

Create the extension:

```sql
CREATE EXTENSION pg_pgq2sql;
```

Create a property graph:

```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(50)
);

CREATE TABLE follows (
    id INT PRIMARY KEY,
    follower INT REFERENCES users(id),
    following INT REFERENCES users(id)
);

INSERT INTO users VALUES
    (1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'David');

INSERT INTO follows VALUES
    (1, 1, 2),  -- Alice follows Bob
    (2, 1, 3),  -- Alice follows Charlie
    (3, 2, 3),  -- Bob follows Charlie
    (4, 2, 4),  -- Bob follows David
    (5, 3, 4);  -- Charlie follows David

CREATE PROPERTY GRAPH social_graph
    VERTEX TABLES (users)
    EDGE TABLES (
        follows
            SOURCE KEY (follower) REFERENCES users(id)
            DESTINATION KEY (following) REFERENCES users(id)
    );
```

Use `pg_pgq2sql` to see how a graph query is transformed:

```sql
SELECT * FROM pg_pgq2sql_print($$
    SELECT common_name
    FROM GRAPH_TABLE (
        social_graph
        MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
        WHERE a.name = 'Alice' AND b.name = 'Bob'
        COLUMNS (x.name AS common_name)
    )
$$);
```

**Result:**

```sql
 SELECT common_name
   FROM LATERAL ( SELECT users_1.name AS common_name
           FROM users,
            follows,
            users users_1,
            follows follows_1,
            users users_2
          WHERE users.id = follows.follower AND users_1.id = follows.following AND users_2.id = follows_1.follower AND users_1.id = follows_1.following AND users.name::text = 'Alice'::text AND users_2.name::text = 'Bob'::text) "graph_table"
```

## Functions

### pg_pgq2sql(query text)

Parse and rewrite a SQL/PGQ query, then return the converted plain SQL text.

```sql
SELECT pg_pgq2sql($$SELECT ... FROM GRAPH_TABLE (...)$$);
```

### pg_pgq2sql_print(query text)

Same as `pg_pgq2sql`, but prints the result to server log/stdout and returns NULL. Easier to copy.

```sql
SELECT pg_pgq2sql_print($$SELECT ... FROM GRAPH_TABLE (...)$$);
```

## Running Tests

```sh
make check
```
