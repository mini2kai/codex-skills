"""测试 git_common.ps1 中的安全检查逻辑。

运行方式：
    cd skills/git-trunk-workflow/scripts
    python test_git_safety.py

通过 Python 重新实现 PowerShell 中的校验逻辑来验证设计意图。
"""

from __future__ import annotations

import re
import sys

# --- 从 git_common.ps1 提取的围栏规则 ---

PROTECTED_BRANCHES = {'main', 'master', 'dev', 'uat', 'prod', 'production', 'staging'}
PROTECTED_PREFIXES = ('release/', 'hotfix/')

AI_BRANCH_PATTERN = re.compile(
    r'^ai/[A-Za-z0-9._-]+/[0-9]{8}-(fix|feat|bug|hotfix|docs|chore|refactor)-[A-Za-z0-9._-]+$'
)

FORBIDDEN_STAGE_PATHS = {'.', '*', ':/', '--all', '-A', '-u'}


def is_protected_branch(branch: str) -> bool:
    if branch in PROTECTED_BRANCHES:
        return True
    for prefix in PROTECTED_PREFIXES:
        if branch.startswith(prefix):
            return True
    return False


def is_valid_ai_branch_name(branch: str) -> bool:
    return AI_BRANCH_PATTERN.match(branch) is not None


def is_ai_branch(branch: str) -> bool:
    return branch.startswith('ai/')


def is_forbidden_stage_path(path: str) -> bool:
    if path.strip() in FORBIDDEN_STAGE_PATHS:
        return True
    if '*' in path:
        return True
    if not path or path.isspace():
        return True
    return False


# === 保护分支测试 ===

PROTECTED_CASES = [
    'main', 'master', 'dev', 'uat', 'prod', 'production', 'staging',
    'release/202606', 'release/v1.0', 'hotfix/login-fix',
]

NOT_PROTECTED_CASES = [
    'ai/dev/20260610-fix-bug',
    'feature/add-search',
    'bugfix/OTB-123',
    'experiment/test',
]

# === AI 分支命名测试 ===

VALID_AI_NAMES = [
    'ai/uat/20260608-fix-export-null',
    'ai/dev/20260608-feat-shop-filter',
    'ai/release-202606/20260608-hotfix-price-sync',
    'ai/prod/20260608-hotfix-login-npe',
    'ai/dev/20260610-docs-update-readme',
    'ai/uat/20260610-chore-cleanup',
    'ai/dev/20260610-refactor-query-module',
    'ai/uat/20260610-bug-OTB-1234-export-null',
]

INVALID_AI_NAMES = [
    'dev',
    'main',
    'feature/something',
    'ai/',
    'ai/dev',
    'ai/dev/',
    'ai/dev/20260608',
    'ai/dev/20260608-unknown-type-topic',
    'ai/dev/fix-no-date',
    'ai/dev/2026060-fix-short-date',
]

# === 暂存路径测试 ===

FORBIDDEN_PATHS = ['.', '*', ':/', '--all', '-A', '-u', '', '  ', 'src/*.ts', '**/*.py']

ALLOWED_PATHS = [
    'src/main.py',
    'skills/postgres-query/scripts/pg_query.py',
    'README.md',
    'manifest.json',
    'skills/git-trunk-workflow/SKILL.md',
]


def test_protected_branches():
    failures = []
    for branch in PROTECTED_CASES:
        if not is_protected_branch(branch):
            failures.append(f"FAIL (should be protected): {branch!r}")
    for branch in NOT_PROTECTED_CASES:
        if is_protected_branch(branch):
            failures.append(f"FAIL (should NOT be protected): {branch!r}")
    return failures


def test_ai_branch_names():
    failures = []
    for name in VALID_AI_NAMES:
        if not is_valid_ai_branch_name(name):
            failures.append(f"FAIL (should be valid): {name!r}")
    for name in INVALID_AI_NAMES:
        if is_valid_ai_branch_name(name):
            failures.append(f"FAIL (should be invalid): {name!r}")
    return failures


def test_stage_paths():
    failures = []
    for path in FORBIDDEN_PATHS:
        if not is_forbidden_stage_path(path):
            failures.append(f"FAIL (should be forbidden): {path!r}")
    for path in ALLOWED_PATHS:
        if is_forbidden_stage_path(path):
            failures.append(f"FAIL (should be allowed): {path!r}")
    return failures


def test_push_protection():
    """push_ai_branch.ps1 的逻辑：只允许 push ai/* 分支。"""
    failures = []
    # 应该允许 push
    for branch in ['ai/dev/20260610-fix-bug', 'ai/uat/20260610-feat-new']:
        if not is_ai_branch(branch):
            failures.append(f"FAIL (should allow push): {branch!r}")
        if is_protected_branch(branch):
            failures.append(f"FAIL (ai branch marked protected): {branch!r}")
    # 应该拒绝 push
    for branch in PROTECTED_CASES + ['feature/something', 'bugfix/test']:
        if is_ai_branch(branch):
            failures.append(f"FAIL (non-ai branch passed ai check): {branch!r}")
    return failures


def test_commit_protection():
    """commit_cn.ps1 的逻辑：保护分支上不允许 commit。"""
    failures = []
    for branch in PROTECTED_CASES:
        if not is_protected_branch(branch):
            failures.append(f"FAIL (should block commit on): {branch!r}")
    for branch in ['ai/dev/20260610-fix-bug', 'feature/test']:
        if is_protected_branch(branch):
            failures.append(f"FAIL (should allow commit on): {branch!r}")
    return failures


def main():
    all_failures = []
    tests = [
        ("protected_branches", test_protected_branches),
        ("ai_branch_names", test_ai_branch_names),
        ("stage_paths", test_stage_paths),
        ("push_protection", test_push_protection),
        ("commit_protection", test_commit_protection),
    ]

    for name, test_fn in tests:
        failures = test_fn()
        if failures:
            print(f"\n{'='*60}")
            print(f"FAILED: {name}")
            print(f"{'='*60}")
            for f in failures:
                print(f"  {f}")
            all_failures.extend(failures)
        else:
            print(f"  PASSED: {name}")

    print(f"\n{'='*60}")
    if all_failures:
        print(f"TOTAL FAILURES: {len(all_failures)}")
        raise SystemExit(1)
    else:
        print("ALL TESTS PASSED")
        raise SystemExit(0)


if __name__ == "__main__":
    main()
