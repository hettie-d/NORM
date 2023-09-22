drop schema if exists norm_gen cascade;
create schema norm_gen;
set search_path to norm_gen;
\ir create_norm_gen_tables.sql;
\ir process_schema_pkg.sql
\ir ts_all.sql
\ir build_conditions_pkg.sql
\ir build_return_type_pkg.sql
\ir build_select_pkg.sql
\ir build_to_db.sql
\ir create_generated_types.sql
\ir generate_from_db.sql
\ir generate_select_by_ids.sql
\ir generate_to_db_function.sql
