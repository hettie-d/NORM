drop schema if exists norm cascade;
create schema norm;
set search_path to norm;
\ir create_norm_gen_tables.sql;
\ir process_schema_pkg.sql
\ir ts_all.sql
\ir build_conditions_pkg.sql
\ir build_return_type_pkg.sql
\ir build_select_pkg.sql
\ir build_to_db.sql
\ir generate_select_by_id.sql
\ir generate_search_generic.sql
\ir generate_to_db_function.sql




