---
name: review-crew
description: Run a panel of reviewers over a slice of work — a local diff or a GitHub PR by link — one general code reviewer, then a chosen subset of specialists (test, code, database, security, design/UI, infra) in parallel, then an intent advocate — adversarially verify every finding, fix what survives (local mode), and run the project's gates. Use when the user asks to "review this slice", "run the crew", "review before I commit", "review this PR", pastes a GitHub PR link, or runs /review-crew. Runs in parallel on Claude Code and sequentially on Cursor. Not a linter and not a bug hunt on its own; it is the gate a slice of work passes through before a human reads it.
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

1. `$ARGUMENTS` names a GitHub PR (a PR URL, or `--pr <number>`) → **PR mode**,
   below.
2. `$ARGUMENTS` names a range or path → use it (`/review-crew HEAD~3..HEAD`)
3. Staged changes exist (`git diff --cached --stat`) → review those
4. On a feature branch with commits ahead of the default branch → review
   `<default>...HEAD`
5. Otherwise → uncommitted working-tree changes

Say which you picked in one line. If the scope is empty, stop and say so — do not
review a clean tree.

**PR mode.** A PR under review — someone else's, or your own already pushed —
gets isolated the same way this skill already isolates everything else: never
in the directory the user is sitting in.

```bash
gh pr view <num> --repo <owner/repo> --json title,body,baseRefName,headRefName,url
git worktree add <tmp-dir> <baseRefName>
cd <tmp-dir> && gh pr checkout <num> --repo <owner/repo>
```

From here `<tmp-dir>` *is* `repo` for every step below. Step 1's diff command
doesn't apply — there is no working-tree diff, the PR's changes are already
committed on its branch — use `git -C <repo> diff <baseRefName>...HEAD -- . ':(exclude).review-crew-run'`
instead; everything else in step 1 (copying personas, assembling the packet) is
identical. The PR's title and body become the task the intent advocate checks
the diff against.

PR mode changes step 5 and step 7 — read those before running one. Remove the
worktree in step 7, success or failure; it must not linger in
`git worktree list`.

**Depth.** `quick` is the right default for most slices: it batches
verification per persona instead of spawning one verifier per finding, which is
where most of the agent count goes. Reserve `deep` for schema, auth or anything
where being wrong is expensive to undo. Read from `$ARGUMENTS` (`--depth quick|standard|deep|max`), default
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
git -C <repo> diff -- . ':(exclude).review-crew-run' > <repo>/.review-crew-run/slice.diff
```

Use `git add -N` deliberately: a new file is invisible to `git diff` until git
knows it is intended, and a review that silently skips every added file is worse
than no review.

Exclude `.review-crew-run` from that diff just as deliberately. `git add -N .`
marks the staging directory intent-to-add too, so without the pathspec the nine
persona briefs land in the diff and every reviewer reads its own instructions as
part of the code under review — which is both noise and a way to confuse a
reviewer about what it is looking at.

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

**No `Workflow` tool available (e.g. running under Cursor)?** Run the same
sequencing yourself, in this session, one persona at a time: read
`<repo>/.review-crew-run/personas/<name>.md`, then the packet and the diff,
then record that persona's findings before moving to the next. You lose the
parallelism — specialists that would fan out together now run one after
another — but not the rigor: same personas, same order, same packet, and
nothing gets fixed between stages, for the same reason it doesn't in the
`Workflow` version. Verification (step 3) works the same way: read
`personas/verifier.md` and adversarially re-examine each finding yourself,
defaulting to refuted when you cannot confirm it against the actual code.

Sequencing, which is deliberate:

1. **The general reviewer runs first, alone.** Broad quality pass — placement,
   DRY/YAGNI, idioms, error handling, naming, dead code.
2. **The selected specialists run in parallel**, over *the same snapshot* the
   general reviewer saw. Nothing is fixed in between. If code changed between
   stages, no finding would be reproducible against the diff the user actually
   wrote.

   **Choose them; do not run all six.** Pass `specialists` in `args` — the
   default is `['security', 'infra']`. Measured across a long run of reviews,
   `general` and `intent` produced almost every confirmed finding while `test`,
   `code` and `database` returned empty far more often than not, and running the
   full set costs six agents plus a verifier per finding they raise. Pick by what
   the slice touches: `security` for auth, crypto or an upload path, `database`
   for migrations and constraints, `infra` for CI and containers, `design` for
   UI, `test` when the tests themselves are the deliverable. `specialists: []`
   runs general and intent alone.
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

**PR mode does not fix.** You do not have standing to change a branch that
isn't yours without being asked — not even a good fix. Findings become review
comments (step 7), not commits. Skip to step 6.

**You apply the fixes, not the subagents.** Parallel agents editing the same
files collide, and a single commit needs one coherent narrative.

Apply in severity order. After each `BLOCKING` fix, re-run the specific test that
covers it if one exists. If a fix requires a design decision the user has not
made, stop and ask — do not guess and note it.

If a finding is genuinely correct but you choose not to fix it, that is a
legitimate outcome. Record it in the summary with the reason.

### Step 6 — Gates

Run every gate found in step 0 inside `<repo>`. All must pass.

**Local mode:** a failing gate after fixes means a fix broke something.
Diagnose it — do not re-run hoping for a different result, and do not weaken a
test to make it pass. If you cannot resolve it, revert that specific fix,
report the finding as unfixed, and say why.

**PR mode:** you didn't fix anything, so a failing gate is a finding, not
something to chase down. Report it in the review comment (step 7) the same way
you'd report any other finding — it's information for the author, not yours to
resolve.

**Report gate output faithfully.** If tests fail, say so with the output.

### Step 7 — Clean up, and stop

**Local mode.** Remove `<repo>/.review-crew-run/` first — it is scaffolding,
not work product, and it must not reach the staged diff. Then `git add` the
changes. **Do not commit and never push.** Write the suggested commit message
to `.git/REVIEW_CREW_MSG` so the user can `git commit -F .git/REVIEW_CREW_MSG`
if they want it. Follow the repo's existing commit style — read `git log` and
match it.

**PR mode.** There is nothing to stage — step 5 skipped fixing on purpose.
Instead, draft the review as a GitHub PR comment: adjudicated findings, ranked
by severity, in the same voice you'd use reporting to a human. Write it
*outside* the worktree (which is about to be removed), e.g.
`review-crew-pr-<num>.md` in the directory you started from, and hand back the
exact command:

```bash
gh pr review <num> --repo <owner/repo> --comment --body-file review-crew-pr-<num>.md
```

**Never run that command yourself.** Posting to someone else's PR is visible to
them and to everyone watching the repo — the same reason this skill never
pushes. Draft it, hand back the command, stop. Then remove the worktree:
`git worktree remove <tmp-dir>` — do this even if the run failed partway.

Then report (both modes):

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
- **Never commit, never push.** Stage and stop (local mode).
- **PR mode never fixes and never posts.** It drafts a review comment and hands
  back the `gh pr review` command — the same reason it never pushes. Remove the
  worktree when done, success or failure.
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
