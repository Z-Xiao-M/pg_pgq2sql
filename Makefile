# Makefile for pg_pgq2sql
MODULES = pg_pgq2sql

EXTENSION = pg_pgq2sql
DATA = pg_pgq2sql--1.0.sql
PGFILEDESC = "pg_pgq2sql - convert SQL/PGQ Query structure back to plain SQL"

OBJS = \
	$(WIN32RES) \
	pg_pgq2sql.o

REGRESS = simple_test \
		  graph_table_test \
		  union \
		  infromcl_test \
		  complex

ifdef USE_PGXS
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pg_pgq2sql
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
