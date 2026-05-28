import argparse

from common import check_auth_status, json_exit, parse_json_text, run_cli


def status(_args):
    auth = check_auth_status()
    json_exit({
        "ok": auth["ok"],
        "stage": "auth_status",
        "requiredIdentity": auth.get("requiredIdentity"),
        "identity": auth.get("identity"),
        "tokenStatus": auth.get("tokenStatus"),
        "expiresAt": auth.get("expiresAt"),
        "expiresInSeconds": auth.get("expiresInSeconds"),
        "userName": auth.get("userName"),
        "message": auth.get("message"),
        "diagnostics": auth.get("diagnostics"),
        "next_action": None if auth["ok"] else "run_auth_login",
    }, code=0)


def login(args):
    start = run_cli(["auth", "login", "--domain", args.domain, "--no-wait", "--json"], timeout=60)
    data = parse_json_text(start.get("stdout", ""))
    if not start["ok"] or not isinstance(data, dict) or not data.get("device_code"):
        json_exit({
            "ok": False,
            "stage": "auth_login_start",
            "message": start.get("stderr") or start.get("stdout") or "无法发起 device login",
            "next_action": "inspect_lark_cli_auth_help",
        }, code=1)

    print_json = {
        "ok": False,
        "stage": "auth_login_waiting_user",
        "verification_url": data.get("verification_url"),
        "user_code": data.get("user_code"),
        "expires_in": data.get("expires_in"),
        "message": "请打开 verification_url，确认 user_code，并授权 lark-cli 访问指定 Feishu 能力；脚本不会要求你输入密码、token 或 cookie。",
        "domains": args.domain,
        "next_action": "authorize_in_browser",
    }
    print(__import__("json").dumps(print_json, ensure_ascii=False, indent=2), flush=True)

    complete = run_cli(["auth", "login", "--device-code", data["device_code"]], timeout=args.timeout)
    if not complete["ok"]:
        json_exit({
            "ok": False,
            "stage": "auth_login_complete",
            "message": complete.get("stderr") or complete.get("stdout") or "device login 未完成",
            "next_action": "retry_auth_login",
        }, code=1)

    auth = check_auth_status()
    json_exit({
        "ok": auth["ok"],
        "stage": "auth_login_verified",
        "requiredIdentity": auth.get("requiredIdentity"),
        "identity": auth.get("identity"),
        "tokenStatus": auth.get("tokenStatus"),
        "expiresAt": auth.get("expiresAt"),
        "expiresInSeconds": auth.get("expiresInSeconds"),
        "userName": auth.get("userName"),
        "message": "登录成功并验证通过" if auth["ok"] else "登录完成但验证未通过",
        "diagnostics": auth.get("diagnostics"),
        "next_action": None if auth["ok"] else "inspect_auth_status",
    }, code=0 if auth["ok"] else 1)


def logout(_args):
    result = run_cli(["auth", "logout"], timeout=60)
    auth = check_auth_status()
    json_exit({
        "ok": result["ok"] and not auth["ok"],
        "stage": "auth_logout",
        "message": "已退出 user 授权" if result["ok"] else (result.get("stderr") or result.get("stdout")),
        "identity_after": auth.get("identity"),
        "next_action": "run_auth_login" if result["ok"] else "inspect_logout_error",
    }, code=0 if result["ok"] else 1)


def main():
    parser = argparse.ArgumentParser(description="Manage lark-cli user authorization")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status")

    login_parser = sub.add_parser("login")
    login_parser.add_argument("--domain", default="docs,wiki,drive")
    login_parser.add_argument("--timeout", type=int, default=650)

    sub.add_parser("logout")

    args = parser.parse_args()
    if args.command == "status":
        status(args)
    elif args.command == "login":
        login(args)
    elif args.command == "logout":
        logout(args)


if __name__ == "__main__":
    main()
