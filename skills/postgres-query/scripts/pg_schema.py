"""查看 PostgreSQL schema、表、字段、键和索引。"""

from __future__ import annotations

import argparse
from pg_common import add_connection_args, connect, emit, fetch_all, redact, resolve_dsn


def split_table(value: str, default_schema: str) -> tuple[str, str]:
    if "." in value:
        schema, table = value.split(".", 1)
        return schema.strip('"'), table.strip('"')
    return default_schema, value.strip('"')


def main() -> None:
    parser = argparse.ArgumentParser(description="查看 PostgreSQL 结构元数据。")
    add_connection_args(parser)
    parser.add_argument("--schema", default="public", help="schema 名称。默认：public。")
    parser.add_argument("--list-schemas", action="store_true", help="列出可见的非系统 schema。")
    parser.add_argument("--list-tables", action="store_true", help="列出 --schema 下的表。")
    parser.add_argument("--table", help="查看表字段、键和索引；可传 schema.table。")
    args = parser.parse_args()

    if not (args.list_schemas or args.list_tables or args.table):
        emit({"ok": False, "error": "missing_action", "message": "请使用 --list-schemas、--list-tables 或 --table 指定操作。"}, 2)

    dsn = resolve_dsn(args)
    conn, driver = connect(dsn, args.timeout)
    result: dict[str, object] = {
        "ok": True,
        "operation": "结构查看",
        "driver": driver,
        "connection": redact(dsn),
    }

    try:
        if args.list_schemas:
            columns, rows = fetch_all(
                conn,
                """
                SELECT schema_name
                FROM information_schema.schemata
                WHERE substring(schema_name from 1 for 3) <> 'pg_'
                  AND schema_name <> 'information_schema'
                ORDER BY schema_name
                """,
            )
            result["schemas"] = {"columns": columns, "rows": rows}

        if args.list_tables:
            columns, rows = fetch_all(
                conn,
                """
                SELECT table_schema, table_name, table_type
                FROM information_schema.tables
                WHERE table_schema = %s
                ORDER BY table_name
                """,
                [args.schema],
            )
            result["tables"] = {"columns": columns, "rows": rows}

        if args.table:
            schema, table = split_table(args.table, args.schema)
            result["table"] = f"{schema}.{table}"

            columns, rows = fetch_all(
                conn,
                """
                SELECT column_name, data_type, is_nullable, column_default, ordinal_position
                FROM information_schema.columns
                WHERE table_schema = %s AND table_name = %s
                ORDER BY ordinal_position
                """,
                [schema, table],
            )
            result["columns"] = {"columns": columns, "rows": rows}

            columns, rows = fetch_all(
                conn,
                """
                SELECT tc.constraint_type, kcu.column_name, ccu.table_schema AS foreign_table_schema,
                       ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON tc.constraint_name = kcu.constraint_name
                 AND tc.table_schema = kcu.table_schema
                LEFT JOIN information_schema.constraint_column_usage ccu
                  ON ccu.constraint_name = tc.constraint_name
                 AND ccu.table_schema = tc.table_schema
                WHERE tc.table_schema = %s AND tc.table_name = %s
                ORDER BY tc.constraint_type, kcu.ordinal_position
                """,
                [schema, table],
            )
            result["constraints"] = {"columns": columns, "rows": rows}

            columns, rows = fetch_all(
                conn,
                """
                SELECT schemaname, tablename, indexname, indexdef
                FROM pg_indexes
                WHERE schemaname = %s AND tablename = %s
                ORDER BY indexname
                """,
                [schema, table],
            )
            result["indexes"] = {"columns": columns, "rows": rows}
    except Exception as exc:
        emit({"ok": False, "error": "schema_query_failed", "message": str(exc), "dsn": redact(dsn)}, 3)
    finally:
        conn.close()

    emit(result)


if __name__ == "__main__":
    main()
