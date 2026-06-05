from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .github import download_text


@dataclass(frozen=True)
class SkillInfo:
    name: str
    path: str
    description: str
    tags: list[str]
    requires: list[str]


@dataclass(frozen=True)
class SkillManifest:
    name: str
    skills: dict[str, SkillInfo]


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def parse_manifest(text: str) -> SkillManifest:
    data = json.loads(text)
    raw_skills = data.get("skills") or {}
    skills: dict[str, SkillInfo] = {}
    for name, raw in raw_skills.items():
        skills[name] = SkillInfo(
            name=name,
            path=str(raw.get("path") or f"skills/{name}"),
            description=str(raw.get("description") or ""),
            tags=_as_list(raw.get("tags")),
            requires=_as_list(raw.get("requires")),
        )
    return SkillManifest(name=str(data.get("name") or "m2k-skills"), skills=skills)


def read_local_manifest(repo_root: Path) -> SkillManifest:
    return parse_manifest((repo_root / "manifest.json").read_text(encoding="utf-8"))


def read_remote_manifest(repo: str, ref: str) -> SkillManifest:
    return parse_manifest(download_text(repo, ref, "manifest.json"))

