import argparse
from pathlib import Path

from common import (
    add_common_args,
    check_auth_status,
    ensure_utf8_file,
    infer_title_from_fetch_output,
    json_exit,
    load_reference_json,
    run_cli,
)


SUPPORTED_OPERATIONS = {"docs_fetch", "docs_create", "docs_update_overwrite"}


def risk_info(operation):
    matrix = load_reference_json("operation_risk_matrix.json")
    return matrix.get(operation, {
        "risk": "unknown",
        "requires_confirmation": True,
        "preflight_read_required": True,
        "post_verify_required": True,
        "description": "未登记操作",
    })


def require_auth():
    auth = check_auth_status()
    if not auth["ok"]:
        json_exit({
            "ok": False,
            "stage": "auth_check",
            "error_type": "auth_missing",
            "identity": auth.get("identity"),
            "tokenStatus": auth.get("tokenStatus"),
            "message": auth.get("message") or "当前没有可用 user 授权",
            "next_action": "run_lz_lark_cli_config_auth",
        }, code=1)
    return auth


def fetch_doc(doc, as_identity="user", output_format="pretty"):
    return run_cli(["docs", "+fetch", "--doc", doc, "--as", as_identity, "--format", output_format], timeout=120)


def preflight_docs_fetch(args):
    auth = require_auth()
    info = risk_info("docs_fetch")
    json_exit({
        "ok": True,
        "stage": "preflight",
        "operation": "docs_fetch",
        "risk": info["risk"],
        "requires_confirmation": info["requires_confirmation"],
        "identity": auth.get("identity"),
        "target": {"type": "doc", "doc": args.doc},
        "message": "读取操作风险较低，可直接 execute。",
        "next_action": "execute_docs_fetch",
    })


def execute_docs_fetch(args):
    auth = require_auth()
    result = fetch_doc(args.doc, args.as_identity, args.format)
    title = infer_title_from_fetch_output(result.get("stdout", ""))
    json_exit({
        "ok": result["ok"],
        "stage": "execute",
        "operation": "docs_fetch",
        "risk": risk_info("docs_fetch")["risk"],
        "identity": auth.get("identity"),
        "target": {"type": "doc", "doc": args.doc, "title": title},
        "result": {
            "verified": result["ok"],
            "title": title,
            "content_preview": result.get("stdout", "")[:1200] if args.include_preview else None,
        },
        "message": "文档读取成功" if result["ok"] else (result.get("stderr") or result.get("stdout") or "文档读取失败"),
        "next_action": None if result["ok"] else "inspect_docs_fetch_error",
    }, code=0 if result["ok"] else 1)


def preflight_docs_create(args):
    auth = require_auth()
    file_info = ensure_utf8_file(args.markdown)
    info = risk_info("docs_create")
    ok = file_info["ok"] and bool(args.title)
    json_exit({
        "ok": ok,
        "stage": "preflight",
        "operation": "docs_create",
        "risk": info["risk"],
        "requires_confirmation": info["requires_confirmation"],
        "identity": auth.get("identity"),
        "target": {"type": "wiki_node", "wiki_node": args.wiki_node, "title": args.title},
        "local_input": file_info,
        "message": "创建文档前置检查通过" if ok else "创建文档前置检查未通过",
        "next_action": "execute_docs_create" if ok else "fix_preflight_blocker",
    }, code=0 if ok else 1)


def execute_docs_create(args):
    auth = require_auth()
    file_info = ensure_utf8_file(args.markdown)
    if not file_info["ok"]:
        json_exit({
            "ok": False,
            "stage": "execute",
            "operation": "docs_create",
            "local_input": file_info,
            "message": "markdown 文件检查失败，拒绝创建文档",
            "next_action": "fix_markdown_file",
        }, code=1)
    cli_args = ["docs", "+create", "--title", args.title, "--markdown", f"@{file_info['path']}", "--as", args.as_identity]
    if args.wiki_node:
        cli_args[2:2] = ["--wiki-node", args.wiki_node]
    result = run_cli(cli_args, timeout=180)
    json_exit({
        "ok": result["ok"],
        "stage": "execute",
        "operation": "docs_create",
        "risk": risk_info("docs_create")["risk"],
        "identity": auth.get("identity"),
        "target": {"type": "wiki_node", "wiki_node": args.wiki_node, "title": args.title},
        "local_input": file_info,
        "raw_result_preview": result.get("stdout", "")[:1200],
        "message": "文档创建成功" if result["ok"] else (result.get("stderr") or result.get("stdout") or "文档创建失败"),
        "next_action": "fetch_created_doc_to_verify" if result["ok"] else "inspect_docs_create_error",
    }, code=0 if result["ok"] else 1)


def preflight_docs_update_overwrite(args):
    auth = require_auth()
    info = risk_info("docs_update_overwrite")
    fetch = fetch_doc(args.doc, args.as_identity, "pretty")
    title = infer_title_from_fetch_output(fetch.get("stdout", ""))
    file_info = ensure_utf8_file(args.markdown)
    ok = fetch["ok"] and file_info["ok"]
    json_exit({
        "ok": ok,
        "stage": "preflight",
        "operation": "docs_update_overwrite",
        "risk": info["risk"],
        "requires_confirmation": True,
        "identity": auth.get("identity"),
        "target": {"type": "doc", "doc": args.doc, "title": title, "fetch_verified": fetch["ok"]},
        "local_input": file_info,
        "impact": [
            "目标 Feishu 文档正文将被本地 markdown 完整替换。",
            "原文档内容可能无法通过 lark-cli 自动恢复。",
            "执行后会立即 docs +fetch 校验标题和主要内容。",
        ],
        "confirm_phrase": "确认覆盖该 Feishu 文档",
        "message": "覆盖更新前置检查通过，等待使用者确认" if ok else "覆盖更新前置检查未通过",
        "next_action": "ask_user_confirmation" if ok else "fix_preflight_blocker",
    }, code=0 if ok else 1)


