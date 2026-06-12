"""执行受保护的 PostgreSQL 只读查询并输出 JSON。"""

from __future__ import annotations

import argparse
from pg_common import add_connection_args, audit, connect, emit, fetch_limited, limited_sql, redact, resolve_dsn
from sql_guard import MAX_ROWS


def main() -> None:
    parser = argparse.ArgumentParser(description="执行安全的 PostgreSQL 只读查询。")
    add_connection_args(parser)
    parser.add_argument("--sql", required=True, help="只读 SQL。仅允许 SELECT/WITH/SHOW/EXPLAIN。")
    parser.add_argument("--limit", type=int, default=100, help=f"SELECT/WITH 样例结果最大行数。默认：100，上限：{MAX_ROWS}。")
    args = parser.parse_args()

    if args.limit < 1 or args.limit > MAX_ROWS:
        emit({"ok": False, "error": "invalid_limit", "message": f"limit 必须在 1 到 {MAX_ROWS} 之间。"}, 2)

    try:
        sql = limited_sql(args.sql, args.limit)
    except ValueError as exc:
        audit("blocked", sql=args.sql, reason=str(exc))
        emit({"ok": False, "error": "unsafe_sql", "message": str(exc)}, 2)

    dsn = resolve_dsn(args)
    conn, driver = connect(dsn, args.timeout)
    try:
        columns, rows, truncated = fetch_limited(conn, sql, args.limit)
    except Exception as exc:
        audit("query_failed", connection=dsn, sql=args.sql, error=str(exc))
        emit({"ok": False, "error": "query_failed", "message": str(exc), "dsn": redact(dsn)}, 3)
    finally:
        conn.close()

    audit("query", connection=dsn, sql=args.sql, rows=len(rows))
    emit(
        {
            "ok": True,
            "operation": "只读查询",
            "driver": driver,
            "connection": redact(dsn),
            "columns": columns,
            "row_count": len(rows),
            "limit": args.limit,
            "truncated": truncated,
            "rows": rows,
        }
    )


if __name__ == "__main__":
    main()
