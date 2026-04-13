/*
 * pg_pgq2sql.c
 *
 * Convert SQL/PGQ query (after rewrite) back to plain SQL.
 *
 * Portions Copyright (c) 2026-2026, Halo Tech Co.,Ltd. All rights reserved.
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * Author: zengman <zengman@halodbtech.com>
 *
 * IDENTIFICATION
 *	  contrib/pg_pgq2sql/pg_pgq2sql.c
 */
#include "postgres.h"

#include "utils/builtins.h"
#include "parser/analyze.h"
#include "parser/parser.h"
#include "parser/parsetree.h"
#include "rewrite/rewriteHandler.h"
#include "utils/ruleutils.h"
#include "nodes/nodes.h"
#include "nodes/parsenodes.h"
#include "nodes/nodeFuncs.h"

PG_MODULE_MAGIC_EXT(
					.name = "pg_pgq2sql",
                    .version = PG_VERSION
);

static void adjust_inFromCl(Query *query);
static bool adjust_inFromCl_walker(Node *node, void *context);
static void adjust_inFromCl_jointree(Query *query);

/*
 * adjust_inFromCl
 *
 * Adjust the inFromCl field of RangeTblEntry objects within a rewritten query
 * so that pg_get_querydef() can produce correct FROM clauses.
 *
 * After GRAPH_TABLE rewrite, RTEs that participate in FROM clauses may have
 * inFromCl set incorrectly.  This function recursively traverses the entire
 * query tree and corrects the flag for any RTE that appears in a jointree
 * fromlist.
 */
static void
adjust_inFromCl(Query *query)
{
	if (!query)
		return;

	/* Process the top-level query's own jointree first. */
	adjust_inFromCl_jointree(query);

	/*
	 * Recursively walk the entire query tree (subqueries in rtable,
	 * setOperations, etc.) using the standard walker infrastructure.
	 * We don't need QTW_EXAMINE_RTES flags because we only act on Query
	 * nodes to fix their jointrees.
	 */
	query_tree_walker(query, adjust_inFromCl_walker, NULL, 0);
}

/*
 * adjust_inFromCl_walker
 *
 * Callback for query_tree_walker.  When we encounter a Query node, process
 * its jointree.  The walker infrastructure handles recursing into subqueries,
	 * set operations, and other child nodes automatically.
 */
static bool
adjust_inFromCl_walker(Node *node, void *context)
{
	if (node == NULL)
		return false;

	if (IsA(node, Query))
	{
		Query	   *query = (Query *) node;

		adjust_inFromCl_jointree(query);

		/* Continue walking into subqueries, set operations, etc. */
		return query_tree_walker(query, adjust_inFromCl_walker, context, 0);
	}

	return expression_tree_walker(node, adjust_inFromCl_walker, context);
}

/*
 * adjust_inFromCl_jointree
 *
 * For a single Query, scan its jointree fromlist and set inFromCl = true for
 * any RTE that appears there.  This mirrors what ruleutils.c's get_from_clause
 * does: it iterates jointree->fromlist and skips RTEs where inFromCl is false.
 * By ensuring all fromlist RTEs have inFromCl = true, we guarantee the
 * deparsed SQL contains the complete FROM clause.
 */
static void
adjust_inFromCl_jointree(Query *query)
{
	ListCell   *lc;

	if (!query->jointree || !query->jointree->fromlist)
		return;

	foreach(lc, query->jointree->fromlist)
	{
		Node	   *jtnode = (Node *) lfirst(lc);

		if (IsA(jtnode, RangeTblRef))
		{
			RangeTblEntry *rte = rt_fetch(((RangeTblRef *) jtnode)->rtindex,
										  query->rtable);

			if (!rte->inFromCl)
				rte->inFromCl = true;
		}
	}
}

PG_FUNCTION_INFO_V1(pg_pgq2sql);

/*
 * pg_pgq2sql(query text)
 *
 * Parse a SQL/PGQ query string, run it through the rewrite phase
 * (which transforms GRAPH_TABLE clauses into subqueries with JOINs),
 * then convert the resulting Query back to plain SQL text.
 */
Datum
pg_pgq2sql(PG_FUNCTION_ARGS)
{
    text       *query_text = PG_GETARG_TEXT_PP(0);
    char       *query_string;
    List       *parsetree_list;
    List       *querytree_list;
    Query       *query;
    Query       *new_query;
    char       *result;

    query_string = text_to_cstring(query_text);

    /* Step 1: Parse the query string */
    parsetree_list = raw_parser(query_string, RAW_PARSE_DEFAULT);
    if (list_length(parsetree_list) != 1)
		elog(ERROR, "expect exactly 1 SQL statement, found %d", list_length(parsetree_list));

    /* Step 2: Analyze the parse tree */
    query = parse_analyze_fixedparams(linitial(parsetree_list),
                                             query_string,
                                             NULL, 0, NULL);

	if (!IsA(query, Query) || query->utilityStmt != NULL ||
		query->commandType != CMD_SELECT)
		elog(ERROR, "unexpected parse analysis result");

    /* Step 3: Rewrite the query */
    querytree_list = QueryRewrite(query);
    if (list_length(querytree_list) != 1)
        elog(ERROR, "unexpected rewrite result, contains %d queries",
			     list_length(querytree_list));

    new_query = linitial(querytree_list);

    /* Step 4: Adjust inFromCl for correct FROM clause deparsing */
    adjust_inFromCl(new_query);

    /* Step 5: Convert the rewritten Query back to SQL string */
    result = pg_get_querydef(new_query, true);
    pfree(query_string);
    PG_RETURN_TEXT_P(cstring_to_text(result));
}

PG_FUNCTION_INFO_V1(pg_pgq2sql_info);

/*
 * pg_pgq2sql_info(query text)
 *
 * Same as pg_pgq2sql but prints the result to stdout (via elog INFO)
 * and returns NULL.
 */
Datum
pg_pgq2sql_info(PG_FUNCTION_ARGS)
{
    text       *query_text = PG_GETARG_TEXT_PP(0);
    char       *query_string;
    List       *parsetree_list;
    List       *querytree_list;
    Query       *query;
    Query       *new_query;
    char       *result;

    query_string = text_to_cstring(query_text);

    /* Step 1: Parse the query string */
    parsetree_list = raw_parser(query_string, RAW_PARSE_DEFAULT);
    if (list_length(parsetree_list) != 1)
        elog(ERROR, "expect exactly 1 SQL statement, found %d", list_length(parsetree_list));

    /* Step 2: Analyze the parse tree */
    query = parse_analyze_fixedparams(linitial(parsetree_list),
                                             query_string,
                                             NULL, 0, NULL);
    if (!IsA(query, Query) || query->utilityStmt != NULL ||
        query->commandType != CMD_SELECT)
        elog(ERROR, "unexpected parse analysis result");

    /* Step 3: Rewrite the query */
    querytree_list = QueryRewrite(query);
    if (list_length(querytree_list) != 1)
        elog(ERROR, "unexpected rewrite result, contains %d queries",
             list_length(querytree_list));

    new_query = linitial(querytree_list);

    /* Step 4: Adjust inFromCl for correct FROM clause deparsing */
    adjust_inFromCl(new_query);

    /* Step 5: Convert the rewritten Query back to SQL string and print it */
    result = pg_get_querydef(new_query, true);

    pfree(query_string);

    /* Print result to server log / stdout */
    elog(INFO, "\n%s;\n", result);

    PG_RETURN_NULL();
}
