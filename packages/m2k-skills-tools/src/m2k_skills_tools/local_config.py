from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .constants import RUNTIME_DIR_NAMES, RUNTIME_FILE_MARKERS, RUNTIME_FILE_SUFFIXES


def is_runtime_artifact(path: Path) -> bool:
    parts = {part.lower() for part in path.parts}
    if parts.intersection(RUNTIME_DIR_NAMES):
        return True
    name = path.name.lower()
    if path.suffix.lower() in RUNTIME_FILE_SUFFIXES:
        return True
    if path.parent.parts and path.parent.parts[0].lower() == "data" and ".local." in name:
        return True
    return any(marker in name for marker in RUNTIME_FILE_MARKERS) and path.suffix.lower() in {".json", ".jsonc"}


def iter_installable_files(skill_root: Path) -> list[Path]:
    files: list[Path] = []
    for path in skill_root.rglob("*"):
        if path.is_file():
            relative = path.relative_to(skill_root)
            if not is_runtime_artifact(relative):
                files.append(path)
    return files


def find_local_config_files(skill_root: Path) -> list[Path]:
    if not skill_root.exists():
        return []
    configs: list[Path] = []
    for path in skill_root.rglob("*"):
        if not path.is_file():
            continue
        name = path.name.lower()
        if not (name.endswith(".local.json") or name.endswith(".local.jsonc")):
            continue
        relative = path.relative_to(skill_root)
        if is_runtime_artifact(relative):
            continue
        configs.append(path)
    return sorted(configs)


def _strip_json_comments(text: str) -> str:
    result: list[str] = []
    in_string = False
    escaped = False
    i = 0
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_string:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            result.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < len(text) and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        result.append(ch)
        i += 1
    return "".join(result)


def _schema_paths(value: Any, prefix: str = "") -> set[str]:
    paths: set[str] = set()
    if value is None or not isinstance(value, (dict, list)):
        if prefix:
            paths.add(prefix)
        return paths
    if isinstance(value, list):
        array_path = f"{prefix}[]" if prefix else "[]"
        paths.add(array_path)
        for item in value:
            paths.update(_schema_paths(item, array_path))
        return paths
    for key, item in value.items():
        path = f"{prefix}.{key}" if prefix else str(key)
        paths.add(path)
        paths.update(_schema_paths(item, path))
    return paths


def read_jsonish_schema(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".jsonc":
        text = _strip_json_comments(text)
    data = json.loads(text)
    if isinstance(data, dict) and "_fieldDescriptions" in data:
        data = data["_fieldDescriptions"]
    return _schema_paths(data)


def can_restore_config(old_path: Path, new_path: Path) -> tuple[bool, str]:
    if not new_path.exists():
        return True, "新版无同路径模板，直接恢复旧配置。"
    try:
        old_schema = read_jsonish_schema(old_path)
        new_schema = read_jsonish_schema(new_path)
    except Exception as exc:
        return False, f"配置结构解析失败：{exc}"
    if old_schema == new_schema:
        return True, "配置结构一致。"
    return False, "配置结构不同，请从备份中手动迁移。"

