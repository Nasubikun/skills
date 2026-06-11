# Brief template

Fill in `{...}` and save as `.claude/cursor-impl/<slug>/task-<n>/brief.md`.
Every section is required; write "None" where a section is empty.

---

```markdown
# Task {n}: {one-line title}

## Context

You are one worker on a parallel implementation team. Other workers are
implementing other areas at the same time. Your assignment is limited to this
brief. The orchestrator reviews and integrates all results afterwards.

## Fixed specification (hard constraints)

{Bullet points. Leave no room for interpretation. Quote only the relevant
sections of any spec document.}

## Touchpoint map

- `{file}:{line}` — {what to change}
- `{file}` (new) — {what to create}

## Reference implementation (imitate this)

{Existing file or directory to follow for structure, naming, and patterns}

## Owned files (change nothing else)

- `{file}`

## Out of scope (read-only)

{Shared glue, lockfiles, generated files, other workers' areas. "Everything
outside the owned files" plus anything that deserves explicit mention.}

## Verification (run before finishing)

- `{command}` → {expected result}

## Rules

- Modify only the owned files. If an out-of-scope change turns out to be
  needed, do not make it; note it in your report.
- Do not revert other workers' changes or existing uncommitted changes.
- Do not run git commit or push.
- Do not run commands that rewrite lockfiles or generated files
  (installs, codegen); note the need in your report instead.
- In your final report, state any spec items you could not meet and any
  out-of-scope changes you found to be needed.
```
