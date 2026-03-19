/* contrib/pg_pgq2sql/pg_pgq2sql--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_pgq2sql" to load this file. \quit

--
-- pg_pgq2sql(query text)
--
-- Parse and rewrite a SQL/PGQ query, then convert back to plain SQL.
-- The function takes a SQL/PGQ query string, parses it, runs through
-- the rewrite phase (which transforms GRAPH_TABLE into JOINs), and
-- returns the equivalent plain SQL statement.
--
CREATE FUNCTION pg_pgq2sql(query text)
RETURNS text
AS 'MODULE_PATHNAME', 'pg_pgq2sql'
LANGUAGE C STABLE STRICT;

COMMENT ON FUNCTION pg_pgq2sql(text) IS
'Parse and rewrite a SQL/PGQ query string, then convert back to plain SQL';

--
-- pg_pgq2sql_print(query text)
--
-- Same as pg_pgq2sql but prints the result to stdout instead of returning it.
-- Returns NULL for convenience.
--
CREATE FUNCTION pg_pgq2sql_print(query text)
RETURNS void
AS 'MODULE_PATHNAME', 'pg_pgq2sql_print'
LANGUAGE C STABLE STRICT;

COMMENT ON FUNCTION pg_pgq2sql_print(text) IS
'Parse and rewrite a SQL/PGQ query string, print the converted SQL to stdout';
