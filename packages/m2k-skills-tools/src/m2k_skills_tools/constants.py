from __future__ import annotations

from pathlib import Path

DEFAULT_REPO = "mini2kai/m2k-skills"
DEFAULT_REF = "main"
MANAGER_NAME = "m2k-skills-tools"
RECORD_FILE = ".m2k-skill.json"

RUNTIME_DIR_NAMES = {
    "__pycache__",
    ".pytest_cache",
    "logs",
    "tmp",
    "temp",
    "cache",
}

RUNTIME_FILE_SUFFIXES = {
    ".xlsx",
    ".xlsm",
    ".xls",
    ".log",
    ".tmp",
    ".bak",
    ".pyc",
}

RUNTIME_FILE_MARKERS = (
    "state",
    "cache",
    "history",
    "preview",
    "ledger",
    "output",
    "result",
    "worklog",
)


def default_targets() -> dict[str, Path]:
    home = Path.home()
    return {
        "codex": home / ".codex" / "skills",
        "claude": home / ".claude" / "skills",
        "current": Path.cwd(),
    }

