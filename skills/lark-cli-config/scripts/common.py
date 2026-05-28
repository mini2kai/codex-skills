import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


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

SENSITIVE_ARG_NAMES = {
    "--access-token",
    "--refresh-token",
    "--app-secret",
    "--client-secret",
    "--cookie",
    "--device-code",
}

FEISHU_DOC_HOST_RE = re.compile(r"(?:^|\.)(?:feishu\.cn|larksuite\.com)$", re.IGNORECASE)
FEISHU_URL_RE = re.compile(r"https?://[^\s\"'<>]+", re.IGNORECASE)
SCOPE_RE = re.compile(r"\b(?:auth|docs|docx|wiki|sheets|base|drive):[A-Za-z0-9_.:-]+\b")


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


def mask_command(cmd):
    masked = []
    hide_next = False
    for item in cmd:
        if hide_next:
            masked.append("***")
            hide_next = False
            continue
        masked.append(item)
        if item in SENSITIVE_ARG_NAMES:
            hide_next = True
    return masked


def json_exit(payload, code=0):
    payload.setdefault("sensitive_masked", True)
    print(json.dumps(mask_sensitive(payload), ensure_ascii=False, indent=2))
    raise SystemExit(code)


def resolve_lark_cli_command():
    for name in ("lark-cli", "lark-cli.cmd", "lark-cli.exe"):
        path = shutil.which(name)
        if path:
            return {
                "runner": "lark-cli",
                "path": path,
                "base_cmd": [path],
            }

    npx = shutil.which("npx") or shutil.which("npx.cmd") or shutil.which("npx.exe")
    if npx:
        return {
            "runner": "npx",
            "path": npx,
            "base_cmd": [npx, "@larksuite/cli"],
        }

    return {
        "runner": "missing",
        "path": None,
        "base_cmd": ["npx", "@larksuite/cli"],
    }


def extract_authorization_url(text):
    for url in FEISHU_URL_RE.findall(text or ""):
        lower = url.lower()
        if "auth" in lower or "authorize" in lower or "open.feishu" in lower or "open.larksuite" in lower:
            return url.rstrip(".,;)")
    return None


def classify_cli_error(stdout="", stderr=""):
    text = "\n".join(part for part in (stdout or "", stderr or "") if part)
    lower = text.lower()
    authorization_url = extract_authorization_url(text)
    missing_scopes = sorted(set(SCOPE_RE.findall(text)))

    if not text:
        return None
    if "no user logged in" in lower or "need_user_authorization" in lower:
        return {
            "error_type": "auth_missing",
            "message": "当前没有可用 user 授权。",
            "next_action": "run_auth_login",
        }
    if "expired" in lower and "token" in lower:
        return {
            "error_type": "auth_expired",
            "message": "user token 已过期，需要重新授权。",
            "next_action": "run_auth_login",
        }
    if "missing scope" in lower or "scope" in lower and ("missing" in lower or "permission" in lower):
        return {
            "error_type": "missing_scope",
            "message": "当前授权缺少操作所需 scope。",
            "missing_scopes": missing_scopes,
            "authorization_url": authorization_url,
            "next_action": "open_authorization_url" if authorization_url else "grant_missing_scopes",
        }
    if "permission" in lower or "forbidden" in lower or "access denied" in lower:
        return {
            "error_type": "permission_denied",
            "message": "当前账号没有目标资源权限。",
            "authorization_url": authorization_url,
            "next_action": "ask_owner_grant_access",
        }
    if "not found" in lower or "invalid token" in lower or "invalid doc" in lower:
        return {
            "error_type": "target_not_found",
            "message": "目标链接或 token 无效，或资源不存在。",
            "next_action": "check_target_url",
        }
    if "network" in lower or "econn" in lower or "timeout" in lower or "proxy" in lower:
        return {
            "error_type": "network_error",
            "message": "连接飞书服务失败，请检查网络或代理。",
            "next_action": "retry_or_check_proxy",
        }
    if authorization_url:
        return {
            "error_type": "authorization_required",
            "message": "需要打开授权链接完成应用或用户授权。",
            "authorization_url": authorization_url,
            "next_action": "open_authorization_url",
        }
    return {
        "error_type": "cli_error",
        "message": "lark-cli 执行失败，请查看 stdout/stderr 摘要。",
        "next_action": "inspect_cli_error",
    }


def run_cli(args, timeout=60):
    cli = resolve_lark_cli_command()
    cmd = cli["base_cmd"] + args
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
            "command": mask_command(cmd),
            "runner": cli["runner"],
            "runner_path": cli["path"],
            "exit_code": None,
            "stdout": "",
            "stderr": str(exc),
            "error_type": "npx_missing",
            "diagnostics": {"error_type": "cli_missing", "message": "未找到 lark-cli 或 npx。", "next_action": "install_lark_cli"},
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "ok": False,
            "command": mask_command(cmd),
            "runner": cli["runner"],
            "runner_path": cli["path"],
            "exit_code": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "error_type": "timeout",
            "diagnostics": {"error_type": "timeout", "message": "lark-cli 执行超时。", "next_action": "retry_or_check_network"},
        }

    diagnostics = None if proc.returncode == 0 else classify_cli_error(proc.stdout, proc.stderr)
    return {
        "ok": proc.returncode == 0,
        "command": mask_command(cmd),
        "runner": cli["runner"],
        "runner_path": cli["path"],
        "exit_code": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
        "error_type": None if proc.returncode == 0 else "cli_error",
        "diagnostics": diagnostics,
    }


