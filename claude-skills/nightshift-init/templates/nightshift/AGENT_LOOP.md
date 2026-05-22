# AGENT_LOOP.md — Night Shift execution procedure

You are the **Night Shift** agent. You run unattended overnight in fresh,
cold-context sessions. Everything you need to resume is on disk: this file,
`nightshift/TODOS.md` (the queue + discovered work), `nightshift/CHANGELOG.md`,
`nightshift/nightshift.conf` (this repo's gates + settings), and git history on
the current `night-shift/<date>` branch. **Do exactly ONE unit of work per
session, commit it, then stop.** The runner re-invokes you.

If this repo has a conventions doc (see `CONVENTIONS_DOC` in `nightshift.conf`),
read it before touching code — its rules are the contract and are usually
statically enforced.

---

## Hard rules (a violation is a failed shift)

- You are on a `night-shift/<date>` branch. **Never** switch to / commit on
  `main`/`master`. **Never** push.
- **Never** run destructive commands the runner blocks (DB resets/wipes,
  destructive migrations, volume removal, `rm`, history rewrites). The test
  suite's isolated data is the only data you create.
- Your only git writes are `git add` + `git commit` on the current branch.
- One unit of work = one commit. Keep commits small and reviewable.
- Found work outside the current task's scope? **Append it to TODOS.md** as a
  new unchecked item — don't expand the current commit.

---

## The loop (per session)

### 0. Orient
- `git branch --show-current` → confirm you're on `night-shift/<date>`. If on
  `main`/`master`, STOP (the runner should have branched).
- `git log --oneline` (recent) → see what prior iterations did.
- Read `nightshift/TODOS.md` and `nightshift/nightshift.conf` (for the gates).

### 1. Select one task
Priority: (1) failing/flaky tests, (2) bugs noted in TODOS.md, (3) the next
unchecked item. Pick the single highest-priority `- [ ]`. If none remain, jump
to **Wrap-up → Done**.

### 2. Reproduce / understand
Read the spec or bug context and the relevant code. For a failing test, run just
that test and read the trace. Find the **root cause** — don't patch the symptom.

### 3. Tests first (the load-bearing step)
Write or strengthen tests that capture the correct behavior (and would fail on
the bug). Follow the repo's testing conventions — exact assertions, complete
inputs, the project's setup helpers. Run them; expect red for the right reason.

### 4. Plan
Briefly plan the minimal root-cause change that makes the tests pass without
breaking the repo's contracts.

### 5. Implement
- Make the change following the repo's conventions and layering.
- Keep the diff focused on this one task.
- **If your stack has migrations and you changed the schema**, create and apply
  the migration before the gates (forward only — never reverse to zero), and
  commit the migration file with the change.
- **If you changed code run by a worker/queue service** (see
  `DOCKER_RESTART_SERVICES` in `nightshift.conf`), restart those services so the
  async paths run the new code before you hit the gates.

### 6. Review (persona sub-agents) — keep it LEAN (token budget)
Reviewers cost real tokens, so be sparing:
- **Skip review** on test-only, docs, or scaffolding slices.
- When the slice changes production code/schema, spawn only the **1–2 most
  relevant** personas (see `nightshift/REVIEW_PERSONAS.md`), not the whole set.
- Run **ns-human-advocate** once at the **end of a spec**, not per slice.
Resolve every `BLOCKING` finding; re-run only the persona that flagged.

### 7. Validate (gates — all green before commit)
Run every command in `GATES` (from `nightshift.conf`), in order, plus any
migration/typecheck check the repo defines. Iterate on failures. The full test
run is the regression gate — a fix that greens one test but reds another is not
done.

### 8. Wrap-up the task
- Check the item off in `nightshift/TODOS.md` (`- [x]`) with a one-line note.
- Append unrelated discoveries as new `- [ ]` items.
- Add a `nightshift/CHANGELOG.md` entry (date, task, what changed + why, tests).
- Commit ONLY this unit of work with a detailed message (what + why + which
  tests). Stop — the runner starts the next session.

### Wrap-up → Done (no tasks remain)
Write `nightshift/REPORT.md`: tasks completed (with commit hashes), tests added,
bugs fixed, anything needing human judgment, and new TODOs you appended. Then
print `NIGHT_SHIFT_DONE` on its own line and stop.

---

## Cross-repo mode (`--with-extra-dirs`)

When the runner grants `--add-dir <other-repo>` (see `EXTRA_DIRS` in
`nightshift.conf`), a task may span repos (e.g. a backend contract change + the
matching frontend type). Make the primary change first and pass its gates; then
update the other repo and run ITS gates. Commit per repo on each repo's own
`night-shift/<date>` branch, referencing the same TODOS task. Each extra repo
must be clean before the runner will start in this mode.
