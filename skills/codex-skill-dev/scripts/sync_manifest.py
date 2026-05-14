"""同步 codex-skills 仓库 manifest.json 中的 skill 信息。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(exit_code)


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description="同步 manifest.json 中的 skill 信息。")
    parser.add_argument("--repo-root", default=".", help="仓库根目录，默认当前目录。")
    parser.add_argument("--skill", required=True, help="skill 名称。")
    parser.add_argument("--description", required=True, help="中文说明。")
    parser.add_argument("--tags", default="", help="逗号分隔 tags。")
    parser.add_argument("--requires", default="", help="逗号分隔依赖。")
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
    data["skills"][args.skill] = {
        "path": f"skills/{args.skill}",
        "description": args.description,
        "tags": split_csv(args.tags),
        "requires": split_csv(args.requires),
    }

    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    manifest_path.write_text(text, encoding="utf-8")

    emit({"ok": True, "manifest": str(manifest_path), "skill": args.skill, "entry": data["skills"][args.skill]})


if __name__ == "__main__":
    main()
