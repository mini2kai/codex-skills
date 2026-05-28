from common import classify_cli_error, extract_created_doc_reference, json_exit, normalize_document_target


def check(name, ok, detail=None):
    return {"name": name, "ok": bool(ok), "detail": detail}


def main():
    checks = []

    doc_url = normalize_document_target("https://example.feishu.cn/docx/ABCDEF154326")
    checks.append(check("doc_url_resolves", doc_url.get("ok") and doc_url.get("doc") == "ABCDEF154326", doc_url))

    wiki_url = normalize_document_target("https://example.feishu.cn/wiki/WIKINODE123")
    checks.append(check("wiki_url_resolves", wiki_url.get("ok") and wiki_url.get("wiki_node") == "WIKINODE123", wiki_url))

    bad_url = normalize_document_target("https://example.com/docx/ABCDEF154326")
    checks.append(check("foreign_url_rejected", not bad_url.get("ok") and bad_url.get("next_action") == "provide_feishu_doc_url_or_token", bad_url))

    missing_scope = classify_cli_error("", "missing scope docs:document.content:read https://open.feishu.cn/app/auth")
    checks.append(check("missing_scope_classified", missing_scope.get("error_type") == "missing_scope", missing_scope))

    auth_missing = classify_cli_error("No user logged in", "")
    checks.append(check("auth_missing_classified", auth_missing.get("next_action") == "run_auth_login", auth_missing))

    created = extract_created_doc_reference('{"url":"https://example.feishu.cn/docx/CREATEDTOKEN"}')
    checks.append(check("created_doc_reference_extracted", created.get("ok") and created.get("doc") == "CREATEDTOKEN", created))

    ok = all(item["ok"] for item in checks)
    json_exit({
        "ok": ok,
        "stage": "self_test",
        "checks": checks,
        "message": "lark-cli-config 本地自测通过" if ok else "lark-cli-config 本地自测失败",
        "next_action": None if ok else "inspect_failed_checks",
    }, code=0 if ok else 1)


if __name__ == "__main__":
    main()
