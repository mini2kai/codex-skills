# Principles

[中文版](./principles_cn.md)

These 5 principles are distilled from real AI collaboration scenarios. They don't depend on any specific platform or model — whether you use Codex, Claude, GPT, or whatever comes next, these constraint patterns apply.

---

## 1. Read-only by default; write operations require explicit authorization

An AI Agent's default action should be "observe," not "modify."

Reading code, reading logs, reading databases, reading documents — all fine at any time. But writing code, changing config, executing SQL, pushing code — each requires explicit human approval.

Not because AI will get it wrong. Because even when it gets it right, if it's not what you intended, the cost of reversal far exceeds the cost of confirmation.

**Implementation patterns:**
- Database connections default to SELECT/WITH/SHOW/EXPLAIN only
- DDL/DML generates SQL text only, never executes
- Git operations: commit and push confirmed separately
- File modifications: show diff or plan before applying

---

## 2. High-risk operations are not banned — they require confirmation gates

"Forbid AI from doing X" is the simplest safety strategy, but also the crudest.

The useful model is: AI can do anything, but the higher the danger, the higher the confirmation threshold. Routine operations pass silently; high-risk operations require human review before proceeding.

Gates are not friction — they're intervention points.

**Risk tiers:**
- No gate: read code, read logs, read docs, generate plans
- Light confirmation: modify code files, generate commits
- Heavy confirmation: push to remote, execute database writes, merge branches
- Forbidden: force push, reset --hard, delete branches/tags, write directly to production

---

## 3. AI should prove it understands the problem before being allowed to act

Most AI collaboration incidents aren't "AI wrote wrong code" — they're "AI solved a problem that doesn't exist."

Require AI to output its understanding first — what's the problem, what's the root cause hypothesis, what will change, what won't — then authorize execution only after human confirms the understanding is correct.

This doesn't slow things down. An AI with correct understanding gets it right in one pass; an AI with wrong understanding fails in three.

**Implementation patterns:**
- Phase gates in orchestration: Intake → Evidence → Plan → (authorize) → Execute → Verify
- Plan phase must stop and output proposal, awaiting human confirmation
- When evidence is insufficient, no definitive conclusions — mark as "to be verified"
- "What won't change" is as important as "what will change" in the proposal

---

## 4. Safety rules travel with the task, not as global switches

"AI cannot access servers" is a global policy. But the real requirement is "AI can read logs, but cannot execute commands."

Bind safety rules at task granularity, not as global blankets. Different tasks have different trust boundaries; the same AI in different contexts should have different permissions.

**Implementation patterns:**
- Server logs: only via allowlist scripts, no SSH shell access
- Database: permissions per profile; production profiles always read-only
- Git: daily work can commit, but push to main requires extra confirmation
- File system: skill-bundled scripts can execute; arbitrary commands cannot

---

## 5. Credentials and local state never enter AI's persistent context

AI Agent conversation history, memory, logs, output files — anywhere that might be persisted should never contain:

- Database connection strings or passwords
- SSH keys, tokens, cookies
- Production environment addresses and credentials
- User Excel data, customer information

Temporary use is fine — passing a connection string for a one-time query is OK. But that information should not be remembered, written to files, committed to Git, or appear in the next conversation.

**Implementation patterns:**
- Local config files use `.local.json` suffix, excluded in .gitignore
- Passwords referenced via environment variables (`passwordEnv`), never plaintext in config
- AI-generated Excel/logs/preview files never committed to Git
- Temporary connection info discarded after use, not written to persistent profiles
