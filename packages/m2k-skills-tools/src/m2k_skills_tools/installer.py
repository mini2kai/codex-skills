from __future__ import annotations

import shutil
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable

from .github import download_repo_archive
from .local_config import can_restore_config, find_local_config_files, iter_installable_files
from .manifest import SkillInfo, read_local_manifest
from .paths import ensure_child
from .records import InstallRecord, write_record

ProgressCallback = Callable[[int, int, str], None]


@dataclass
class InstallResult:
    name: str
    destination: Path
    installed: bool
    backup: Path | None = None
    restored: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def copy_skill_directory(source: Path, destination: Path, progress: ProgressCallback | None = None, base_step: int = 0, total_steps: int = 1) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    files = iter_installable_files(source)
    total_files = max(1, len(files))
    for index, file in enumerate(files, start=1):
        relative = file.relative_to(source)
        target = destination / relative
        ensure_child(destination, target)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)
        if progress:
            copy_span = max(1, total_steps - base_step - 2)
            copy_step = base_step + int(index / total_files * copy_span)
            progress(copy_step, total_steps, f"复制文件 {index}/{total_files}: {relative}")


def restore_local_configs(backup_root: Path, new_root: Path) -> tuple[list[str], list[str], list[str]]:
    restored: list[str] = []
    skipped: list[str] = []
    warnings: list[str] = []
    for config in find_local_config_files(backup_root):
        relative = config.relative_to(backup_root)
        target = new_root / relative
        ok, reason = can_restore_config(config, target)
        if not ok:
            skipped.append(str(relative))
            warnings.append(f"未自动恢复配置：{relative}。{reason}")
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(config, target)
        restored.append(str(relative))
    return restored, skipped, warnings


def backup_existing(skill_dir: Path, backup_root: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = backup_root / f"{skill_dir.name}-{timestamp}"
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(skill_dir), str(backup))
    return backup


def install_skill(
    skill: SkillInfo,
    target_dir: Path,
    repo: str,
    ref: str,
    force: bool = False,
    progress: ProgressCallback | None = None,
) -> InstallResult:
    def emit(step: int, total: int, message: str) -> None:
        if progress:
            progress(step, total, message)

    total_steps = 10
    target_dir.mkdir(parents=True, exist_ok=True)
    destination = target_dir / skill.name
    ensure_child(target_dir, destination)

    if destination.exists() and not force:
        return InstallResult(name=skill.name, destination=destination, installed=False, warnings=["skill 已存在，未覆盖。使用 update 或 --force。"])

    emit(1, total_steps, f"准备下载 {repo}@{ref}")
    remote = download_repo_archive(repo, ref, progress=lambda message: emit(2, total_steps, message))
    try:
        emit(3, total_steps, "校验 manifest 和 skill 文件")
        manifest = read_local_manifest(remote.root)
        if skill.name not in manifest.skills:
            raise RuntimeError(f"远端 manifest 中不存在 skill：{skill.name}")
        remote_skill = manifest.skills[skill.name]
        source = remote.root / remote_skill.path
        if not (source / "SKILL.md").exists():
            raise RuntimeError(f"远端 skill 无效，缺少 SKILL.md：{remote_skill.path}")

        backup = None
        restored: list[str] = []
        skipped: list[str] = []
        warnings: list[str] = []
        if destination.exists():
            emit(4, total_steps, "备份旧版本")
            backup = backup_existing(destination, target_dir / ".backup")
        else:
            emit(4, total_steps, "目标目录可用")

        emit(5, total_steps, "复制 skill 文件")
        copy_skill_directory(source, destination, progress=progress, base_step=5, total_steps=total_steps)
        if backup:
            emit(9, total_steps, "恢复本地配置")
            restored, skipped, restore_warnings = restore_local_configs(backup, destination)
            warnings.extend(restore_warnings)
        else:
            emit(9, total_steps, "无需恢复本地配置")

        emit(10, total_steps, "写入安装记录")
        write_record(destination, InstallRecord.create(skill.name, repo, ref, remote.commit, remote_skill.version, remote_skill.path))
        return InstallResult(skill.name, destination, True, backup, restored, skipped, warnings)
    finally:
        remote.cleanup()
