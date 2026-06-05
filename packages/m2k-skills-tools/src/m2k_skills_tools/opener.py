from __future__ import annotations

import os
import platform
import subprocess
from pathlib import Path


def open_path(path: Path) -> None:
    system = platform.system().lower()
    if system == "windows":
        if path.is_file():
            subprocess.Popen(["notepad", str(path)])
        else:
            os.startfile(str(path))  # type: ignore[attr-defined]
        return
    if system == "darwin":
        subprocess.Popen(["open", str(path)])
        return
    editor = os.environ.get("EDITOR")
    if path.is_file() and editor:
        subprocess.Popen([editor, str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])

