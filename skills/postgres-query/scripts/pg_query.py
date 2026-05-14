"""执行受保护的 PostgreSQL 只读查询并输出 JSON。"""

from __future__ import annotations

import argparse
from pg_common import add_connection_args, connect, emit, fetch_all, limited_sql, redact, resolve_dsn


def main() -> None:
    parser = argparse.ArgumentParser(description="执行安全的 PostgreSQL 只读查询。")
    add_connection_args(parser)
    parser.add_argument("--sql", required=True, help="只读 SQL。仅允许 SELECT/WITH/SHOW/EXPLAIN。")
    parser.add_argument("--limit", type=int, default=100, help="SELECT/WITH 样例结果最大行数。默认：100。")
    args = parser.parse_args()

    if args.limit < 1 or args.limit > 10000:
        emit({"ok": False, "error": "invalid_limit", "message": "limit 必须在 1 到 10000 之间。"}, 2)

    try:
        sql = limited_sql(args.sql, args.limit)
    except ValueError as exc:
        emit({"ok": False, "error": "unsafe_sql", "message": str(exc)}, 2)

    dsn = resolve_dsn(args)
    conn, driver = connect(dsn, args.timeout)
    try:
        columns, rows = fetch_all(conn, sql)
    except Exception as exc:
        emit({"ok": False, "error": "query_failed", "message": str(exc), "dsn": redact(dsn)}, 3)
    finally:
        conn.close()

    emit(
        {
            "ok": True,
            "operation": "只读查询",
            "driver": driver,
            "connection": redact(dsn),
            "columns": columns,
            "row_count": len(rows),
            "rows": rows,
        }
    )


if __name__ == "__main__":
    main()
