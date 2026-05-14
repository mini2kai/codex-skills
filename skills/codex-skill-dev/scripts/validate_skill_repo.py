"""运行 codex-skills 仓库级 skill 校验。"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

sys.dont_write_bytecode = True
from pathlib import Path
from typing import Any

from skill_preflight import scan_skill

QUICK_VALIDATE = Path.home() / ".codex" / "skills" / ".system" / "skill-creator" / "scripts" / "quick_validate.py"


def run(command: list[str], cwd: Path) -> dict[str, Any]:
    completed = subprocess.run(command, cwd=str(cwd), text=True, capture_output=True)
    return {
        "command": command,
        "returncode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
        "ok": completed.returncode == 0,
    }


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(exit_code)


def main() -> None:
    parser = argparse.ArgumentParser(description="运行 codex-skills 仓库级 skill 校验。")
    parser.add_argument("--repo-root", default=".", help="仓库根目录，默认当前目录。")
    parser.add_argument("--skill", required=True, help="skill 名称。")
    parser.add_argument("--skip-py-compile", action="store_true", help="跳过 Python 脚本语法检查。")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    skill_dir = repo_root / "skills" / args.skill
    results: list[dict[str, Any]] = []
    warnings: list[str] = []

    preflight = scan_skill(repo_root, args.skill)

    if QUICK_VALIDATE.is_file() and skill_dir.is_dir():
        results.append(run([sys.executable, str(QUICK_VALIDATE), str(skill_dir)], repo_root))
    else:
        warnings.append(f"未找到 quick_validate.py 或 skill 目录：{QUICK_VALIDATE}")

    manifest = repo_root / "manifest.json"
    if manifest.is_file():
        results.append(run([sys.executable, "-m", "json.tool", str(manifest)], repo_root))
    else:
        results.append({"ok": False, "command": ["check", "manifest"], "returncode": 1, "stdout": "", "stderr": "manifest.json 不存在"})

    readme = repo_root / "README.md"
    if readme.is_file():
        text = readme.read_text(encoding="utf-8-sig")
        if args.skill not in text:
            warnings.append(f"README.md 未提到 {args.skill}")
    else:
        warnings.append("README.md 不存在")

    py_files = list(skill_dir.rglob("*.py")) if skill_dir.is_dir() else []
    if py_files and not args.skip_py_compile:
        results.append(run([sys.executable, "-m", "py_compile", *[str(path) for path in py_files]], repo_root))
        warnings.append("py_compile 可能生成 __pycache__；校验后请清理。")

    ok = bool(preflight.get("ok")) and all(item.get("ok") for item in results)
    emit(
        {
            "ok": ok,
            "skill": args.skill,
            "preflight": preflight,
            "command_results": results,
            "warnings": warnings,
            "next_action": "如运行了 py_compile，请检查并清理目标 skill 内的 __pycache__。",
        },
        0 if ok else 1,
    )


if __name__ == "__main__":
    main()
