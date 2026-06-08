"""同步 m2k-skills-tools PyPI 包版本。"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
PYPROJECT_VERSION_RE = re.compile(r'(?m)^(version\s*=\s*")([^"]+)(")\s*$')
INIT_VERSION_RE = re.compile(r'(?m)^(__version__\s*=\s*")([^"]+)(")\s*$')
LOCK_PACKAGE_RE = re.compile(
    r'(?ms)(\[\[package\]\]\s*\nname\s*=\s*"m2k-skills-tools"\s*\nversion\s*=\s*")([^"]+)(")'
)


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(exit_code)


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


def replace_once(text: str, pattern: re.Pattern[str], version: str, path: Path) -> str:
    updated, count = pattern.subn(rf"\g<1>{version}\g<3>", text, count=1)
    if count != 1:
        emit({"ok": False, "error": "version_field_not_found", "file": str(path)}, 1)
    return updated


def read_current_version(pyproject_path: Path) -> str:
    text = pyproject_path.read_text(encoding="utf-8-sig")
    match = PYPROJECT_VERSION_RE.search(text)
    if not match:
        emit({"ok": False, "error": "pyproject_version_not_found", "file": str(pyproject_path)}, 1)
    return require_semver(match.group(2))


def main() -> None:
    parser = argparse.ArgumentParser(description="同步 m2k-skills-tools PyPI 包版本。")
    parser.add_argument("--repo-root", default=".", help="仓库根目录，默认当前目录。")
    parser.add_argument("--version", help="显式设置包版本，格式 x.y.z。")
    parser.add_argument("--bump", choices=["patch", "minor", "major"], help="基于当前 pyproject 版本自动递增。")
    args = parser.parse_args()

    if args.version and args.bump:
        emit({"ok": False, "error": "version_conflict", "message": "--version 和 --bump 只能二选一。"}, 2)

    repo_root = Path(args.repo_root).resolve()
    package_root = repo_root / "packages" / "m2k-skills-tools"
    pyproject_path = package_root / "pyproject.toml"
    init_path = package_root / "src" / "m2k_skills_tools" / "__init__.py"
    lock_path = package_root / "uv.lock"
    for path in [pyproject_path, init_path, lock_path]:
        if not path.is_file():
            emit({"ok": False, "error": "missing_file", "file": str(path)}, 1)

    current_version = read_current_version(pyproject_path)
    if args.version:
        next_version = require_semver(args.version)
    elif args.bump:
        next_version = bump_version(current_version, args.bump)
    else:
        emit({"ok": False, "error": "missing_version", "message": "请传 --version x.y.z 或 --bump patch|minor|major。"}, 2)

    pyproject_path.write_text(replace_once(pyproject_path.read_text(encoding="utf-8-sig"), PYPROJECT_VERSION_RE, next_version, pyproject_path), encoding="utf-8")
    init_path.write_text(replace_once(init_path.read_text(encoding="utf-8-sig"), INIT_VERSION_RE, next_version, init_path), encoding="utf-8")
    lock_path.write_text(replace_once(lock_path.read_text(encoding="utf-8-sig"), LOCK_PACKAGE_RE, next_version, lock_path), encoding="utf-8")

    dist_root = package_root / "dist"
    tarball = dist_root / f"m2k_skills_tools-{next_version}.tar.gz"
    wheel = dist_root / f"m2k_skills_tools-{next_version}-py3-none-any.whl"
    emit(
        {
            "ok": True,
            "package": "m2k-skills-tools",
            "from_version": current_version,
            "to_version": next_version,
            "updated": [str(pyproject_path), str(init_path), str(lock_path)],
            "next_commands": [
                "uv build packages\\m2k-skills-tools",
                "uvx twine check packages\\m2k-skills-tools\\dist\\*",
                "$env:UV_PUBLISH_TOKEN = \"pypi-你的新PyPI-token\"",
                f"uv publish {tarball} {wheel}",
                "Remove-Item Env:\\UV_PUBLISH_TOKEN",
            ],
        }
    )


if __name__ == "__main__":
    main()
