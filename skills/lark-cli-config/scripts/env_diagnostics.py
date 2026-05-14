from common import json_exit, parse_json_text, run_cli


def main():
    help_result = run_cli(["--help"], timeout=60)
    doctor_result = run_cli(["doctor"], timeout=90)
    doctor_json = parse_json_text(doctor_result.get("stdout", ""))

    warnings = []
    blocking = []
    token_missing = False

    if isinstance(doctor_json, dict):
        for check in doctor_json.get("checks", []):
            status = check.get("status")
            name = check.get("name")
            message = check.get("message")
            if status == "warn":
                warnings.append({"name": name, "message": message, "hint": check.get("hint")})
            elif status == "fail":
                if name == "token_exists":
                    token_missing = True
                else:
                    blocking.append({"name": name, "message": message, "hint": check.get("hint")})
    elif not doctor_result["ok"]:
        blocking.append({"name": "doctor", "message": doctor_result.get("stderr") or doctor_result.get("stdout")})

    ok = help_result["ok"] and not blocking
    next_action = "run_auth_login" if token_missing else (None if ok else "fix_environment")

    json_exit({
        "ok": ok,
        "stage": "env_diagnostics",
        "cli_available": help_result["ok"],
        "doctor_ok": bool(isinstance(doctor_json, dict) and doctor_json.get("ok")) if not token_missing else False,
        "token_missing": token_missing,
        "warnings": warnings,
        "blocking": blocking,
        "message": "lark-cli 环境可用" if ok else "lark-cli 环境存在待处理项",
        "next_action": next_action,
    }, code=0 if help_result["ok"] else 1)


if __name__ == "__main__":
    main()
