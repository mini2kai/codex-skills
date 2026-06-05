from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .github import download_text


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    detail: str


def _command_version(command: str, args: list[str] | None = None) -> CheckResult:
    args = args or ["--version"]
    path = shutil.which(command)
    if not path:
        return CheckResult(command, False, "未找到")
    try:
        result = subprocess.run([path, *args], check=False, capture_output=True, text=True, timeout=10)
        output = (result.stdout or result.stderr or path).strip().splitlines()[0]
        return CheckResult(command, result.returncode == 0, output)
    except Exception as exc:
        return CheckResult(command, False, str(exc))


def run_doctor(target_dir: Path, repo: str, ref: str) -> list[CheckResult]:
    return list(iter_doctor_checks(target_dir, repo, ref))


def iter_doctor_checks(target_dir: Path, repo: str, ref: str):
    for command in ["python", "uv", "git", "node", "npx"]:
        yield _command_version(command)

    pwsh = _command_version("pwsh", ["-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"])
    powershell = _command_version("powershell", ["-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"])
    yield pwsh if pwsh.ok else powershell

    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        probe = target_dir / ".m2k-write-test"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink()
        yield CheckResult("skills-dir", True, str(target_dir.resolve()))
    except Exception as exc:
        yield CheckResult("skills-dir", False, str(exc))

    try:
        download_text(repo, ref, "manifest.json")
        yield CheckResult("manifest", True, f"{repo}@{ref}")
    except Exception as exc:
        yield CheckResult("manifest", False, str(exc))
