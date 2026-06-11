# git-trunk-workflow: Protected Branches as Code, Not Trust

[中文版](./DESIGN_cn.md)

## Problem

AI Agents doing Git operations is useful but dangerous. A single `git push --force` or accidental merge to main can destroy work. Prompting "don't force push" is unreliable — as demonstrated in this repository's own incident log.

## Design Philosophy

**Protected branches, safe staging, and push restrictions are enforced by script logic. AI cannot bypass them regardless of what it's told to do.**

The AI has full freedom to decide *what* to commit and *how* to describe it, but the scripts physically prevent it from pushing to protected branches, force pushing, or staging everything blindly.

## Implementation

### 1. Protected Branch Registry

`Test-ProtectedBranch` in `git_common.ps1` maintains a hardcoded list:
- Named: main, master, dev, uat, prod, production, staging
- Prefixed: release/*, hotfix/*

Any script that would modify these branches checks this function first and exits on match.

### 2. Push Restriction

`push_ai_branch.ps1` enforces two checks before push:
1. Current branch must start with `ai/` (`Test-AiBranchCurrent`)
2. Current branch must NOT be protected (`Test-ProtectedBranch`)

Only `git push -u origin <current-ai-branch>` is executed. No `--force`, no alternative remote refs.

### 3. Stage Path Validation

`stage_paths.ps1` rejects:
- `.`, `*`, `:/`, `--all`, `-A`, `-u` (bulk staging)
- Any path containing wildcards
- Empty paths

Only explicit file paths are accepted. This prevents "git add everything" scenarios where unrelated or sensitive files get committed.

### 4. Branch Name Enforcement

`Test-AiBranchName` requires the pattern: `ai/<source>/<YYYYMMDD>-<type>-<topic>`

This ensures every AI branch is traceable to its source, date, and purpose.

### 5. Safe Sync Only

`create_ai_branch.ps1` only syncs via `git pull --ff-only`. If fast-forward fails (diverged history), the script stops. No automatic merge, no automatic rebase.

### 6. Git State Guard

`Assert-NoGitOperationInProgress` checks for MERGE_HEAD, REBASE_HEAD, CHERRY_PICK_HEAD, and rebase directories. If any exist, all operations are refused until the user resolves the state.

### 7. Commit on Protected Branch Rejected

`commit_cn.ps1` calls `Assert-NotProtectedBranch` before committing. Even if AI somehow stages files on a protected branch, the commit itself is blocked.

### 8. File Existence Validation Before Staging

`stage_paths.ps1` cross-checks every requested path against `git status` output. If a path has no changes (typo, wrong path, already committed), staging is refused with an explicit error listing the missing paths.

### 9. Audit Trail

All git operations (create branch, stage, commit, push, handoff summary) are logged to `logs/git-ops-YYYY-MM-DD.jsonl` with 7-day rotation. Audit records include timestamp, event type, branch, commit hash, and affected files.

### 10. Source Branch Staleness Detection

`git_handoff_summary.ps1` reports how many commits the source branch is ahead of the current AI branch. If source moved forward during development, the handoff explicitly warns about potential merge conflicts.

### 11. Push Failure Guidance

When `push_ai_branch.ps1` fails due to proxy/network issues, it outputs a `next_action` with a bypass command (`git -c http.proxy="" push`) instead of just an error message.

## What Was Deliberately Removed

- **10-step workflow documentation**: model knows Git flow
- **Commit message templates**: model writes Chinese naturally
- **Merge/backport strategy guide**: model can assess based on context
- **Validation checklist format**: model decides what to verify
- **Branch lifecycle management details**: model can suggest cleanup
- **Platform config** (openai.yaml): obsolete

## File Structure

```
git-trunk-workflow/
├── SKILL.md                     # Fence rules + script entry (~45 lines)
├── DESIGN.md                    # This file
├── DESIGN_cn.md                 # Chinese version
└── scripts/
    ├── git_common.ps1           # All fence logic (protected branches, validation)
    ├── git_preflight.ps1        # Read-only repo state check
    ├── create_ai_branch.ps1     # Safe branch creation with ff-only sync
    ├── stage_paths.ps1          # Explicit-path-only staging
    ├── commit_cn.ps1            # Chinese commit helper
    ├── push_ai_branch.ps1       # ai/* only push, no force
    ├── git_handoff_summary.ps1  # Handoff facts collection
    └── test_git_safety.py       # Safety tests
```
