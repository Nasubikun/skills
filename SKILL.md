---
name: cursor-impl
description: Delegates implementation to parallel Cursor composer workers (headless cursor CLI). Decomposes an approved plan into disjoint tasks, dispatches workers, reviews results, and integrates. Invoke with /cursor-impl after a plan is approved.
disable-model-invocation: true
---

# cursor-impl — Parallel delegation to Cursor composer

Act as the orchestrator: decompose, dispatch, review, integrate. Workers write
the implementation.

- Run: `${CLAUDE_SKILL_DIR}/scripts/run-cursor.sh <run|fix> <task-dir>`
- Brief format: [references/brief-template.md](references/brief-template.md)
- The script sets the model (override via `CURSOR_MODEL`); do not pass one.
- Task artifacts live in `.claude/cursor-impl/<slug>/task-<n>/` in the target
  repo. The script keeps this path out of git.

## Workflow

Copy this checklist and track progress:

```
- [ ] 1. Preflight
- [ ] 2. Decompose into tasks
- [ ] 3. Write briefs
- [ ] 4. Dispatch in parallel
- [ ] 5. Review each task
- [ ] 6. Integrate
```

### 1. Preflight

- Require a clean working tree (`git status --short`). If dirty, ask the user.
- Identify the project's lint / typecheck / test commands. Briefs may only
  reference commands that exist.

### 2. Decompose into tasks

Delegate only high-output, low-judgment work:

| Delegate | Write yourself |
|---|---|
| Vertical slices of mostly new files | Surgical edits to existing code |
| Propagating a reference implementation pattern | Changes dominated by design decisions |
| Mass-producing tests / scaffolding | Shared glue |

If the brief would be longer than the expected diff, do not delegate.

Rules:

- Slice vertically, never by layer (types/API/UI).
- Give each task a manifest of owned files. Manifests must be disjoint;
  otherwise re-split or serialize.
- Exclude shared glue (union types, index/barrel registrations, constant maps,
  lockfiles, generated files) from every task; write it yourself.
- Put dependent tasks in later waves. Size each wave to what you can review
  immediately on completion.
- For pattern propagation, implement the first instance yourself and cite it
  as the reference implementation.
- Do not delegate tasks that need their own dev server or test run; if
  unavoidable, use worktree isolation (`agent -w`).

### 3. Write briefs

Write `.claude/cursor-impl/<slug>/task-<n>/brief.md` per
[references/brief-template.md](references/brief-template.md).

- Keep the touchpoint map coarse: file level plus a reference implementation
  for new files; `file:line` only when delegating edits to existing code.
- Quote only the relevant sections of specs.

### 4. Dispatch in parallel

From the target repo root, launch each task as a separate Bash call with
`run_in_background: true`:

```bash
${CLAUDE_SKILL_DIR}/scripts/run-cursor.sh run .claude/cursor-impl/<slug>/task-1
```

- One task per Bash call; a single block runs commands sequentially.
- Wait for completion notifications. Do not poll; silence is normal
  (runs can take ~15 minutes).
- Results land in `task-<n>/result.json` (status / session_id / report /
  usage).

### 5. Review each task

Verify independently; do not trust the worker's report:

1. Check `git status --short` / `git diff --stat` against the task manifest;
   revert out-of-scope changes.
2. Run lint / typecheck / test yourself.
3. Read every changed file in full, focusing on boundaries (authorization,
   sanitization, shared-type consistency).

Give a three-valued verdict:

- **approve** — move on.
- **nits** — fix them yourself on the spot.
- **blocking** — write all findings into `task-<n>/feedback.md` as one batch,
  then:

  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/run-cursor.sh fix .claude/cursor-impl/<slug>/task-1
  ```

At most 3 fix rounds per task. If findings are not shrinking, stop and take
the task over yourself or report to the user.

### 6. Integrate

1. Write the shared glue.
2. Run lockfile updates / codegen once, if needed.
3. Run project-wide lint / typecheck / test.
4. Include each task's usage in the final report.

## Troubleshooting

- status=failed: check the tail of `task-<n>/stderr-<iter>.log` and
  `stream-<iter>.log`.
- To observe a running task (e.g. when the user asks for progress), tail
  `task-<n>/stream-<iter>.log`.
