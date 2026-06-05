from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from . import __version__
from .constants import MANAGER_NAME, RECORD_FILE


@dataclass(frozen=True)
class InstallRecord:
    name: str
    repo: str
    ref: str
    commit: str
    source_path: str
    installed_at: str
    manager: str
    manager_version: str

    @classmethod
    def create(cls, name: str, repo: str, ref: str, commit: str, source_path: str) -> "InstallRecord":
        return cls(
            name=name,
            repo=repo,
            ref=ref,
            commit=commit,
            source_path=source_path,
            installed_at=datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
            manager=MANAGER_NAME,
            manager_version=__version__,
        )

    def to_dict(self) -> dict[str, str]:
        return {
            "name": self.name,
            "repo": self.repo,
            "ref": self.ref,
            "commit": self.commit,
            "sourcePath": self.source_path,
            "installedAt": self.installed_at,
            "manager": self.manager,
            "managerVersion": self.manager_version,
        }


def record_path(skill_dir: Path) -> Path:
    return skill_dir / RECORD_FILE


def write_record(skill_dir: Path, record: InstallRecord) -> None:
    record_path(skill_dir).write_text(json.dumps(record.to_dict(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_record(skill_dir: Path) -> dict[str, str] | None:
    path = record_path(skill_dir)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    return {str(key): str(value) for key, value in data.items() if value is not None}


def short_commit(commit: str | None) -> str:
    if not commit:
        return "-"
    return commit[:7]

