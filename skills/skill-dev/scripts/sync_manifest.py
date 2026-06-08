"""同步 m2k-skills 仓库 manifest.json 中的 skill 信息。"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(exit_code)


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def require_semver(value: str) -> str:
    if not SEMVER_RE.match(value):
        emit({"ok": False, "error": "invalid_version", "message": f"版本号必须是 x.y.z 格式：{value}"}, 2)
    return value


def bump_version(value: str, level: str) -> str:
    require_semver(value)
    major, minor, patch = [int(part) for part in value.split(".")]
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def main() -> None:
    parser = argparse.ArgumentParser(description="同步 manifest.json 中的 skill 信息。")
    parser.add_argument("--repo-root", default=".", help="仓库根目录，默认当前目录。")
    parser.add_argument("--skill", required=True, help="skill 名称。")
    parser.add_argument("--description", required=True, help="中文说明。")
    parser.add_argument("--tags", default="", help="逗号分隔 tags。")
    parser.add_argument("--requires", default="", help="逗号分隔依赖。")
    parser.add_argument("--version", help="显式设置 skill 版本，格式 x.y.z。")
    parser.add_argument("--bump", choices=["patch", "minor", "major"], help="基于 manifest 现有版本自动递增。")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    manifest_path = repo_root / "manifest.json"
    skill_dir = repo_root / "skills" / args.skill

    if not skill_dir.is_dir():
        emit({"ok": False, "error": "missing_skill_dir", "message": f"未找到 skill 目录：{skill_dir}"}, 1)
    if not manifest_path.is_file():
        emit({"ok": False, "error": "missing_manifest", "message": f"未找到 manifest.json：{manifest_path}"}, 1)

    data: dict[str, Any] = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    data.setdefault("skills", {})
    previous = data["skills"].get(args.skill) if isinstance(data["skills"].get(args.skill), dict) else {}
    current_version = str(previous.get("version") or "0.1.0")
    if args.version and args.bump:
        emit({"ok": False, "error": "version_conflict", "message": "--version 和 --bump 只能二选一。"}, 2)
    if args.version:
        version = require_semver(args.version)
    elif args.bump:
        version = bump_version(current_version, args.bump)
    else:
        version = current_version

    data["skills"][args.skill] = {
        "path": f"skills/{args.skill}",
        "version": version,
        "description": args.description,
        "tags": split_csv(args.tags),
        "requires": split_csv(args.requires),
    }

    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    manifest_path.write_text(text, encoding="utf-8")

    emit({"ok": True, "manifest": str(manifest_path), "skill": args.skill, "entry": data["skills"][args.skill]})


if __name__ == "__main__":
    main()
