"""预检 m2k-skills 仓库中的单个 skill。"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from pathlib import Path
from typing import Any

DISCOURAGED_FILES = {
    "CHANGELOG.md",
    "INSTALLATION_GUIDE.md",
    "QUICK_REFERENCE.md",
}

SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


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


def parse_semver(version: str) -> tuple[int, int, int] | None:
    match = SEMVER_RE.match(version)
    if not match:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def git_has_skill_changes(repo_root: Path, skill: str) -> bool:
    """检查 skill 目录相对于 HEAD 是否有未提交的改动，或相对于上一次提交是否有已提交的改动。"""
    skill_path = f"skills/{skill}/"

    # 检查工作区和暂存区是否有改动
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain", "--", skill_path],
            capture_output=True, text=True, cwd=str(repo_root)
        )
        if result.stdout.strip():
            return True
    except Exception:
        return False

    # 检查最近一次提交是否包含该 skill 的改动
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD~1", "HEAD", "--", skill_path],
            capture_output=True, text=True, cwd=str(repo_root)
        )
        if result.stdout.strip():
            return True
    except Exception:
        pass

    return False


def git_last_committed_version(repo_root: Path, skill: str) -> str | None:
    """从上一次提交中读取 manifest 里该 skill 的版本号。"""
    try:
        result = subprocess.run(
            ["git", "show", "HEAD~1:manifest.json"],
            capture_output=True, text=True, cwd=str(repo_root)
        )
        if result.returncode != 0:
            return None
        old_manifest = json.loads(result.stdout)
        entry = (old_manifest.get("skills") or {}).get(skill)
        if isinstance(entry, dict):
            return entry.get("version")
    except Exception:
        pass
    return None


def check_version_bumped(repo_root: Path, skill: str, current_version: str) -> dict[str, Any]:
    """检查 skill 有改动时版本是否已递增。返回检查结果。"""
    has_changes = git_has_skill_changes(repo_root, skill)
    if not has_changes:
        return {"name": "version_bump", "ok": True, "detail": "skill 无改动，无需递增版本"}

    old_version = git_last_committed_version(repo_root, skill)
    if old_version is None:
        return {"name": "version_bump", "ok": True, "detail": "无法获取旧版本（新 skill 或首次提交），跳过检查"}

    old = parse_semver(old_version)
    new = parse_semver(current_version)
    if old is None or new is None:
        return {"name": "version_bump", "ok": False, "detail": f"版本号格式异常：旧={old_version} 新={current_version}"}

    if new > old:
        return {"name": "version_bump", "ok": True, "detail": f"版本已递增：{old_version} -> {current_version}"}
    else:
        return {
            "name": "version_bump",
            "ok": False,
            "detail": f"skill 目录有改动但 manifest 版本未递增（当前={current_version}，上次={old_version}）。请根据变更范围递增：patch/minor/major。"
        }


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

    # manifest 检查
    manifest_path = repo_root / "manifest.json"
    current_version = None
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
            entry = (manifest.get("skills") or {}).get(skill)
            check("manifest_entry", isinstance(entry, dict), f"manifest.json 应包含 {skill}")
            if isinstance(entry, dict):
                current_version = str(entry.get("version") or "")
                check("manifest_version", bool(SEMVER_RE.match(current_version)), "manifest version 必须是 x.y.z 格式")
        except Exception as exc:
            check("manifest_readable", False, f"manifest.json 读取失败：{exc}")
    else:
        check("manifest_exists", False, str(manifest_path))

    # 版本递增检查（围栏：有改动就必须递增版本）
    if current_version and SEMVER_RE.match(current_version):
        bump_result = check_version_bumped(repo_root, skill, current_version)
        checks.append(bump_result)
        if not bump_result["ok"]:
            errors.append(bump_result["detail"])

    # SKILL.md 检查
    skill_md = skill_dir / "SKILL.md"
    check("skill_md_exists", skill_md.is_file(), str(skill_md))

    if skill_md.is_file():
        text = read_text(skill_md)
        frontmatter = parse_frontmatter(text)
        check("frontmatter_name", frontmatter.get("name") == skill, f"frontmatter name 应等于 {skill}")
        check("frontmatter_description", bool(frontmatter.get("description")), "description 不能为空")
        if has_bom(skill_md):
            warnings.append(f"文件包含 UTF-8 BOM：{skill_md}")

    # DESIGN.md 检查
    design_md = skill_dir / "DESIGN.md"
    if not design_md.is_file():
        warnings.append("缺少 DESIGN.md（设计理念文档）")

    # 测试检查
    scripts_dir = skill_dir / "scripts"
    if scripts_dir.is_dir():
        test_files = list(scripts_dir.glob("test_*.py"))
        if not test_files:
            warnings.append("scripts/ 下没有 test_*.py 测试文件；围栏逻辑必须有测试")

    # 文件规范检查
    for path in skill_dir.rglob("*"):
        if path.is_dir() and path.name == "__pycache__":
            errors.append(f"发现 __pycache__：{path}")
        if path.is_file():
            if path.name in DISCOURAGED_FILES:
                warnings.append(f"skill 内不建议创建该文件：{path.name}")
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
    parser = argparse.ArgumentParser(description="预检 m2k-skills 仓库中的单个 skill。")
    parser.add_argument("--repo-root", default=".", help="仓库根目录，默认当前目录。")
    parser.add_argument("--skill", required=True, help="skill 名称。")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    result = scan_skill(repo_root, args.skill)
    emit(result, 0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
