import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
REFERENCES_DIR = SKILL_DIR / "references"

SENSITIVE_KEYS = {
    "access_token",
    "refresh_token",
    "app_secret",
    "client_secret",
    "cookie",
    "device_code",
}


def mask_value(value):
    if value is None:
        return value
    text = str(value)
    if len(text) <= 8:
        return "***"
    return f"{text[:4]}***{text[-4:]}"


def mask_sensitive(obj):
    if isinstance(obj, dict):
        result = {}
        for key, value in obj.items():
            if key.lower() in SENSITIVE_KEYS:
                result[key] = mask_value(value)
            else:
                result[key] = mask_sensitive(value)
        return result
    if isinstance(obj, list):
        return [mask_sensitive(item) for item in obj]
    return obj


def json_exit(payload, code=0):
    payload.setdefault("sensitive_masked", True)
    print(json.dumps(mask_sensitive(payload), ensure_ascii=False, indent=2))
    raise SystemExit(code)


def run_cli(args, timeout=60):
    npx = shutil.which("npx") or shutil.which("npx.cmd") or shutil.which("npx.exe") or "npx"
    cmd = [npx, "@larksuite/cli"] + args
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            shell=False,
        )
    except FileNotFoundError as exc:
        return {
            "ok": False,
            "command": cmd,
            "exit_code": None,
            "stdout": "",
            "stderr": str(exc),
            "error_type": "npx_missing",
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "ok": False,
            "command": cmd,
            "exit_code": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "error_type": "timeout",
        }

    return {
        "ok": proc.returncode == 0,
        "command": cmd,
        "exit_code": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
        "error_type": None if proc.returncode == 0 else "cli_error",
    }


def parse_json_text(text):
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def load_reference_json(name):
    path = REFERENCES_DIR / name
    return json.loads(path.read_text(encoding="utf-8"))


def check_auth_status():
    result = run_cli(["auth", "status", "--verify"], timeout=60)
    data = parse_json_text(result.get("stdout", ""))
    if result["ok"] and isinstance(data, dict):
        identity = data.get("identity")
        token_status = data.get("tokenStatus")
        return {
            "ok": identity == "user" and token_status == "valid" and data.get("verified", True) is not False,
            "identity": identity,
            "tokenStatus": token_status,
            "expiresAt": data.get("expiresAt"),
            "userName": data.get("userName"),
            "raw": data,
            "message": "user 授权有效" if identity == "user" and token_status == "valid" else data.get("note", "user 授权不可用"),
        }
    return {
        "ok": False,
        "identity": None,
        "tokenStatus": None,
        "expiresAt": None,
        "userName": None,
        "raw": data,
        "message": result.get("stderr") or result.get("stdout") or "auth status 执行失败",
    }


def ensure_utf8_file(path):
    file_path = Path(path).expanduser().resolve()
    if not file_path.exists():
        return {"ok": False, "path": str(file_path), "exists": False, "message": "文件不存在"}
    if not file_path.is_file():
        return {"ok": False, "path": str(file_path), "exists": True, "message": "路径不是文件"}
    try:
        content = file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return {"ok": False, "path": str(file_path), "exists": True, "encoding": "non-utf-8", "message": "文件不是 UTF-8"}
    return {
        "ok": True,
        "path": str(file_path),
        "exists": True,
        "encoding": "utf-8",
        "size_bytes": file_path.stat().st_size,
        "line_count": len(content.splitlines()),
        "has_replacement_question_mark": "�" in content,
    }


def infer_title_from_fetch_output(text):
    if not text:
        return None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    data = parse_json_text(text)
    if isinstance(data, dict):
        for key in ("title", "name"):
            if data.get(key):
                return data[key]
    return None


def add_common_args(parser):
    parser.add_argument("--as", dest="as_identity", default="user", choices=["user", "bot", "auto"])
    parser.add_argument("--format", default="pretty")
    return parser
