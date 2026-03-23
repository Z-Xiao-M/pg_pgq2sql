CREATE EXTENSION pg_pgq2sql;

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

SELECT common_name
FROM GRAPH_TABLE (
    social_graph
    MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
    WHERE a.name = 'Alice' AND b.name = 'Bob'
    COLUMNS (x.name AS common_name)
);

SELECT * FROM pg_pgq2sql_info($$
    SELECT common_name
    FROM GRAPH_TABLE (
        social_graph
        MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
        WHERE a.name = 'Alice' AND b.name = 'Bob'
        COLUMNS (x.name AS common_name)
    )
$$);

SELECT common_name
FROM LATERAL ( SELECT users_1.name AS common_name
        FROM users,
        follows,
        users users_1,
        follows follows_1,
        users users_2
        WHERE users.id = follows.follower AND users_1.id = follows.following AND users_2.id = follows_1.follower AND users_1.id = follows_1.following AND users.name::text = 'Alice'::text AND users_2.name::text = 'Bob'::text) "graph_table";

DROP TABLE users CASCADE;
DROP TABLE follows CASCADE;
DROP PROPERTY GRAPH social_graph;

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
    (1, '张三'), (2, '李四'), (3, '王五'), (4, '赵六');

INSERT INTO follows VALUES
    (1, 1, 2),  -- 张三 关注 李四
    (2, 1, 3),  -- 张三 关注 王五
    (3, 2, 3),  -- 李四 关注 王五
    (4, 2, 4),  -- 李四 关注 赵六
    (5, 3, 4);  -- 王五 关注 赵六


CREATE PROPERTY GRAPH social_graph
    VERTEX TABLES (users)
    EDGE TABLES (
        follows
            SOURCE KEY (follower) REFERENCES users(id)
            DESTINATION KEY (following) REFERENCES users(id)
    );

SELECT common_name
FROM GRAPH_TABLE (
    social_graph
    MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
    WHERE a.name = '张三' AND b.name = '李四'
    COLUMNS (x.name AS common_name)
);

SELECT * FROM pg_pgq2sql($$SELECT common_name
                            FROM GRAPH_TABLE (
                                social_graph
                                MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
                                WHERE a.name = '张三' AND b.name = '李四'
                                COLUMNS (x.name AS common_name)
                            )$$);

SELECT * FROM pg_pgq2sql_info($$SELECT common_name
                            FROM GRAPH_TABLE (
                                social_graph
                                MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
                                WHERE a.name = '张三' AND b.name = '李四'
                                COLUMNS (x.name AS common_name)
                            )$$);

SELECT common_name
FROM LATERAL ( SELECT users_1.name AS common_name
        FROM users,
        follows,
        users users_1,
        follows follows_1,
        users users_2
        WHERE users.id = follows.follower AND users_1.id = follows.following AND users_2.id = follows_1.follower AND users_1.id = follows_1.following AND users.name::text = '张三'::text AND users_2.name::text = '李四'::text) "graph_table";

EXPLAIN (VERBOSE, COSTS OFF)
SELECT common_name
FROM GRAPH_TABLE (
    social_graph
    MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
    WHERE a.name = '张三' AND b.name = '李四'
    COLUMNS (x.name AS common_name)
);

EXPLAIN (VERBOSE, COSTS OFF)
SELECT common_name
FROM LATERAL ( SELECT users_1.name AS common_name
        FROM users,
        follows,
        users users_1,
        follows follows_1,
        users users_2
        WHERE users.id = follows.follower AND users_1.id = follows.following AND users_2.id = follows_1.follower AND users_1.id = follows_1.following AND users.name::text = '张三'::text AND users_2.name::text = '李四'::text) "graph_table";

DROP TABLE users CASCADE;
DROP TABLE follows CASCADE;
DROP PROPERTY GRAPH social_graph;