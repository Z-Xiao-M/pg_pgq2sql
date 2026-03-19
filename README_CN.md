# pg_pgq2sql

将 SQL/PGQ（属性图查询）转换为标准 SQL。

中文 | [English](./README.md)

`pg_pgq2sql` 是一个 PostgreSQL 扩展，用于将 SQL/PGQ 查询语句在经过查询重写阶段后转换回普通的 SQL 文本。这对于理解 PostgreSQL 如何将图查询转换为关系查询非常有用。

## 环境要求

需要 PostgreSQL master 分支（SQL/PGQ 尚未在任何正式版本中发布）。

## 安装

### Linux

编译并安装扩展：

```sh
cd contrib/pg_pgq2sql
make
make install
```

## 快速开始

创建扩展

```sql
CREATE EXTENSION pg_pgq2sql;
```

创建属性图：

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
```

使用 `pg_pgq2sql` 查看图查询如何被转换：

```sql
SELECT * FROM pg_pgq2sql($$
    SELECT common_name
    FROM GRAPH_TABLE (
        social_graph
        MATCH (a IS users)-[]->(x IS users)<-[]-(b IS users)
        WHERE a.name = '张三' AND b.name = '李四'
        COLUMNS (x.name AS common_name)
    )
$$);
```

**结果：**

```sql
SELECT common_name
FROM LATERAL (
    SELECT users_1.name AS common_name
    FROM users,
        follows,
        users users_1,
        follows follows_1,
        users users_2
        WHERE users.id = follows.follower AND users_1.id = follows.following AND users_2.id = follows_1.follower AND users_1.id = follows_1.following AND users.name::text = '张三'::text AND users_2.name::text = '李四'::text
    ) "graph_table"
```

## 函数

### pg_pgq2sql(query text)

解析并重写 SQL/PGQ 查询，然后返回转换后的普通 SQL 文本。

```sql
SELECT pg_pgq2sql($$SELECT ... FROM GRAPH_TABLE (...)$$);
```

### pg_pgq2sql_print(query text)

功能与 `pg_pgq2sql` 相同，但将结果打印到服务器日志/标准输出并返回 NULL，更方便复制。

```sql
SELECT pg_pgq2sql_print($$SELECT ... FROM GRAPH_TABLE (...)$$);
```

## 运行测试

```sh
make check
```
