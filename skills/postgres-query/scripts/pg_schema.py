"""查看 PostgreSQL schema 结构信息。

接收 --sql 参数执行任意只读元数据查询，或使用便捷参数快速列出 schema/表/表详情。
具体查什么由调用方（AI 或用户）决定，本脚本只保证只读安全。
"""

from __future__ import annotations

import argparse
from pg_common import add_connection_args, audit, connect, emit, fetch_all, redact, resolve_dsn
from sql_guard import assert_read_only


def main() -> None:
    parser = argparse.ArgumentParser(description="查看 PostgreSQL 结构元数据（只读）。")
    add_connection_args(parser)
    parser.add_argument("--sql", help="自定义只读元数据查询 SQL。")
    parser.add_argument("--schema", default="public", help="目标 schema，配合 --list-tables 使用。")
    parser.add_argument("--list-schemas", action="store_true", help="列出非系统 schema。")
    parser.add_argument("--list-tables", action="store_true", help="列出 --schema 下的表。")
    parser.add_argument("--table", help="查看表字段、约束和索引。支持 schema.table 格式。")
    args = parser.parse_args()

    if not (args.list_schemas or args.list_tables or args.table or args.sql):
        emit({"ok": False, "error": "missing_action", "message": "请使用 --sql、--list-schemas、--list-tables 或 --table。"}, 2)

    dsn = resolve_dsn(args)
    conn, driver = connect(dsn, args.timeout)
    result: dict[str, object] = {
        "ok": True,
        "operation": "结构查看",
        "driver": driver,
        "connection": redact(dsn),
    }

    try:
        if args.sql:
            try:
                safe_sql = assert_read_only(args.sql)
            except ValueError as exc:
                audit("blocked", sql=args.sql, reason=str(exc))
                emit({"ok": False, "error": "unsafe_sql", "message": str(exc)}, 2)
            columns, rows = fetch_all(conn, safe_sql)
            result["custom_query"] = {"columns": columns, "rows": rows}
            audit("schema_query", connection=dsn, sql=args.sql, rows=len(rows))

        if args.list_schemas:
            columns, rows = fetch_all(
                conn,
                "SELECT schema_name FROM information_schema.schemata "
                "WHERE schema_name NOT LIKE 'pg_%' AND schema_name <> 'information_schema' "
                "ORDER BY schema_name",
            )
            result["schemas"] = {"columns": columns, "rows": rows}

        if args.list_tables:
            columns, rows = fetch_all(
                conn,
                "SELECT table_schema, table_name, table_type "
                "FROM information_schema.tables WHERE table_schema = %s ORDER BY table_name",
                [args.schema],
            )
            result["tables"] = {"columns": columns, "rows": rows}

        if args.table:
            schema, table = (args.table.split(".", 1) + [None])[:2]
            if table is None:
                schema, table = args.schema, schema
            schema = schema.strip('"')
            table = table.strip('"')
            result["table"] = f"{schema}.{table}"

            columns, rows = fetch_all(
                conn,
                "SELECT column_name, data_type, is_nullable, column_default "
                "FROM information_schema.columns "
                "WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
                [schema, table],
            )
            result["columns"] = {"columns": columns, "rows": rows}

            columns, rows = fetch_all(
                conn,
                "SELECT indexname, indexdef FROM pg_indexes "
                "WHERE schemaname = %s AND tablename = %s ORDER BY indexname",
                [schema, table],
            )
            result["indexes"] = {"columns": columns, "rows": rows}

    except Exception as exc:
        audit("schema_query_failed", connection=dsn, error=str(exc))
        emit({"ok": False, "error": "schema_query_failed", "message": str(exc), "dsn": redact(dsn)}, 3)
    finally:
        conn.close()

    audit("schema", connection=dsn)
    emit(result)


if __name__ == "__main__":
    main()
