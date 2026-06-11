# server-docker-logs-readonly: Allowlist Scripts as the Only Entry Point

[中文版](./DESIGN_cn.md)

## Problem

AI Agents need to read server logs for troubleshooting, but giving them SSH access is unacceptable — a single wrong command can modify server state, leak credentials, or cause service disruption.

The traditional approach is prompting "don't run dangerous commands." But prompt constraints can be ignored. You need a guarantee that the AI physically cannot execute anything beyond read-only log retrieval.

## Design Philosophy

**No SSH shell access. Only allowlisted scripts. Every parameter validated. Every action audited.**

The AI never touches the server directly. It can only call a fixed set of PowerShell scripts, each of which:
1. Validates all inputs against strict patterns
2. Constructs a read-only remote command from validated components
3. Checks the constructed command against a whitelist pattern AND a danger-fragment blacklist
4. Executes via a controlled SSH helper
5. Logs the action to an audit trail

## Implementation

### 1. Allowlist Script Model

The AI can only execute 9 specific `.ps1` scripts. Each script:
- Accepts named parameters (`-Target`, `-Source`, `-File`, `-Keyword`)
- Validates every parameter with `Assert-Safe*` functions
- Constructs a remote command from safe building blocks
- Passes it through `Assert-RemoteReadCommand` before execution

There is no generic "run this command on the server" path.

### 2. Remote Command Fence (Assert-RemoteReadCommand)

Every constructed remote command must pass three checks:

1. **Single-line only** — newlines rejected (prevents injection via line breaks)
2. **Whitelist pattern match** — must start with `cd -- /safe/path &&` or `docker exec container /bin/sh -lc` or `docker ps/inspect`
3. **Path traversal rejection** — `..` anywhere in the command is rejected
4. **Danger fragment scan** — 30+ dangerous substrings (rm, mv, chmod, curl, wget, kill, systemctl, etc.) rejected case-insensitively

### 3. Input Validation Layer

- `Assert-SafeName`: only `[A-Za-z0-9_.-]` for targets, accounts, sources, containers
- `Assert-SafeAbsDir`: must be absolute, no `..`, no `\\`, no `//`
- `Assert-SafeRelDir`: must be relative, no `..`, no leading `/`
- `Assert-SafeLogFile`: simple filename only, no path separators
- `Assert-Tail`: hard limit 5000
- `Assert-MaxMatches`: hard limit 1000
- `Assert-Keyword`: max 200 chars, no shell metacharacters

### 4. Permission Model

Each SSH account has explicit permissions:
- `permissions.hostDir`: can read host directory logs
- `permissions.docker`: can read docker container logs

A source of type `docker` requires `docker` permission. A source of type `host_dir` requires `hostDir` permission. Missing permission = immediate rejection.

### 5. Audit Trail

Every remote read operation is logged to `logs/server-access-YYYY-MM-DD.jsonl`:
- Timestamp, account, host (redacted in output), command type, full remote command
- 7-day automatic rotation

### 6. Credential Protection

- `targets.local.json` never committed to Git
- Output never contains real host, SSH user, key path, or password
- AI only sees target/account/source aliases

## What Was Deliberately Removed

- **Step-by-step flow instructions**: model knows to list targets before reading files
- **Command templates**: model can infer from script parameters
- **Parameter documentation**: scripts already enforce via Assert-*
- **Error code reference**: script JSON output is self-describing
- **Platform config** (openai.yaml): obsolete

## Vulnerabilities Fixed by Tests

The test suite (`test_command_safety.py`) exposed and validated fixes for:
- Docker exec commands with danger keywords after opening quote (`'rm`, `'curl`)
- Path traversal via `..` in whitelist-matched paths

## File Structure

```
server-docker-logs-readonly/
├── SKILL.md                    # Fence rules + script entry (~45 lines)
├── DESIGN.md                   # This file
├── DESIGN_cn.md                # Chinese version
└── scripts/
    ├── common.ps1              # All fence logic (whitelist, blacklist, validation, audit)
    ├── ssh_run.py              # SSH execution helper (controlled by common.ps1)
    ├── list-targets.ps1        # Allowlisted entry scripts
    ├── list-accounts.ps1
    ├── list-sources.ps1
    ├── list-log-files.ps1
    ├── get-log-file.ps1
    ├── search-logs.ps1
    ├── recent-errors.ps1
    ├── list-containers.ps1
    ├── get-container-info.ps1
    ├── test_command_safety.py  # Safety tests
    └── targets.local.json      # Local config (not in Git)
```
