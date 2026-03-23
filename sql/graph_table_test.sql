CREATE SCHEMA graph_table_tests;
GRANT USAGE ON SCHEMA graph_table_tests TO PUBLIC;
SET search_path = graph_table_tests, public;

CREATE TABLE products (
    product_no integer PRIMARY KEY,
    name varchar,
    price numeric
);

CREATE TABLE customers (
    customer_id integer PRIMARY KEY,
    name varchar,
    address varchar
);

CREATE TABLE orders (
    order_id integer PRIMARY KEY,
    ordered_when date
);

CREATE TABLE order_items (
    order_items_id integer PRIMARY KEY,
    order_id integer REFERENCES orders (order_id),
    product_no integer REFERENCES products (product_no),
    quantity integer
);

CREATE TABLE customer_orders (
    customer_orders_id integer PRIMARY KEY,
    customer_id integer REFERENCES customers (customer_id),
    order_id integer REFERENCES orders (order_id)
);

CREATE TABLE wishlists (
    wishlist_id integer PRIMARY KEY,
    wishlist_name varchar
);

CREATE TABLE wishlist_items (
    wishlist_items_id integer PRIMARY KEY,
    wishlist_id integer REFERENCES wishlists (wishlist_id),
    product_no integer REFERENCES products (product_no)
);

CREATE TABLE customer_wishlists (
    customer_wishlist_id integer PRIMARY KEY,
    customer_id integer REFERENCES customers (customer_id),
    wishlist_id integer REFERENCES wishlists (wishlist_id)
);

CREATE PROPERTY GRAPH myshop
    VERTEX TABLES (
        products,
        customers,
        orders
           DEFAULT LABEL
           LABEL lists PROPERTIES (order_id AS node_id, 'order'::varchar(10) AS list_type),
        wishlists
           DEFAULT LABEL
           LABEL lists PROPERTIES (wishlist_id AS node_id, 'wishlist'::varchar(10) AS list_type)
    )
    EDGE TABLES (
        order_items KEY (order_items_id)
            SOURCE KEY (order_id) REFERENCES orders (order_id)
            DESTINATION KEY (product_no) REFERENCES products (product_no)
            DEFAULT LABEL
            LABEL list_items PROPERTIES (order_id AS link_id, product_no),
        wishlist_items KEY (wishlist_items_id)
            SOURCE KEY (wishlist_id) REFERENCES wishlists (wishlist_id)
            DESTINATION KEY (product_no) REFERENCES products (product_no)
            DEFAULT LABEL
            LABEL list_items PROPERTIES (wishlist_id AS link_id, product_no),
        customer_orders KEY (customer_orders_id)
            SOURCE KEY (customer_id) REFERENCES customers (customer_id)
            DESTINATION KEY (order_id) REFERENCES orders (order_id)
            DEFAULT LABEL
            LABEL cust_lists PROPERTIES (customer_id, order_id AS link_id),
        customer_wishlists KEY (customer_wishlist_id)
            SOURCE KEY (customer_id) REFERENCES customers (customer_id)
            DESTINATION KEY (wishlist_id) REFERENCES wishlists (wishlist_id)
            DEFAULT LABEL
            LABEL cust_lists PROPERTIES (customer_id, wishlist_id AS link_id)
    );

INSERT INTO products VALUES
    (1, 'product1', 10),
    (2, 'product2', 20),
    (3, 'product3', 30);
INSERT INTO customers VALUES
    (1, 'customer1', 'US'),
    (2, 'customer2', 'CA'),
    (3, 'customer3', 'GL');
INSERT INTO orders VALUES
    (1, date '2024-01-01'),
    (2, date '2024-01-02'),
    (3, date '2024-01-03');
INSERT INTO wishlists VALUES
    (1, 'wishlist1'),
    (2, 'wishlist2'),
    (3, 'wishlist3');
INSERT INTO order_items (order_items_id, order_id, product_no, quantity) VALUES
    (1, 1, 1, 5),
    (2, 1, 2, 10),
    (3, 2, 1, 7);
INSERT INTO customer_orders (customer_orders_id, customer_id, order_id) VALUES
    (1, 1, 1),
    (2, 2, 2);
