"""执行不带 ANALYZE 的安全 PostgreSQL EXPLAIN，并输出 JSON。"""

from __future__ import annotations

import argparse
import re
from pg_common import add_connection_args, assert_read_only, connect, emit, fetch_all, mask_literals_and_comments, redact, resolve_dsn


def explain_sql(sql: str) -> str:
    normalized = assert_read_only(sql, allow_explain_analyze=False)
    masked = mask_literals_and_comments(normalized).lstrip().upper()
    if masked.startswith("EXPLAIN"):
        return normalized
    return "EXPLAIN " + normalized


def classify_plan(lines: list[str]) -> list[str]:
    joined = "\n".join(lines)
    findings: list[str] = []
    if re.search(r"Seq Scan", joined):
        findings.append("查询计划包含顺序扫描；请结合表数据量、过滤条件和索引策略判断是否合理。")
    if re.search(r"Nested Loop", joined):
        findings.append("查询计划包含 Nested Loop；如果输入数据量较大，请检查行数估算和 join 索引。")
    if re.search(r"Sort", joined):
        findings.append("查询计划包含显式排序；如果较慢，请检查 ORDER BY、work_mem 和索引顺序。")
    if re.search(r"Hash Join|HashAggregate", joined):
        findings.append("查询计划包含 hash 操作；如果实际执行较慢，请检查内存、行数估算和是否发生落盘。")
    return findings


def main() -> None:
    parser = argparse.ArgumentParser(description="执行不带 ANALYZE 的安全 EXPLAIN。")
    add_connection_args(parser)
    parser.add_argument("--sql", required=True, help="要分析的只读 SQL。EXPLAIN ANALYZE 会被拒绝。")
    args = parser.parse_args()

    try:
        sql = explain_sql(args.sql)
    except ValueError as exc:
        emit({"ok": False, "error": "unsafe_sql", "message": str(exc)}, 2)

    dsn = resolve_dsn(args)
    conn, driver = connect(dsn, args.timeout)
    try:
        _, rows = fetch_all(conn, sql)
        plan_lines = [str(row[0]) for row in rows]
    except Exception as exc:
        emit({"ok": False, "error": "explain_failed", "message": str(exc), "dsn": redact(dsn)}, 3)
    finally:
        conn.close()

    emit(
        {
            "ok": True,
            "operation": "查询计划",
            "driver": driver,
            "connection": redact(dsn),
            "plan": plan_lines,
            "findings": classify_plan(plan_lines),
        }
    )


if __name__ == "__main__":
    main()
