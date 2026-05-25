"""PostgreSQL 查询 skill 的共享工具。"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Iterable

BANNED_TOKENS = {
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

ALLOWED_START = {"SELECT", "WITH", "SHOW", "EXPLAIN"}

CONNECTION_CONFIG = Path(__file__).resolve().parent / "connections.local.json"


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, default=str, indent=2))
    raise SystemExit(exit_code)


def redact(value: str | None) -> str | None:
    if not value:
        return value
    value = re.sub(r"(postgres(?:ql)?://[^:/@]+:)[^@]+(@)", r"\1***\2", value, flags=re.I)
    value = re.sub(r"(password=)(?:'[^']*'|[^\s]+)", r"\1***", value, flags=re.I)
    return value


def quote_conn_value(value: Any) -> str:
    text = str(value)
    escaped = text.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def load_connection_config(required: bool = False) -> dict[str, Any] | None:
    if not CONNECTION_CONFIG.exists():
        if required:
            emit(
                {
                    "ok": False,
                    "error": "config_missing",
                    "message": "缺少 PostgreSQL 本地连接配置：scripts/connections.local.json。",
                    "next_action": "请在当前 skill 的 scripts/connections.local.json 中配置 profiles；真实密码不要提交到仓库。",
                },
                2,
            )
        return None
    try:
        with CONNECTION_CONFIG.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        emit(
            {
                "ok": False,
                "error": "config_invalid",
                "message": str(exc),
                "next_action": "请修正 scripts/connections.local.json。该文件必须是标准 JSON。",
            },
            2,
        )
    if not isinstance(data, dict):
        emit({"ok": False, "error": "config_invalid", "message": "connections.local.json 顶层必须是 JSON 对象。"}, 2)
    return data


def get_profiles(config: dict[str, Any]) -> dict[str, Any]:
    profiles = config.get("profiles")
    if not isinstance(profiles, dict):
        emit({"ok": False, "error": "config_invalid", "message": "connections.local.json 必须配置 profiles 对象。"}, 2)
    return profiles


def build_profile_dsn(profile: dict[str, Any], profile_name: str) -> str:
    if profile.get("dsn"):
        return str(profile["dsn"])

    password = profile.get("password")
    password_env = profile.get("passwordEnv")
    if password_env:
        password = os.environ.get(str(password_env))
        if password is None:
            emit(
                {
                    "ok": False,
                    "error": "password_env_missing",
                    "profile": profile_name,
                    "message": f"Profile {profile_name} 使用 passwordEnv={password_env}，但当前环境变量未设置。",
                },
                2,
            )

    parts = {
        "host": profile.get("host"),
        "port": profile.get("port", 5432),
        "dbname": profile.get("dbname") or profile.get("database"),
        "user": profile.get("user") or profile.get("username"),
        "password": password,
        "sslmode": profile.get("sslmode"),
    }
    missing = [key for key in ("host", "dbname", "user") if not parts.get(key)]
    if missing:
        emit(
            {
                "ok": False,
                "error": "config_invalid",
                "profile": profile_name,
                "message": "Profile 缺少必填字段：" + ", ".join(missing),
            },
            2,
        )
    return " ".join(f"{key}={quote_conn_value(value)}" for key, value in parts.items() if value is not None and value != "")


def resolve_profile_dsn(profile_name: str | None) -> str | None:
    config = load_connection_config(required=bool(profile_name))
    if not config:
        return None
    profiles = get_profiles(config)
    selected = profile_name or config.get("defaultProfile")
    if not selected:
        return None
    selected = str(selected)
    profile = profiles.get(selected)
    if not isinstance(profile, dict):
        emit(
            {
                "ok": False,
                "error": "profile_not_found",
                "profile": selected,
                "message": "本地连接配置中没有该 profile。",
                "available_profiles": sorted(profiles.keys()),
            },
            2,
        )
    return build_profile_dsn(profile, selected)


def resolve_dsn(args: argparse.Namespace) -> str | None:
    if getattr(args, "dsn", None):
        return args.dsn
    if getattr(args, "profile", None):
        return resolve_profile_dsn(args.profile)
    if os.environ.get("POSTGRES_DSN"):
        return os.environ["POSTGRES_DSN"]
    required = ["PGHOST", "PGDATABASE", "PGUSER"]
    if all(os.environ.get(k) for k in required):
        parts = {
            "host": os.environ.get("PGHOST"),
            "port": os.environ.get("PGPORT", "5432"),
            "dbname": os.environ.get("PGDATABASE"),
            "user": os.environ.get("PGUSER"),
            "password": os.environ.get("PGPASSWORD"),
            "sslmode": os.environ.get("PGSSLMODE"),
        }
        return " ".join(f"{key}={value}" for key, value in parts.items() if value)
    return resolve_profile_dsn(None)


def add_connection_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--dsn", help="临时 PostgreSQL DSN。为减少 shell 历史暴露，重复使用时优先放到环境变量。")
    parser.add_argument("--profile", help="读取 scripts/connections.local.json 中的连接别名。")
    parser.add_argument("--timeout", type=int, default=30, help="语句超时时间，单位秒。默认：30。")


def normalize_sql(sql: str) -> str:
    return sql.strip().rstrip(";").strip()


def mask_literals_and_comments(sql: str) -> str:
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
    match = re.search(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", masked_sql)
    return match.group(1).upper() if match else None


def assert_read_only(sql: str, allow_explain_analyze: bool = False) -> str:
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
    normalized = assert_read_only(sql)
    start = first_keyword(mask_literals_and_comments(normalized))
    if start in {"SELECT", "WITH"}:
        return f"SELECT * FROM (\n{normalized}\n) AS codex_limited_query LIMIT {int(limit)}"
    return normalized


def connect(dsn: str | None, timeout: int):
    if not dsn:
        emit(
            {
                "ok": False,
                "error": "missing_connection",
                "message": "未找到 PostgreSQL 连接信息。请向用户索取临时 DSN，或 host/port/database/user/password。",
                "accepted_inputs": ["--dsn", "POSTGRES_DSN", "PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD"],
            },
            2,
        )

    try:
        import psycopg  # type: ignore

        conn = psycopg.connect(dsn, connect_timeout=timeout)
        conn.execute(f"SET statement_timeout = {int(timeout) * 1000}")
        return conn, "psycopg"
    except ModuleNotFoundError:
        pass
    except Exception as exc:  # pragma: no cover - environment dependent
        emit({"ok": False, "error": "connection_failed", "message": str(exc), "dsn": redact(dsn)}, 3)

    try:
        import psycopg2  # type: ignore

        conn = psycopg2.connect(dsn, connect_timeout=timeout)
        cur = conn.cursor()
        cur.execute(f"SET statement_timeout = {int(timeout) * 1000}")
        cur.close()
        return conn, "psycopg2"
    except ModuleNotFoundError:
        emit(
            {
                "ok": False,
                "error": "missing_driver",
                "message": "本机缺少 PostgreSQL Python 驱动。请安装 psycopg 或 psycopg2 后再使用脚本连接数据库。",
                "next_action": "读取 references/driver_install.md，用中文引导用户确认后安装推荐驱动。",
                "install_commands": ["python -m pip install \"psycopg[binary]\"", "python -m pip install psycopg2-binary"],
            },
            4,
        )
    except Exception as exc:  # pragma: no cover - environment dependent
        emit({"ok": False, "error": "connection_failed", "message": str(exc), "dsn": redact(dsn)}, 3)


def fetch_all(conn: Any, sql: str, params: Iterable[Any] | None = None) -> tuple[list[str], list[list[Any]]]:
    cur = conn.cursor()
    try:
        cur.execute(sql, tuple(params or ()))
        columns = [desc[0] for desc in (cur.description or [])]
        rows = [list(row) for row in cur.fetchall()] if columns else []
        return columns, rows
    finally:
        cur.close()
