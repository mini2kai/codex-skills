"""SQL 只读安全检查器。

零外部依赖，可独立复用。适用于任何需要在执行前验证 SQL 是否只读的场景。

安全模型：
  1. 遮蔽所有字面值（单引号、双引号、dollar-quote）和注释（行注释、块注释）
  2. 对剩余裸 token 做关键字白名单/黑名单检查
  3. 拒绝多语句（分号分隔）

已知边界：
  - 不处理 E'...' 转义语法（PostgreSQL 扩展），但 E 后引号仍被正常遮蔽
  - 嵌套 dollar-quote 只处理一层
  - 如果 SQL 语法本身有 bug（未闭合引号），遮蔽结果不确定，可能误判为安全
  - 不替代数据库自身的权限控制，是应用层的前置防线
"""

from __future__ import annotations

import re

BANNED_TOKENS: set[str] = {
    "INSERT",
    "UPDATE",
    "DELETE",
    "TRUNCATE",
    "DROP",
    "ALTER",
    "CREATE",
    "GRANT",
    "REVOKE",
    "VACUUM",
    "CALL",
    "DO",
    "COPY",
    "MERGE",
    "REFRESH",
    "LOCK",
    "SETVAL",
    "NEXTVAL",
}

ALLOWED_START: set[str] = {"SELECT", "WITH", "SHOW", "EXPLAIN"}

MAX_TIMEOUT: int = 120
MAX_ROWS: int = 1000


def normalize_sql(sql: str) -> str:
    """去除首尾空白和末尾分号。"""
    return sql.strip().rstrip(";").strip()


def mask_literals_and_comments(sql: str) -> str:
    """将 SQL 中的字面值和注释替换为等长空格，保留裸 token 位置不变。

    处理的语法结构：
      - 单引号字符串 ('...')，含转义 ('')
      - 双引号标识符 ("...")，含转义 ("")
      - 行注释 (--)
      - 块注释 (/* ... */)
      - Dollar-quote ($tag$...$tag$ 或 $$...$$)
    """
    chars: list[str] = []
    i = 0
    in_single = False
    in_double = False
    in_line_comment = False
    in_block_comment = False
    dollar_tag: str | None = None

    while i < len(sql):
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < len(sql) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                chars.append("\n")
            else:
                chars.append(" ")
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                chars.extend("  ")
                in_block_comment = False
                i += 2
            else:
                chars.append(" ")
                i += 1
            continue

        if dollar_tag:
            if sql.startswith(dollar_tag, i):
                chars.extend(" " * len(dollar_tag))
                i += len(dollar_tag)
                dollar_tag = None
            else:
                chars.append(" ")
                i += 1
            continue

        if in_single:
            if ch == "'" and nxt == "'":
                chars.extend("  ")
                i += 2
            elif ch == "'":
                chars.append(" ")
                in_single = False
                i += 1
            else:
                chars.append(" ")
                i += 1
            continue

        if in_double:
            if ch == '"' and nxt == '"':
                chars.extend("  ")
                i += 2
            elif ch == '"':
                chars.append(" ")
                in_double = False
                i += 1
            else:
                chars.append(" ")
                i += 1
            continue

        if ch == "-" and nxt == "-":
            chars.extend("  ")
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            chars.extend("  ")
            in_block_comment = True
            i += 2
            continue
        if ch == "'":
            chars.append(" ")
            in_single = True
            i += 1
            continue
        if ch == '"':
            chars.append(" ")
            in_double = True
            i += 1
            continue
        if ch == "$":
            match = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[i:])
            if match:
                dollar_tag = match.group(0)
                chars.extend(" " * len(dollar_tag))
                i += len(dollar_tag)
                continue

        chars.append(ch)
        i += 1

    return "".join(chars)


def first_keyword(masked_sql: str) -> str | None:
    """从遮蔽后的 SQL 中提取第一个关键字。"""
    match = re.search(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", masked_sql)
    return match.group(1).upper() if match else None


def assert_read_only(sql: str, *, allow_explain_analyze: bool = False) -> str:
    """验证 SQL 是只读的。通过返回规范化后的 SQL，不通过抛出 ValueError。

    检查逻辑：
      1. 规范化（去空白、去尾分号）
      2. 遮蔽字面值和注释
      3. 拒绝多语句（遮蔽后仍有分号）
      4. 首关键字必须在 ALLOWED_START 白名单中
      5. 全文不得出现 BANNED_TOKENS 中的关键字
      6. EXPLAIN 默认不允许 ANALYZE（会实际执行查询）
    """
    normalized = normalize_sql(sql)
    if not normalized:
        raise ValueError("SQL 为空。")

    masked = mask_literals_and_comments(normalized)
    if ";" in masked:
        raise ValueError("不允许执行多条 SQL 语句。")

    start = first_keyword(masked)
    if start not in ALLOWED_START:
        raise ValueError(f"默认只允许只读 SQL。检测到的首个关键字：{start or '无'}。")

    upper = masked.upper()
    for token in sorted(BANNED_TOKENS):
        if re.search(rf"\b{re.escape(token)}\b", upper):
            raise ValueError(f"检测到风险关键字 '{token}'。本 skill 只能生成此类 SQL，不能直接执行。")

    if start == "EXPLAIN" and not allow_explain_analyze:
        if re.search(r"\bANALYZE\b", upper):
            raise ValueError("EXPLAIN ANALYZE 会实际执行查询，默认不允许。")

    return normalized


def limited_sql(sql: str, limit: int) -> str:
    """验证 SQL 只读性并对 SELECT/WITH 追加行数限制。"""
    limit = min(limit, MAX_ROWS)
    if limit < 1:
        raise ValueError(f"limit 必须在 1 到 {MAX_ROWS} 之间。")
    normalized = assert_read_only(sql)
    start = first_keyword(mask_literals_and_comments(normalized))
    if start in {"SELECT", "WITH"}:
        return f"SELECT * FROM (\n{normalized}\n) AS _limited LIMIT {int(limit)}"
    return normalized


def clamp_timeout(timeout: int) -> int:
    """将超时值限制在合理范围内。"""
    if timeout < 1:
        return 1
    return min(timeout, MAX_TIMEOUT)