INSERT INTO customer_wishlists (customer_wishlist_id, customer_id, wishlist_id) VALUES
    (1, 2, 3),
    (2, 3, 1),
    (3, 3, 2);
INSERT INTO wishlist_items (wishlist_items_id, wishlist_id, product_no) VALUES
    (1, 1, 2),
    (2, 1, 3),
    (3, 2, 1),
    (4, 3, 1);

-- single element path pattern
SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers) COLUMNS (c.name));
SELECT pg_pgq2sql_info('SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers) COLUMNS (c.name))');
 SELECT name
   FROM LATERAL ( SELECT customers.name
           FROM customers) "graph_table";

SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers WHERE c.address = 'US')-[IS customer_orders]->(o IS orders) COLUMNS (c.name));
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers WHERE c.address = 'US')-[IS customer_orders]->(o IS orders) COLUMNS (c.name))$$);
 SELECT name
   FROM LATERAL ( SELECT customers.name
           FROM customers,
            customer_orders,
            orders
          WHERE customers.address::text = 'US'::text AND customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id) "graph_table";

-- graph element specification without label or variable
SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers WHERE c.address = 'US')-[]->(o IS orders) COLUMNS (c.name AS customer_name));
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers WHERE c.address = 'US')-[]->(o IS orders) COLUMNS (c.name AS customer_name));$$);
 SELECT customer_name
   FROM LATERAL ( SELECT customers.name AS customer_name
           FROM customers,
            customer_orders,
            orders
          WHERE customers.address::text = 'US'::text AND customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id) "graph_table";

SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)-[co IS customer_orders]->(o IS orders WHERE o.ordered_when = date '2024-01-02') COLUMNS (c.name, c.address));
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)-[co IS customer_orders]->(o IS orders WHERE o.ordered_when = date '2024-01-02') COLUMNS (c.name, c.address));$$);
 SELECT name,
    address
   FROM LATERAL ( SELECT customers.name,
            customers.address
           FROM customers,
            customer_orders,
            orders
          WHERE customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id AND orders.ordered_when = '01-02-2024'::date) "graph_table";

SELECT * FROM GRAPH_TABLE (myshop MATCH (o IS orders)-[IS customer_orders]->(c IS customers) COLUMNS (c.name, o.ordered_when));
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (o IS orders)-[IS customer_orders]->(c IS customers) COLUMNS (c.name, o.ordered_when));$$);
 SELECT name,
    ordered_when
   FROM LATERAL ( SELECT NULL::character varying AS name,
            NULL::date AS ordered_when
          WHERE false) "graph_table";

SELECT * FROM GRAPH_TABLE (myshop MATCH (o IS orders)<-[IS customer_orders]-(c IS customers) COLUMNS (c.name, o.ordered_when));
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (o IS orders)<-[IS customer_orders]-(c IS customers) COLUMNS (c.name, o.ordered_when));$$);
 SELECT name,
    ordered_when
   FROM LATERAL ( SELECT customers.name,
            orders.ordered_when
           FROM orders,
            customer_orders,
            customers
          WHERE customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id) "graph_table";

-- spaces around pattern operators
SELECT * FROM GRAPH_TABLE (myshop MATCH ( o IS orders ) <- [ IS customer_orders ] - (c IS customers) COLUMNS ( c.name, o.ordered_when));
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH ( o IS orders ) <- [ IS customer_orders ] - (c IS customers) COLUMNS ( c.name, o.ordered_when));$$);
 SELECT name,
    ordered_when
   FROM LATERAL ( SELECT customers.name,
            orders.ordered_when
           FROM orders,
            customer_orders,
            customers
          WHERE customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id) "graph_table";

SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)-[IS cust_lists]->(l IS lists)-[ IS list_items]->(p IS products) COLUMNS (c.name AS customer_name, p.name AS product_name, l.list_type)) ORDER BY customer_name, product_name, list_type;
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)-[IS cust_lists]->(l IS lists)-[ IS list_items]->(p IS products) COLUMNS (c.name AS customer_name, p.name AS product_name, l.list_type)) ORDER BY customer_name, product_name, list_type;$$);
 SELECT customer_name,
    product_name,
    list_type
   FROM LATERAL ( SELECT customers.name AS customer_name,
            products.name AS product_name,
            'order'::character varying(10) AS list_type
           FROM customers,
            customer_orders,
            orders,
            order_items,
            products
          WHERE customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id AND orders.order_id = order_items.order_id AND products.product_no = order_items.product_no
        UNION ALL
         SELECT customers.name AS customer_name,
            products.name AS product_name,
            'wishlist'::character varying(10) AS list_type
           FROM customers,
            customer_wishlists,
            wishlists,
            wishlist_items,
            products
          WHERE customers.customer_id = customer_wishlists.customer_id AND wishlists.wishlist_id = customer_wishlists.wishlist_id AND wishlists.wishlist_id = wishlist_items.wishlist_id AND products.product_no = wishlist_items.product_no) "graph_table"
  ORDER BY customer_name, product_name, list_type;

-- label disjunction
SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)-[IS customer_orders | customer_wishlists ]->(l IS orders | wishlists)-[ IS list_items]->(p IS products) COLUMNS (c.name AS customer_name, p.name AS product_name)) ORDER BY customer_name, product_name;
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)-[IS customer_orders | customer_wishlists ]->(l IS orders | wishlists)-[ IS list_items]->(p IS products) COLUMNS (c.name AS customer_name, p.name AS product_name)) ORDER BY customer_name, product_name;$$);
SELECT customer_name,
    product_name
   FROM LATERAL ( SELECT customers.name AS customer_name,
            products.name AS product_name
           FROM customers,
            customer_orders,
            orders,
            order_items,
            products
          WHERE customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id AND orders.order_id = order_items.order_id AND products.product_no = order_items.product_no
        UNION ALL
         SELECT customers.name AS customer_name,
            products.name AS product_name
           FROM customers,
            customer_wishlists,
            wishlists,
            wishlist_items,
            products
          WHERE customers.customer_id = customer_wishlists.customer_id AND wishlists.wishlist_id = customer_wishlists.wishlist_id AND wishlists.wishlist_id = wishlist_items.wishlist_id AND products.product_no = wishlist_items.product_no) "graph_table"
  ORDER BY customer_name, product_name;

-- vertex to vertex connection abbreviation
SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)->(o IS orders) COLUMNS (c.name, o.ordered_when)) ORDER BY 1;
SELECT pg_pgq2sql_info($$SELECT * FROM GRAPH_TABLE (myshop MATCH (c IS customers)->(o IS orders) COLUMNS (c.name, o.ordered_when)) ORDER BY 1;$$);
 SELECT name,
    ordered_when
   FROM LATERAL ( SELECT customers.name,
            orders.ordered_when
           FROM customers,
            customer_orders,
            orders
          WHERE customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id) "graph_table"
  ORDER BY name;

-- lateral test
CREATE TABLE x1 (a int, b text);
INSERT INTO x1 VALUES (1, 'one'), (2, 'two');
SELECT * FROM x1, GRAPH_TABLE (myshop MATCH (c IS customers WHERE c.address = 'US' AND c.customer_id = x1.a)-[IS customer_orders]->(o IS orders) COLUMNS (c.name AS customer_name, c.customer_id AS cid));
SELECT pg_pgq2sql_info($$SELECT * FROM x1, GRAPH_TABLE (myshop MATCH (c IS customers WHERE c.address = 'US' AND c.customer_id = x1.a)-[IS customer_orders]->(o IS orders) COLUMNS (c.name AS customer_name, c.customer_id AS cid));$$);
 SELECT x1.a,
    x1.b,
    "graph_table".customer_name,
    "graph_table".cid
   FROM x1,
    LATERAL ( SELECT customers.name AS customer_name,
            customers.customer_id AS cid
           FROM customers,
            customer_orders,
            orders
          WHERE customers.address::text = 'US'::text AND customers.customer_id = x1.a AND customers.customer_id = customer_orders.customer_id AND orders.order_id = customer_orders.order_id) "graph_table";

DROP TABLE x1;

DROP SCHEMA graph_table_tests CASCADE;
DROP EXTENSION pg_pgq2sql;
