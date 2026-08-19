---
name: review-crew
description: Run a panel of specialist reviewers over a slice of work — one general code reviewer, then six specialists (test, code, database, security, design/UI, infra) in parallel, then an intent advocate — adversarially verify every finding, fix what survives, and run the project's gates. Use when the user asks to "review this slice", "run the crew", "review before I commit", or runs /review-crew. Not a linter and not a bug hunt on its own; it is the gate a slice of work passes through before a human reads it.
metadata:
  author: Nelson Boralli Neto
  version: "1.0.0"
---

# Review Crew

A slice of work is not done when the code is written. It is done when the code
has been written, reviewed from every angle that matters, had its findings
*challenged*, been fixed, and passed the project's own gates.

This skill runs that whole loop as one operation and hands back a staged,
verified diff.

## What makes this different from just asking for a review

**Findings are adversarially verified before they become work.** A reviewer that
produces twelve findings, three of which are real, has not saved anyone time — it
has moved the work from finding problems to triaging noise. Every finding here
goes to a verifier prompted to *refute* it, defaulting to refuted when uncertain.
Only survivors become tasks.

**One slice, one commit.** Eight reviewers do not produce eight commits. The
whole slice — your code plus everything the review changed — lands as a single
reviewable unit. The skill stages it and stops; committing is the human's call.

---

## Process

### Step 0 — Resolve scope, depth, and gates

**Scope.** In order of preference:

1. `$ARGUMENTS` names a range or path → use it (`/review-crew HEAD~3..HEAD`)
2. Staged changes exist (`git diff --cached --stat`) → review those
3. On a feature branch with commits ahead of the default branch → review
   `<default>...HEAD`
4. Otherwise → uncommitted working-tree changes

Say which you picked in one line. If the scope is empty, stop and say so — do not
review a clean tree.

**Depth.** Read from `$ARGUMENTS` (`--depth quick|standard|deep|max`), default
`standard`:

| Depth | General | Specialists | Verify | Intent | Verification |
|---|---|---|---|---|---|
| `quick` | sonnet / medium | sonnet / low | sonnet / medium | sonnet / medium | batched per persona |
| `standard` | opus / medium | sonnet / medium | opus / high | opus / medium | per finding |
| `deep` | opus / high | sonnet / high | opus / xhigh | opus / high | per finding |
| `max` | opus / xhigh | opus / high | opus / max | opus / xhigh | per finding, 3 verifiers |

`--model` and `--effort` override the whole table uniformly if the user wants a
flat run.

