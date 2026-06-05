from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .manifest import SkillManifest
from .records import read_record


@dataclass(frozen=True)
class SkillStatus:
    name: str
    state: str
    path: Path
    local_commit: str | None
    remote_commit: str
    installed_at: str | None
    description: str
    requires: list[str]
    tags: list[str]


def get_skill_status(manifest: SkillManifest, target_dir: Path, remote_commit: str, repo: str) -> list[SkillStatus]:
    rows: list[SkillStatus] = []
    for name, skill in sorted(manifest.skills.items()):
        skill_dir = target_dir / name
        record = read_record(skill_dir) if skill_dir.exists() else None
        if not skill_dir.exists():
            state = "未安装"
            local_commit = None
            installed_at = None
        elif record is None:
            state = "已安装，无记录"
            local_commit = None
            installed_at = None
        else:
            local_commit = record.get("commit")
            installed_at = record.get("installedAt")
            if record.get("repo") and record.get("repo") != repo:
                state = "来源不同"
            elif local_commit == remote_commit:
                state = "最新"
            else:
                state = "有更新"
        rows.append(
            SkillStatus(
                name=name,
                state=state,
                path=skill_dir,
                local_commit=local_commit,
                remote_commit=remote_commit,
                installed_at=installed_at,
                description=skill.description,
                requires=skill.requires,
                tags=skill.tags,
            )
        )
    return rows


def find_status(rows: list[SkillStatus], name: str) -> SkillStatus | None:
    return next((row for row in rows if row.name == name), None)
