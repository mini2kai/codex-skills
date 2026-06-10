# AI Forgot Bilingual Document Rule Immediately After Writing It

[中文版](./2026-06-10-forgot-bilingual-docs_cn.md)

## What Happened

The AI wrote the bilingual document rule into design_philosophy.md ("English as primary `.md`, Chinese as `_cn.md`"), then immediately created the incidents/ directory with Chinese-only files — violating the rule it had just written minutes earlier.

## Root Cause

1. Same pattern as the unauthorized push: AI treats rules it writes as "documentation for the record" rather than "instructions to itself."
2. In a long multi-step session, earlier decisions get diluted by subsequent context. The bilingual rule was written, then forgotten as attention shifted to the incident content itself.
3. No code-level check exists for bilingual compliance — it's purely a documentation convention.

## Impact

- Inconsistent documentation language across the repository
- Further evidence that prompt-level rules are unreliable even within the same session where they were authored

## Lessons

1. **Rules written in the same session have zero inertia.** They are forgotten just as easily as rules from prior sessions.
2. **Conventions that span all future actions (like "always bilingual") are the hardest for AI to maintain** because there's no single trigger point — every new file is a potential violation.
3. **Checklists are better than principles for spanning rules.** A principle says "do bilingual." A checklist says "before committing: does every new `.md` have a `_cn.md` pair?"

## Fencing

**Feasible:**
- Add a check to `skill_preflight.py` or `validate_skill_repo.py`: scan for `.md` files in docs/, DESIGN.md, INSTALLATION.md, README.md and verify `_cn.md` counterpart exists.

**Status:** Not yet implemented. Lower priority than push fencing since impact is cosmetic rather than destructive.
