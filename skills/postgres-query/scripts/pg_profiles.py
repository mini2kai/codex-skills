"""列出 PostgreSQL 本地连接 profile，输出脱敏 JSON。"""

from __future__ import annotations

from pg_common import emit, get_profiles, load_connection_config


def main() -> None:
    config = load_connection_config(required=True)
    assert config is not None
    profiles = get_profiles(config)
    default_profile = config.get("defaultProfile")
    rows: list[dict[str, object]] = []
    for name in sorted(profiles.keys()):
        profile = profiles[name]
        if not isinstance(profile, dict):
            rows.append({"profile": name, "error": "profile 必须是 JSON 对象"})
            continue
        rows.append(
            {
                "profile": name,
                "description": profile.get("description", ""),
                "default": name == default_profile,
                "host": profile.get("host", ""),
                "port": profile.get("port", 5432),
                "dbname": profile.get("dbname") or profile.get("database", ""),
                "user": profile.get("user") or profile.get("username", ""),
                "password_source": "env" if profile.get("passwordEnv") else ("inline" if profile.get("password") else "none"),
                "sslmode": profile.get("sslmode", ""),
            }
        )
    emit({"ok": True, "operation": "连接配置列表", "defaultProfile": default_profile, "profiles": rows})


if __name__ == "__main__":
    main()
