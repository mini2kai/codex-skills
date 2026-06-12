"""sql_guard.py 的安全检查测试。

运行方式：
    cd skills/postgres-query/scripts
    python -m pytest test_sql_safety.py -v
    # 或不依赖 pytest：
    python test_sql_safety.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sql_guard import assert_read_only, limited_sql, mask_literals_and_comments


# === 应该通过的只读 SQL ===

SAFE_CASES = [
    # 基本 SELECT
    "SELECT * FROM users",
    "SELECT id, name FROM users WHERE id = 1",
    "select count(*) from orders",
    # WITH (CTE)
    "WITH cte AS (SELECT 1) SELECT * FROM cte",
    "WITH RECURSIVE tree AS (SELECT id, parent_id FROM nodes WHERE id = 1 UNION ALL SELECT n.id, n.parent_id FROM nodes n JOIN tree t ON n.parent_id = t.id) SELECT * FROM tree",
    # SHOW
    "SHOW server_version",
    "SHOW ALL",
    # EXPLAIN（不带 ANALYZE）
    "EXPLAIN SELECT * FROM users WHERE id = 1",
    "EXPLAIN (FORMAT JSON) SELECT 1",
    # 关键字出现在字符串字面值中——不应被误判
    "SELECT 'DELETE FROM users' AS label",
    "SELECT * FROM t WHERE name = 'DROP TABLE'",
    "SELECT * FROM t WHERE col = 'INSERT INTO foo VALUES (1)'",
    # 关键字出现在注释中——不应被误判
    "SELECT 1 -- DELETE FROM users",
    "SELECT 1 /* DROP TABLE users */",
    # 关键字出现在双引号标识符中——不应被误判
    'SELECT "DELETE" FROM t',
    'SELECT * FROM "CREATE" WHERE id = 1',
    # 关键字出现在 dollar-quote 中——不应被误判
    "SELECT $$ DELETE FROM users $$ AS code",
    "SELECT $tag$ UPDATE users SET name = 'x' $tag$ AS code",
    # 带单引号转义
    "SELECT * FROM users WHERE name = 'O''Brien'",
    # 复杂但安全
    "SELECT u.id, o.total FROM users u JOIN orders o ON u.id = o.user_id WHERE o.total > 100",
    "WITH monthly AS (SELECT date_trunc('month', created_at) AS m, count(*) FROM orders GROUP BY 1) SELECT * FROM monthly",
]

# === 应该被拦截的危险 SQL ===

DANGEROUS_CASES = [
    # 直接写操作
    ("DELETE FROM users", "DELETE"),
    ("INSERT INTO users (name) VALUES ('test')", "INSERT"),
    ("UPDATE users SET name = 'x' WHERE id = 1", "UPDATE"),
    ("TRUNCATE TABLE users", "TRUNCATE"),
    ("DROP TABLE users", "DROP"),
    ("ALTER TABLE users ADD COLUMN age INT", "ALTER"),
    ("CREATE TABLE t (id int)", "CREATE"),
    ("GRANT SELECT ON users TO readonly", "GRANT"),
    ("REVOKE ALL ON users FROM public", "REVOKE"),
    ("VACUUM users", "VACUUM"),
    ("COPY users TO '/tmp/out.csv'", "COPY"),
    ("DO $$ BEGIN RAISE NOTICE 'hi'; END $$", "DO"),
    ("CALL my_procedure()", "CALL"),
    ("MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET x = 1", "MERGE"),
    ("REFRESH MATERIALIZED VIEW my_view", "REFRESH"),
    # 多语句注入
    ("SELECT 1; DROP TABLE users", None),
    ("SELECT 1;DELETE FROM users", None),
    # EXPLAIN ANALYZE（实际执行查询）
    ("EXPLAIN ANALYZE SELECT * FROM users", "ANALYZE"),
    ("EXPLAIN (ANALYZE true) SELECT 1", "ANALYZE"),
    # 危险关键字不在字符串中
    ("SELECT * FROM users WHERE 1=1 UNION ALL DELETE FROM users", "DELETE"),
    # LOCK
    ("LOCK TABLE users IN EXCLUSIVE MODE", "LOCK"),
    # setval / nextval
    ("SELECT setval('users_id_seq', 1000)", "SETVAL"),
    ("SELECT nextval('users_id_seq')", "NEXTVAL"),
]

# === 空 SQL 和边界情况 ===

EDGE_CASES_REJECTED = [
    "",
    "   ",
    "   ;  ",
]


def test_safe_cases():
    """所有安全 SQL 应该通过检查。"""
    failures = []
    for sql in SAFE_CASES:
        try:
            result = assert_read_only(sql)
            assert result  # 返回非空字符串
        except ValueError as e:
            failures.append(f"FAIL (should pass): {sql!r}\n  Error: {e}")
    return failures


def test_dangerous_cases():
    """所有危险 SQL 应该被拦截。"""
    failures = []
    for item in DANGEROUS_CASES:
        if isinstance(item, tuple):
            sql, expected_keyword = item
        else:
            sql, expected_keyword = item, None
        try:
            assert_read_only(sql)
            failures.append(f"FAIL (should block): {sql!r}")
        except ValueError as e:
            if expected_keyword and expected_keyword not in str(e):
                failures.append(f"FAIL (blocked but wrong reason): {sql!r}\n  Expected '{expected_keyword}' in: {e}")
    return failures


def test_edge_cases():
    """空 SQL 和纯空白应该被拒绝。"""
    failures = []
    for sql in EDGE_CASES_REJECTED:
        try:
            assert_read_only(sql)
            failures.append(f"FAIL (should reject empty): {sql!r}")
        except ValueError:
            pass
    return failures


def test_limited_sql():
    """limited_sql 应验证只读和 limit 参数，但不改写原 SQL。"""
    failures = []

    result = limited_sql("SELECT * FROM users", 50)
    if result != "SELECT * FROM users":
        failures.append(f"FAIL: SELECT should not be wrapped: {result}")

    result = limited_sql("SELECT * FROM users", 99999)
    if result != "SELECT * FROM users":
        failures.append(f"FAIL: SELECT should remain unchanged when limit is clamped: {result}")

    result = limited_sql("SHOW server_version", 50)
    if "LIMIT" in result:
        failures.append(f"FAIL: SHOW should remain unchanged: {result}")

    try:
        limited_sql("DELETE FROM users", 10)
        failures.append("FAIL: limited_sql should reject DELETE")
    except ValueError:
        pass

    return failures


def test_mask_preserves_length():
    """遮蔽后的字符串长度应与原始相同。"""
    failures = []
    cases = [
        "SELECT 'hello world' FROM t",
        "SELECT $$ multi\nline $$ FROM t",
        "SELECT 1 -- comment\nSELECT 2",
        "SELECT /* block */ 3",
        'SELECT "identifier" FROM t',
    ]
    for sql in cases:
        masked = mask_literals_and_comments(sql)
        if len(masked) != len(sql):
            failures.append(f"FAIL length mismatch: {sql!r} -> {masked!r}")
    return failures


def main():
    all_failures = []
    tests = [
        ("safe_cases", test_safe_cases),
        ("dangerous_cases", test_dangerous_cases),
        ("edge_cases", test_edge_cases),
        ("limited_sql", test_limited_sql),
        ("mask_preserves_length", test_mask_preserves_length),
    ]

    for name, test_fn in tests:
        failures = test_fn()
        if failures:
            print(f"\n{'='*60}")
            print(f"FAILED: {name}")
            print(f"{'='*60}")
            for f in failures:
                print(f"  {f}")
            all_failures.extend(failures)
        else:
            print(f"  PASSED: {name}")

    print(f"\n{'='*60}")
    if all_failures:
        print(f"TOTAL FAILURES: {len(all_failures)}")
        raise SystemExit(1)
    else:
        print("ALL TESTS PASSED")
        raise SystemExit(0)


if __name__ == "__main__":
    main()
