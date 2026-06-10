# Incident Case Library

[中文版](./README_cn.md)

Records real incidents during skill development and AI collaboration, extracts lessons, and drives fence implementation.

## Document Format

One file per incident. Naming: `YYYY-MM-DD-short-description.md` (English) + `YYYY-MM-DD-short-description_cn.md` (Chinese)

File structure:

```markdown
# Incident Title

## What Happened

Brief description of the incident.

## Root Cause

Why it happened.

## Impact

What consequences resulted.

## Lessons

Principles or criteria derived from this incident.

## Fencing

What code-level checks or blocks did this incident drive? If not yet fenced, explain why and the plan.
```

## Usage

- Record an entry each time a rule is skipped and causes a real problem
- Periodic review: which lessons are still only at the documentation level? Can they be upgraded to code fences?
- design_philosophy.md references this directory as empirical source for principles
