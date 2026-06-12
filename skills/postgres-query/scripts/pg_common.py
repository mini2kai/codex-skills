"""PostgreSQL 查询 skill 的共享工具：连接管理、输出格式和审计日志。"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from sql_guard import (
    ALLOWED_START,
    BANNED_TOKENS,
    MAX_ROWS,
    MAX_TIMEOUT,
    assert_read_only,
    clamp_timeout,
    first_keyword,
    limited_sql,
    mask_literals_and_comments,
    normalize_sql,
)

CONNECTION_CONFIG = Path(__file__).resolve().parent / "connections.local.json"
AUDIT_LOG = Path(__file__).resolve().parent / "audit.local.jsonl"


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, default=str, indent=2))
    raise SystemExit(exit_code)


def redact(value: str | None) -> str | None:
    if not value:
        return value
    value = re.sub(r"(postgres(?:ql)?://[^:/@]+:)[^@]+(@)", r"\1***\2", value, flags=re.I)
    value = re.sub(r"(password=)(?:'[^']*'|[^\s]+)", r"\1***", value, flags=re.I)
    return value


def audit(action: str, *, connection: str | None = None, sql: str | None = None,
          rows: int | None = None, error: str | None = None, reason: str | None = None) -> None:
    """追加一条审计记录到本地 jsonl 文件。静默失败，不影响主流程。"""
    try:
        entry: dict[str, Any] = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "action": action,
        }
        if connection:
            entry["connection"] = redact(connection)
        if sql:
            entry["sql_hash"] = hashlib.sha256(sql.encode()).hexdigest()[:12]
            entry["sql_preview"] = sql[:80] + ("..." if len(sql) > 80 else "")
        if rows is not None:
            entry["rows"] = rows
        if error:
            entry["error"] = error
        if reason:
            entry["reason"] = reason
        with AUDIT_LOG.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


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

    timeout = clamp_timeout(timeout)

    try:
        import psycopg  # type: ignore

        conn = psycopg.connect(dsn, connect_timeout=timeout)
        conn.execute(f"SET statement_timeout = {int(timeout) * 1000}")
        audit("connect", connection=dsn)
        return conn, "psycopg"
    except ModuleNotFoundError:
        pass
    except Exception as exc:
        audit("connect_failed", connection=dsn, error=str(exc))
        emit({"ok": False, "error": "connection_failed", "message": str(exc), "dsn": redact(dsn)}, 3)

    try:
        import psycopg2  # type: ignore

        conn = psycopg2.connect(dsn, connect_timeout=timeout)
        cur = conn.cursor()
        cur.execute(f"SET statement_timeout = {int(timeout) * 1000}")
        cur.close()
        audit("connect", connection=dsn)
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
    except Exception as exc:
        audit("connect_failed", connection=dsn, error=str(exc))
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


def fetch_limited(conn: Any, sql: str, limit: int, params: Iterable[Any] | None = None) -> tuple[list[str], list[list[Any]], bool]:
    cur = conn.cursor()
    try:
        cur.execute(sql, tuple(params or ()))
        columns = [desc[0] for desc in (cur.description or [])]
        if not columns:
            return columns, [], False
        raw_rows = cur.fetchmany(limit + 1)
        truncated = len(raw_rows) > limit
        rows = [list(row) for row in raw_rows[:limit]]
        return columns, rows, truncated
    finally:
        cur.close()