def parse_json_text(text):
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    for opener, closer in (("{", "}"), ("[", "]")):
        start = text.find(opener)
        end = text.rfind(closer)
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end + 1])
            except json.JSONDecodeError:
                return None
    return None


def load_reference_json(name):
    path = REFERENCES_DIR / name
    return json.loads(path.read_text(encoding="utf-8"))


def _seconds_until(expires_at):
    if not expires_at:
        return None
    try:
        normalized = expires_at.replace("Z", "+00:00")
        expires = datetime.fromisoformat(normalized)
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        return int((expires - datetime.now(expires.tzinfo)).total_seconds())
    except ValueError:
        return None


def check_auth_status(required_identity="user"):
    result = run_cli(["auth", "status", "--verify"], timeout=60)
    data = parse_json_text(result.get("stdout", ""))
    if result["ok"] and isinstance(data, dict):
        identity = data.get("identity")
        token_status = data.get("tokenStatus")
        verified = data.get("verified", True) is not False
        identity_ok = identity == required_identity if required_identity != "auto" else identity in {"user", "bot"}
        token_ok = token_status == "valid" and verified
        expires_at = data.get("expiresAt")
        return {
            "ok": identity_ok and token_ok,
            "requiredIdentity": required_identity,
            "identity": identity,
            "tokenStatus": token_status,
            "expiresAt": expires_at,
            "expiresInSeconds": _seconds_until(expires_at),
            "userName": data.get("userName"),
            "raw": data,
            "message": f"{required_identity} 授权有效" if identity_ok and token_ok else data.get("note", f"{required_identity} 授权不可用"),
        }
    return {
        "ok": False,
        "requiredIdentity": required_identity,
        "identity": None,
        "tokenStatus": None,
        "expiresAt": None,
        "expiresInSeconds": None,
        "userName": None,
        "raw": data,
        "message": result.get("stderr") or result.get("stdout") or "auth status 执行失败",
        "diagnostics": result.get("diagnostics"),
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


def normalize_document_target(target=None, doc=None, wiki_node=None):
    raw = target or doc or wiki_node
    if not raw:
        return {
            "ok": False,
            "input": None,
            "message": "缺少飞书文档链接、doc_token 或 wiki_node_token。",
            "next_action": "provide_feishu_doc_url_or_token",
        }

    text = str(raw).strip()
    result = {
        "ok": True,
        "input": text,
        "original_url": text if text.startswith(("http://", "https://")) else None,
        "type": "doc",
        "doc": doc if doc else None,
        "wiki_node": wiki_node if wiki_node else None,
        "doc_arg": text,
        "message": "目标已识别为 Feishu 文档。",
        "next_action": None,
    }

    if text.startswith(("http://", "https://")):
        parsed = urlparse(text)
        if not FEISHU_DOC_HOST_RE.search(parsed.hostname or ""):
            result.update({
                "ok": False,
                "type": "unknown_url",
                "message": "链接不是 feishu.cn 或 larksuite.com 域名。",
                "next_action": "provide_feishu_doc_url_or_token",
            })
            return result
        parts = [part for part in parsed.path.split("/") if part]
        for index, part in enumerate(parts):
            if part in {"doc", "docx", "docs"} and index + 1 < len(parts):
                result.update({"type": "doc", "doc": parts[index + 1], "doc_arg": text})
                return result
            if part == "wiki" and index + 1 < len(parts):
                result.update({
                    "type": "wiki_node",
                    "wiki_node": parts[index + 1],
                    "doc_arg": text,
                    "message": "目标已识别为 Feishu wiki 链接，将直接交给 lark-cli 解析。",
                })
                return result
        result.update({
            "ok": False,
            "type": "unknown_url",
            "message": "未能从链接中识别 doc/wiki token。",
            "next_action": "provide_feishu_doc_url_or_token",
        })
        return result

    if wiki_node and not doc:
        result.update({"type": "wiki_node", "wiki_node": text, "doc_arg": text, "message": "目标已识别为 wiki_node_token。"})
    else:
        result.update({"type": "doc", "doc": text, "doc_arg": text})
    return result


def extract_created_doc_reference(text):
    data = parse_json_text(text or "")

    def walk(value):
        if isinstance(value, dict):
            for key in ("url", "document_url", "doc_url", "link"):
                if isinstance(value.get(key), str):
                    target = normalize_document_target(value[key])
                    if target.get("ok"):
                        return target
            for key in ("doc_token", "document_id", "documentId", "doc", "token"):
                if isinstance(value.get(key), str):
                    return normalize_document_target(doc=value[key])
            for item in value.values():
                found = walk(item)
                if found:
                    return found
        elif isinstance(value, list):
            for item in value:
                found = walk(item)
                if found:
                    return found
        return None

    found = walk(data)
    if found:
        return found

    for url in FEISHU_URL_RE.findall(text or ""):
        target = normalize_document_target(url.rstrip(".,;)"))
        if target.get("ok"):
            return target
    return {
        "ok": False,
        "message": "创建结果中未解析出新文档链接或 doc_token。",
        "next_action": "inspect_docs_create_output",
    }


def add_common_args(parser):
    parser.add_argument("--as", dest="as_identity", default="user", choices=["user"])
    parser.add_argument("--format", default="pretty")
    return parser