def execute_docs_update_overwrite(args):
    auth = require_auth()
    if not args.confirmed:
        json_exit({
            "ok": False,
            "stage": "execute",
            "operation": "docs_update_overwrite",
            "risk": risk_info("docs_update_overwrite")["risk"],
            "requires_confirmation": True,
            "message": "缺少 --confirmed，拒绝执行覆盖更新。",
            "confirm_phrase": "确认覆盖该 Feishu 文档",
            "next_action": "ask_user_confirmation",
        }, code=1)
    file_info = ensure_utf8_file(args.markdown)
    if not file_info["ok"]:
        json_exit({
            "ok": False,
            "stage": "execute",
            "operation": "docs_update_overwrite",
            "local_input": file_info,
            "message": "markdown 文件检查失败，拒绝覆盖更新",
            "next_action": "fix_markdown_file",
        }, code=1)
    update = run_cli(["docs", "+update", "--doc", args.doc, "--mode", "overwrite", "--markdown", f"@{file_info['path']}", "--as", args.as_identity], timeout=180)
    verify = fetch_doc(args.doc, args.as_identity, "pretty") if update["ok"] else {"ok": False, "stdout": "", "stderr": "update failed"}
    title = infer_title_from_fetch_output(verify.get("stdout", ""))
    json_exit({
        "ok": update["ok"] and verify["ok"],
        "stage": "execute",
        "operation": "docs_update_overwrite",
        "risk": risk_info("docs_update_overwrite")["risk"],
        "identity": auth.get("identity"),
        "target": {"type": "doc", "doc": args.doc, "title": title},
        "local_input": file_info,
        "result": {"update_ok": update["ok"], "fetch_verify_ok": verify["ok"], "title": title},
        "message": "覆盖更新成功并完成 fetch 验证" if update["ok"] and verify["ok"] else (update.get("stderr") or verify.get("stderr") or "覆盖更新或验证失败"),
        "next_action": None if update["ok"] and verify["ok"] else "inspect_update_or_verify_error",
    }, code=0 if update["ok"] and verify["ok"] else 1)


def unsupported(args):
    info = risk_info(args.operation)
    json_exit({
        "ok": False,
        "stage": args.stage,
        "operation": args.operation,
        "risk": info["risk"],
        "requires_confirmation": info.get("requires_confirmation", True),
        "error_type": "unsupported_operation",
        "message": "当前 wrapper 尚不支持该 operation。请先检索 lark-cli help/schema 或官方文档，使用只读命令验证处理方式，完成任务后将稳定流程沉淀回 skill。",
        "next_action": "research_capability_then_iterate_skill",
    }, code=2)


def build_parser():
    parser = argparse.ArgumentParser(description="Safe Feishu document operation wrapper")
    parser.add_argument("stage", choices=["preflight", "execute"])
    parser.add_argument("--operation", required=True)
    parser.add_argument("--doc")
    parser.add_argument("--wiki-node")
    parser.add_argument("--title")
    parser.add_argument("--markdown")
    parser.add_argument("--confirmed", action="store_true")
    parser.add_argument("--include-preview", action="store_true")
    add_common_args(parser)
    return parser


def main():
    args = build_parser().parse_args()
    if args.operation not in SUPPORTED_OPERATIONS:
        unsupported(args)

    if args.stage == "preflight" and args.operation == "docs_fetch":
        preflight_docs_fetch(args)
    elif args.stage == "execute" and args.operation == "docs_fetch":
        if not args.doc:
            json_exit({"ok": False, "message": "缺少 --doc", "next_action": "provide_doc"}, code=1)
        execute_docs_fetch(args)
    elif args.stage == "preflight" and args.operation == "docs_create":
        if not args.title or not args.markdown:
            json_exit({"ok": False, "message": "缺少 --title 或 --markdown", "next_action": "provide_required_args"}, code=1)
        preflight_docs_create(args)
    elif args.stage == "execute" and args.operation == "docs_create":
        if not args.title or not args.markdown:
            json_exit({"ok": False, "message": "缺少 --title 或 --markdown", "next_action": "provide_required_args"}, code=1)
        execute_docs_create(args)
    elif args.stage == "preflight" and args.operation == "docs_update_overwrite":
        if not args.doc or not args.markdown:
            json_exit({"ok": False, "message": "缺少 --doc 或 --markdown", "next_action": "provide_required_args"}, code=1)
        preflight_docs_update_overwrite(args)
    elif args.stage == "execute" and args.operation == "docs_update_overwrite":
        if not args.doc or not args.markdown:
            json_exit({"ok": False, "message": "缺少 --doc 或 --markdown", "next_action": "provide_required_args"}, code=1)
        execute_docs_update_overwrite(args)


if __name__ == "__main__":
    main()
