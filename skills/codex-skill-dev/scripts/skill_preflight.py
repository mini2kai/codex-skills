"""预检 codex-skills 仓库中的单个 skill。"""

from __future__ import annotations

import argparse
import json
import re
import sys

sys.dont_write_bytecode = True
from pathlib import Path
from typing import Any

DISCOURAGED_FILES = {
    "README.md",
    "CHANGELOG.md",
    "INSTALLATION_GUIDE.md",
    "QUICK_REFERENCE.md",
}


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(exit_code)


def has_bom(path: Path) -> bool:
    try:
        return path.read_bytes().startswith(b"\xef\xbb\xbf")
    except OSError:
        return False


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return {}
    normalized = text.replace("\r\n", "\n")
    end = normalized.find("\n---\n", 4)
    if end == -1:
        return {}
    raw = normalized[4:end]
    result: dict[str, str] = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        result[key.strip()] = value.strip().strip('"').strip("'")
    return result


def scan_skill(repo_root: Path, skill: str) -> dict[str, Any]:
    skill_dir = repo_root / "skills" / skill
    checks: list[dict[str, Any]] = []
    warnings: list[str] = []
    errors: list[str] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append({"name": name, "ok": ok, "detail": detail})
        if not ok:
            errors.append(detail or name)

    check("skill_dir_exists", skill_dir.is_dir(), str(skill_dir))
    if not skill_dir.is_dir():
        return {"ok": False, "skill": skill, "checks": checks, "warnings": warnings, "errors": errors}

    skill_md = skill_dir / "SKILL.md"
    check("skill_md_exists", skill_md.is_file(), str(skill_md))

    if skill_md.is_file():
        text = read_text(skill_md)
        frontmatter = parse_frontmatter(text)
        check("frontmatter_name", frontmatter.get("name") == skill, f"frontmatter name 应等于 {skill}")
        check("frontmatter_description", bool(frontmatter.get("description")), "description 不能为空")
        if has_bom(skill_md):
            warnings.append(f"文件包含 UTF-8 BOM：{skill_md}")
        if "[TODO" in text:
            warnings.append(f"SKILL.md 仍包含 TODO：{skill_md}")

    openai_yaml = skill_dir / "agents" / "openai.yaml"
    check("openai_yaml_exists", openai_yaml.is_file(), str(openai_yaml))
    if openai_yaml.is_file():
        text = read_text(openai_yaml)
        if f"${skill}" not in text:
            warnings.append(f"agents/openai.yaml 的 default_prompt 可能未包含 ${skill}")
        if "Use -" in text:
            warnings.append("agents/openai.yaml 可能发生 PowerShell 变量展开，出现了 'Use -'。")
        if has_bom(openai_yaml):
            warnings.append(f"文件包含 UTF-8 BOM：{openai_yaml}")

    for expected in ["references", "scripts"]:
        path = skill_dir / expected
        if not path.exists():
            warnings.append(f"未创建 {expected}/；如果该 skill 不需要可忽略。")

    for path in skill_dir.rglob("*"):
        if path.is_dir() and path.name == "__pycache__":
            errors.append(f"发现 __pycache__：{path}")
        if path.is_file():
            if path.name in DISCOURAGED_FILES:
                warnings.append(f"skill 内不建议创建额外文档：{path.name}")
            if has_bom(path):
                warnings.append(f"文件包含 UTF-8 BOM：{path}")

    py_files = [str(p.relative_to(skill_dir)) for p in skill_dir.rglob("*.py")]
    return {
        "ok": not errors,
        "skill": skill,
        "skill_dir": str(skill_dir),
        "checks": checks,
        "warnings": warnings,
        "errors": errors,
        "python_files": py_files,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="预检 codex-skills 仓库中的单个 skill。")
    parser.add_argument("--repo-root", default=".", help="仓库根目录，默认当前目录。")
    parser.add_argument("--skill", required=True, help="skill 名称。")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    result = scan_skill(repo_root, args.skill)
    emit(result, 0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
