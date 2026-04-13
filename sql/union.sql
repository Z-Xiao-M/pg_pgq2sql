DROP TABLE IF EXISTS follows cascade;
DROP TABLE IF EXISTS users cascade;

-- 创建社交图的多标签版本
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    user_type VARCHAR(20)
);

CREATE TABLE follows (
    id INT PRIMARY KEY,
    follower INT REFERENCES users(id),
    following INT REFERENCES users(id)
);

CREATE TABLE premium_follows (
    id INT PRIMARY KEY,
    follower INT REFERENCES users(id),
    following INT REFERENCES users(id)
);

INSERT INTO users VALUES
    (1, 'Alice', 'regular'),
    (2, 'Bob', 'regular'),
    (3, 'Charlie', 'premium'),
    (4, 'David', 'premium');

INSERT INTO follows VALUES
    (1, 1, 2),
    (2, 1, 3);

INSERT INTO premium_follows VALUES
    (1, 3, 4),
    (2, 2, 3);

CREATE PROPERTY GRAPH social_graph_multi
    VERTEX TABLES (users)
    EDGE TABLES (
        follows
            SOURCE KEY (follower) REFERENCES users(id)
            DESTINATION KEY (following) REFERENCES users(id)
            LABEL connections,
        premium_follows
            SOURCE KEY (follower) REFERENCES users(id)
            DESTINATION KEY (following) REFERENCES users(id)
            LABEL connections
    );

SELECT * FROM pg_pgq2sql($$
    SELECT common_name
    FROM GRAPH_TABLE (
        social_graph_multi
        MATCH (a IS users)-[IS connections]->(x IS users)
        WHERE a.name = 'Alice'
        COLUMNS (x.name AS common_name)
    )
$$);


SELECT * FROM pg_pgq2sql_info($$
    SELECT common_name
    FROM GRAPH_TABLE (
        social_graph_multi
        MATCH (a IS users)-[IS connections]->(x IS users)
        WHERE a.name = 'Alice'
        COLUMNS (x.name AS common_name)
    )
$$);

SELECT common_name
FROM LATERAL ( SELECT users_1.name AS common_name
        FROM users,
        follows,
        users users_1
        WHERE users.id = follows.follower AND users_1.id = follows.following AND users.name::text = 'Alice'::text
    UNION ALL
        SELECT users_1.name AS common_name
        FROM users,
        premium_follows,
        users users_1
        WHERE users.id = premium_follows.follower AND users_1.id = premium_follows.following AND users.name::text = 'Alice'::text) "graph_table";

DROP TABLE IF EXISTS follows cascade;
DROP TABLE IF EXISTS users cascade;
DROP PROPERTY GRAPH social_graph_multi;