**Gates.** Detect the project's own commands — do not guess. Look in
`package.json` scripts, `Makefile`, `justfile`, `pyproject.toml`, `Cargo.toml`,
or a conventions doc (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`). You want the
test command, the typecheck command, and the lint command if they exist. If you
cannot find them, ask once rather than inventing them.

### Step 1 — Stage the run, then build the review packet

**Everything a reviewer reads must live inside the repo being reviewed.** This
is not a preference; it is what makes the run work at all.

A background subagent cannot answer a permission prompt. Point one at a path
outside the project — this skill's own `personas/` directory, a diff in `/tmp`,
anything under `~` — and it stalls on its first read having produced nothing,
while the user gets prompts they did not ask for. Two reviewers were lost to
exactly this the first time this skill ran.

So before spawning anything:

```bash
mkdir -p <repo>/.review-crew-run/personas
cp <skill-dir>/personas/*.md <repo>/.review-crew-run/personas/
git -C <repo> add -N .            # so untracked files appear in the diff
git -C <repo> diff > <repo>/.review-crew-run/slice.diff
```

Use `git add -N` deliberately: a new file is invisible to `git diff` until git
knows it is intended, and a review that silently skips every added file is worse
than no review.

Delete `.review-crew-run/` in step 7, before staging. The skill's promise is that
nothing it writes into the target repo survives the run.

Every reviewer sees the same thing, so assemble it once:

- The diff for the resolved scope
- The list of changed files with line counts
- The project's conventions doc, if one exists
- The stack facts a reviewer needs to be concrete rather than generic: language,
  test framework, DB and migration tool, frontend framework, deploy target
- **The task the slice was meant to accomplish**, in the user's own words where
  available. The intent advocate cannot work without this.

Keep it factual. Do not summarize the diff — reviewers read the code.

### Step 2 — Run the crew

**This is a `Workflow` call.** These instructions are the opt-in; use
`workflow.js` in this skill directory as the script, passing the packet and the
resolved depth as `args`.

Sequencing, which is deliberate:

1. **The general reviewer runs first, alone.** Broad quality pass — placement,
   DRY/YAGNI, idioms, error handling, naming, dead code.
2. **The six specialists run in parallel**, over *the same snapshot* the general
   reviewer saw. Nothing is fixed in between. If code changed between stages, no
   finding would be reproducible against the diff the user actually wrote.
3. **The intent advocate runs last**, over the diff *and* the original task.

Every reviewer returns structured findings. A reviewer with nothing to say
returns an empty list — say so plainly rather than manufacturing a finding to
look useful. **A persona that reports "no findings" is a successful run.**

### Step 3 — Verify

Each finding goes to a verifier told to refute it. The verifier reads the actual
code, not the finding's description of it. It defaults to `refuted: true` when
uncertain. At `max` depth, three verifiers vote and a finding survives on a
majority.

Verifiers kill three things reliably, and all three are common:
- Findings about code the reviewer misread
- Findings that are true but already handled elsewhere in the file
- Findings that restate a deliberate decision the code comments explain

### Step 4 — Adjudicate, and apply your own judgement

Dedupe across personas — the same issue found by security and by database is one
finding, not two. Rank by severity: `BLOCKING`, `SHOULD-FIX`, `NIT`.

**Then read them yourself.** You are the last filter, and this step is not
optional. A verified finding can still be wrong, out of scope for this slice, or
correct-but-not-ours. Push back in the summary where you disagree, and say why.
Never apply a fix you cannot independently justify — "a reviewer said so" is not
a reason to change code.

Watch specifically for:
- **A finding that would break something the tests do not cover.** Trace it.
- **A fix that belongs to a later slice.** Note it; do not do it.
- **A pre-existing issue the diff merely touched.** Flag separately; it is not
  this slice's job, and quietly fixing it makes the diff harder to review.

### Step 5 — Fix

**You apply the fixes, not the subagents.** Parallel agents editing the same
files collide, and a single commit needs one coherent narrative.

Apply in severity order. After each `BLOCKING` fix, re-run the specific test that
covers it if one exists. If a fix requires a design decision the user has not
made, stop and ask — do not guess and note it.

If a finding is genuinely correct but you choose not to fix it, that is a
legitimate outcome. Record it in the summary with the reason.

### Step 6 — Gates

Run every gate found in step 0. All must pass.

A failing gate after fixes means a fix broke something. Diagnose it — do not
re-run hoping for a different result, and do not weaken a test to make it pass.
If you cannot resolve it, revert that specific fix, report the finding as
unfixed, and say why.

**Report gate output faithfully.** If tests fail, say so with the output.

### Step 7 — Clean up, stage, and stop

Remove `<repo>/.review-crew-run/` first — it is scaffolding, not work product,
and it must not reach the staged diff.

Then `git add` the changes. **Do not commit and never push.**

Write the suggested commit message to `.git/REVIEW_CREW_MSG` so the user can
`git commit -F .git/REVIEW_CREW_MSG` if they want it. Follow the repo's existing
commit style — read `git log` and match it.

Then report:

```
Scope     <what was reviewed> (N files, +X/-Y)
Depth     standard
Crew      8 reviewers → 14 findings
Verified  9 confirmed, 5 refuted
Applied   7 fixed, 2 declined (reasons below)
Gates     ✓ 927 tests  ✓ typecheck  ✓ lint
Staged    not committed
```

Then the findings that mattered, what you changed, what you declined and why, and
anything you noticed that belongs in a later slice.

---

## Rules

- **Never point a reviewer outside the repo.** A background agent cannot answer
  a permission prompt; it hangs silently and the user gets prompts instead of a
  review. Stage what they need inside the working directory (step 1).
- **Never commit, never push.** Stage and stop.
- **Never weaken a test to make a gate pass.**
- **Never fix a pre-existing problem silently.** Flag it; it is not this slice.
- **A refuted finding is a good outcome**, not a failed review. Report the count.
- **Report honestly.** If gates fail or a fix was skipped, say so plainly.
- **The user's decisions outrank a persona's opinion.** If the code does
  something deliberately and a comment or the task says why, a reviewer
  disagreeing is a note, not a defect.

## Files

| File | Purpose |
|---|---|
| `workflow.js` | The orchestration script passed to `Workflow` |
| `personas/general.md` | Base code reviewer — runs first, alone |
| `personas/test.md` | Test coverage and assertion quality |
| `personas/code.md` | Senior engineer — design, placement, idioms |
| `personas/database.md` | Schema, migrations, queries, constraints |
| `personas/security.md` | Authz, injection, secrets, data exposure |
| `personas/design.md` | UI, UX, accessibility |
| `personas/infra.md` | Build, deploy, CI, config, runtime |
| `personas/intent.md` | Does this match the ask — runs last |
| `personas/verifier.md` | The adversarial refuter |
