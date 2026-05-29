import argparse

from common import (
    add_common_args,
    check_auth_status,
    clean_sheet_values,
    json_exit,
    matrix_to_markdown,
    normalize_sheet_target,
    parse_json_text,
    run_cli,
)


DEFAULT_RANGE = "A1:AZ500"
SUPPORTED_OPERATIONS = {"sheets_read"}


def require_auth(as_identity="user"):
    auth = check_auth_status(as_identity)
    if not auth["ok"]:
        json_exit({
            "ok": False,
            "stage": "auth_check",
            "error_type": "auth_missing",
            "requiredIdentity": auth.get("requiredIdentity"),
            "identity": auth.get("identity"),
            "tokenStatus": auth.get("tokenStatus"),
            "expiresAt": auth.get("expiresAt"),
            "message": auth.get("message") or "当前没有可用 user 授权",
            "diagnostics": auth.get("diagnostics"),
            "next_action": "run_auth_login",
        }, code=1)
    return auth


def resolve_target_or_exit(args, stage):
    target = normalize_sheet_target(
        target=args.target,
        spreadsheet_token=args.spreadsheet_token,
        sheet_id=args.sheet_id,
    )
    if not target["ok"]:
        json_exit({
            "ok": False,
            "stage": stage,
            "operation": args.operation,
            "target": target,
            "message": target["message"],
            "next_action": target.get("next_action"),
        }, code=1)
    return target


def read_sheet(target, args):
    cli_args = [
        "sheets",
        "+read",
        "--spreadsheet-token",
        target["spreadsheet_token"],
        "--sheet-id",
        target["sheet_id"],
        "--range",
        args.range,
        "--value-render-option",
        args.value_render_option,
        "--as",
        args.as_identity,
    ]
    return run_cli(cli_args, timeout=args.timeout)


def preflight_sheets_read(args):
    target = resolve_target_or_exit(args, "preflight")
    auth = require_auth(args.as_identity)
    json_exit({
        "ok": True,
        "stage": "preflight",
        "operation": "sheets_read",
        "risk": "low",
        "requires_confirmation": False,
        "identity": auth.get("identity"),
        "target": target,
        "range": args.range,
        "strategy": "direct_read_without_info",
        "message": "已从 URL/token 精准识别 spreadsheet_token 和 sheet_id，可跳过 +info 直接读取。",
        "next_action": "execute_sheets_read",
    })


def execute_sheets_read(args):
    target = resolve_target_or_exit(args, "execute")
    auth = require_auth(args.as_identity)
    result = read_sheet(target, args)
    data = parse_json_text(result.get("stdout", "")) if result["ok"] else None
    values = None
    if isinstance(data, dict):
        values = (((data.get("data") or {}).get("valueRange") or {}).get("values"))
    cleaned = clean_sheet_values(values, args.max_cells) if values is not None else {"matrix": [], "text": "", "row_count": 0, "column_count": 0, "cell_count": 0, "truncated": False}
    ok = result["ok"] and values is not None
    json_exit({
        "ok": ok,
        "stage": "execute",
        "operation": "sheets_read",
        "risk": "low",
        "identity": auth.get("identity"),
        "target": target,
        "range": args.range,
        "strategy": "direct_read_without_info",
        "result": {
            "raw_read_ok": result["ok"],
            "cleaned_rows": cleaned["row_count"],
            "cleaned_columns": cleaned["column_count"],
            "cell_count": cleaned.get("cell_count", 0),
            "truncated": cleaned.get("truncated", False),
        },
        "cleaned_text": cleaned["text"][:args.max_text_chars] if args.include_text else None,
        "markdown_table": matrix_to_markdown(cleaned["matrix"])[:args.max_text_chars] if args.include_markdown else None,
        "cleaned_matrix": cleaned["matrix"] if args.include_matrix else None,
        "diagnostics": result.get("diagnostics"),
        "message": "表格读取成功并已完成本地清洗" if ok else (result.get("stderr") or result.get("stdout") or "表格读取失败"),
        "next_action": None if ok else "inspect_sheets_read_error",
    }, code=0 if ok else 1)


def unsupported(args):
    json_exit({
        "ok": False,
        "stage": args.stage,
        "operation": args.operation,
        "risk": "unknown",
        "requires_confirmation": True,
        "error_type": "unsupported_operation",
        "message": "当前 sheet wrapper 尚不支持该 operation。",
        "next_action": "research_capability_then_iterate_skill",
    }, code=2)


def build_parser():
    parser = argparse.ArgumentParser(description="Fast Feishu spreadsheet read wrapper")
    parser.add_argument("stage", choices=["preflight", "execute"])
    parser.add_argument("--operation", default="sheets_read")
    parser.add_argument("--target", help="Feishu spreadsheet URL")
    parser.add_argument("--spreadsheet-token")
    parser.add_argument("--sheet-id")
    parser.add_argument("--range", default=DEFAULT_RANGE)
    parser.add_argument("--value-render-option", default="FormattedValue", choices=["ToString", "FormattedValue", "Formula", "UnformattedValue"])
    parser.add_argument("--include-text", action="store_true")
    parser.add_argument("--include-markdown", action="store_true")
    parser.add_argument("--include-matrix", action="store_true")
    parser.add_argument("--max-text-chars", type=int, default=12000)
    parser.add_argument("--max-cells", type=int, default=20000)
    parser.add_argument("--timeout", type=int, default=120)
    add_common_args(parser)
    return parser


def main():
    args = build_parser().parse_args()
    if args.operation not in SUPPORTED_OPERATIONS:
        unsupported(args)
    if args.stage == "preflight":
        preflight_sheets_read(args)
    else:
        execute_sheets_read(args)


if __name__ == "__main__":
    main()
