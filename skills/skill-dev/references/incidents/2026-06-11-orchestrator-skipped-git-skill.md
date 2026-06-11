# Orchestrator Bypassed Git Skill With Manual Commands

[中文版](./2026-06-11-orchestrator-skipped-git-skill_cn.md)

## What Happened

During a work-orchestrator Execute phase that involved creating a Git branch for code changes, the AI used manual `git switch -c` instead of routing to `git-trunk-workflow` scripts. The git-trunk-workflow skill was available and matched the task, but the AI skipped the routing step entirely.

## Root Cause

1. work-orchestrator's capability routing was purely advisory ("match description, judge if suitable") rather than mandatory.
2. The AI's attention was on the implementation task itself, not on "which skill should I route through."
3. No mechanism distinguished between "use the skill" and "do it yourself" — both paths were equally available.

## Impact

- Git operations executed without git-trunk-workflow's safety fences (protected branch check, audit trail, staging validation)
- The branch was created successfully, but bypassed the designed safety layer

## Lessons

1. **"Dynamic matching" without enforcement is just a suggestion.** When routing depends on AI judgment, it will be skipped under cognitive load.
2. **The fix is not "match better" but "make bypass impossible when skill exists."** If the skill is available, the native command path should be explicitly forbidden.
3. **The rule structure should be: "has skill → must use; no skill → free to act."** This is clear, binary, and doesn't depend on judgment quality.

## Fencing

**Completed:**
- work-orchestrator SKILL.md rewritten: added "不可绕过清单" (non-bypassable list) — when a matching skill is available, native commands are explicitly forbidden
- Rule is now binary: skill available → must use skill. Skill unavailable → free to act with user confirmation.

**Structural limitation:**
- This remains a prompt-level rule. The actual enforcement is downstream — git-trunk-workflow's scripts ARE the code fence. The orchestrator's job is routing to those scripts, and routing cannot be code-enforced in the current architecture.
- The real defense-in-depth is: even if orchestrator routing fails, the git-trunk-workflow scripts themselves prevent the worst outcomes (no force push, no protected branch push) IF they are used.
