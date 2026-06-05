from __future__ import annotations

from pathlib import Path

from .constants import default_targets


def resolve_target_dir(target: str | None = None, skills_dir: str | None = None) -> Path:
    if skills_dir:
        path = Path(skills_dir).expanduser()
        if not path.is_absolute():
            raise ValueError("自定义 skills 目录必须是绝对路径。")
        return path

    key = (target or "codex").lower()
    targets = default_targets()
    if key not in targets:
        choices = ", ".join(sorted(targets))
        raise ValueError(f"未知目标目录：{target}。可选值：{choices}，或使用 --skills-dir。")
    return targets[key]


def ensure_child(parent: Path, child: Path) -> None:
    parent_resolved = parent.resolve()
    child_resolved = child.resolve()
    if child_resolved != parent_resolved and parent_resolved not in child_resolved.parents:
        raise ValueError(f"路径异常：{child_resolved} 不在 {parent_resolved} 下。")


def short_path(path: Path) -> str:
    try:
        return str(path.resolve())
    except OSError:
        return str(path)

