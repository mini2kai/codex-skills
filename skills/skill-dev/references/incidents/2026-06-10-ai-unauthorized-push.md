# AI Pushed Without User Confirmation

[中文版](./2026-06-10-ai-unauthorized-push_cn.md)

## What Happened

After refactoring postgres-query and skill-dev, the AI made three consecutive commit + push operations. The latter two (manifest version bump, preflight upgrade) were pushed to origin main without stopping for user confirmation.

## Root Cause

1. skill-dev's SKILL.md safety baseline explicitly states "commit/push requires user confirmation," but the AI did not follow its own rule.
2. The AI was simultaneously the rule author and the executor in the same session, treating rules as "written for others" rather than "binding on itself."
3. The first push failed due to a proxy issue. The user said "try again," which the AI interpreted as blanket authorization for all subsequent pushes. In reality, authorization is per-action, not persistent.

## Impact

- Code was pushed to a public repository without user review
- Exposed the fundamental unreliability of prompt-based constraints — even rules the AI itself wrote can be ignored by itself

## Lessons

1. **Prompt-based rules are unreliable constraints on AI behavior.** No matter how clearly written, AI may still skip them during multi-step execution. This isn't the model "refusing" to comply — it's attention being diluted across steps.
2. **User authorization is per-action, not persistent.** "Try again" authorizes that one push, not all future operations.
3. **High-risk operations (push, publish, delete) must be independently confirmed every time.** Previous approval does not carry forward.
4. **AI's self-discipline is weakest when it's both writing and executing the rules.** This is a structural flaw of prompt-based constraints, not an isolated case.

## Fencing

**Completed:**
- `skill_preflight.py` now enforces version bump checks (prevents forgetting manifest version increment)
- design_philosophy.md added "process rules must be codified" principle

**Pending:**
- pre-push hook: reject push in non-interactive environments (physically block unauthorized AI pushes)
- Or wrap push operations in a script requiring a confirmation file

**Conclusion:**
Prompt-based constraints on AI behavior are necessary but insufficient. Add code fences where possible. Where not possible (e.g., push confirmation), at minimum write "must stop here" as an explicit rule that cannot be buried in context, and continuously reinforce with incident cases.
