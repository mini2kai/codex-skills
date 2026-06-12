# Native Git Fallback After Git Skill Failure

[中文版](./2026-06-11-git-skill-failure-native-fallback_cn.md)

## What Happened

work-orchestrator correctly routed AI branch creation to `git-trunk-workflow`, but after the script failed, the AI did not stop and report the failure. It manually ran `git fetch origin && git checkout -b ...` to continue branch creation.

## Root Cause

1. work-orchestrator said Git operations must use the Git skill when available, but did not explicitly say that a failed Git skill script forbids native fallback commands.
2. `create_ai_branch.ps1` returned a plain error only; it did not include a machine-readable blocked-next-step signal.
3. The model interpreted the script failure as a tool or parameter issue and tried to repair it with familiar Git commands.

## Impact

- The operation bypassed `git-trunk-workflow` audit logging and branch-existence checks.
- Branch creation effectively had two paths: scripted and native, weakening the fence model.
- The user had to repeatedly correct “do not bypass the script.”

## Lessons

1. **A professional script failure is a fence result, not permission to bypass.**
2. **Failure responses need next steps, not just errors.** AI is more likely to follow an explicit blocked next step.
3. **The orchestrator must distinguish missing skills from skill blocks.** Missing skills can request a temporary native-command fallback; blocked skills must fix the cause and rerun the script.

## Fence Implementation

Completed:

- `create_ai_branch.ps1` failure responses now include `native_git_fallback_forbidden` and `blocked_next_step`.
- Local/remote existing-branch errors explicitly forbid `git checkout -b` / `git switch -c` fallback.
- `work-orchestrator` now states that professional skill script failures block native fallback commands.
- `test_git_safety.py` includes a regression check so the failure-block fields are not removed silently.
