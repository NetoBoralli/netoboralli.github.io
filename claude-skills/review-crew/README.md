# review-crew

A review gate for a slice of work: one general reviewer, six specialists, an
intent advocate, and an adversarial verifier that kills the findings which do not
survive contact with the actual code.

## Install

Claude Code: copy this folder to `~/.claude/skills/review-crew` (every project)
or `<repo>/.claude/skills/review-crew` (that repo only). Cursor: same folder,
`~/.cursor/skills/review-crew` or `<repo>/.cursor/skills/review-crew`. Nothing
else to configure — the skill writes nothing into the repo it reviews, other
than a worktree it removes itself (PR mode, below).

## Use

```bash
/review-crew                      # standard depth, scope auto-detected
/review-crew --depth deep
/review-crew --depth quick
/review-crew HEAD~3..HEAD         # explicit range
/review-crew --pr 482             # review a GitHub PR by number
/review-crew --pr https://github.com/org/repo/pull/482
/review-crew --model opus --effort high    # flat override, ignores the tiers
```

Scope resolves in this order: a PR link or number, then an explicit argument,
then staged changes, then the branch against its default branch, then the
working tree. It says which it picked.

## Claude Code and Cursor

The specialist sweep fans out in parallel using Claude Code's `Workflow` tool.
Cursor has no equivalent, so under Cursor the same personas run one after
another in a single session instead — slower, same coverage, nothing to
configure either way.

## PR mode

Reviewing a PR by link — someone else's, or your own already pushed — checks it
out into an isolated `git worktree`, never your current working directory, and
runs the same crew against it there.

It never fixes and never posts. Findings become a drafted review comment
written next to your repo, plus the exact `gh pr review --comment
--body-file ...` command to publish it. Posting to someone else's PR is visible
to them and to everyone watching the repo, so a human decides when that
happens — the same reason this skill never pushes a local fix.

## Depth

Depth sets model and effort per stage rather than one dial for everything —
quality goes where it pays. The general pass and the verifier decide whether the
output is trustworthy; the specialist sweep is broad and shallow.

| Depth | General | Specialists | Verify | Verification |
|---|---|---|---|---|
| `quick` | sonnet / medium | sonnet / low | sonnet / medium | batched per persona |
| `standard` | opus / medium | sonnet / medium | opus / high | per finding |
| `deep` | opus / high | sonnet / high | opus / xhigh | per finding |
| `max` | opus / xhigh | opus / high | opus / max | per finding, 3 votes |

`quick` is for a small slice you mostly trust. `standard` is the default.
`deep` is for anything customer-facing, security-relevant, or hard to reverse.
`max` is for a migration you cannot roll back.

## The crew

| Persona | Owns |
|---|---|
| **general** | Ordinary quality — bugs, placement, DRY, YAGNI, idiom, dead code. Runs first, alone. |
| **test** | Whether tests would fail if the code were wrong. Hunts vacuous assertions first. |
| **code** | Design, invariants, coupling, concurrency, failure modes, blast radius. |
| **database** | Constraints as enforcement, migration safety and reversibility, types, indexes. |
| **security** | Authorization, escalation, injection, output encoding, SSRF, secrets, exposure. |
| **design** | States, feedback, accessibility, meaning not carried by colour, consistency. |
| **infra** | Config completeness, build, resources, deploy order, observability, CI. |
| **intent** | Does this match the task, and can a human review it tomorrow. Runs last. |
| **verifier** | Refutes findings. Defaults to refuted when unsure. |

## Why the verifier exists

A panel of eight reviewers will produce findings that are confidently argued and
wrong: code misread, a case already handled twenty lines up, a deliberate
decision reported as an oversight. Those are indistinguishable from real findings
until someone opens the file.

Every finding is therefore sent to a verifier prompted to refute it, which must
read the code and reconstruct the failure before the finding survives. **A high
refutation rate is the system working.** The count is reported.

## What it does and does not do

It **stages** the result. It does not commit and never pushes — the suggested
message goes to `.git/REVIEW_CREW_MSG` and committing is yours.

In local mode, it fixes what survives verification, in one pass, applied by the
orchestrator rather than by the subagents — parallel agents editing the same
files collide, and a slice should land as one coherent change rather than
eight. PR mode never fixes (see above) — there's no standing to change a
branch that isn't yours.

It runs the project's own gates afterwards and reports the output honestly. It
will not weaken a test to make one pass, and it will not silently fix a
pre-existing problem the diff merely touched — that gets flagged separately,
because a fix nobody asked for makes a diff harder to review.

## One implementation detail that is not optional

Reviewers run as background subagents, and **a background subagent cannot answer
a permission prompt**. Point one at a path outside the repo — this skill's own
`personas/` folder, a diff written to `/tmp`, anything under `~` — and it stalls
on its first read having produced nothing, while you get permission prompts you
did not ask for.

So the skill copies the persona briefs and the diff into
`<repo>/.review-crew-run/` before spawning anything, and deletes that directory
before staging. Everything a reviewer touches is inside the working directory.

This is the first thing that went wrong when the skill was first run: two of
eight reviewers hung silently. If you fork this or write something like it, that
is the trap.

## Tuning

The personas are plain markdown in `personas/`. Edit them. If your project has a
recurring failure mode, add it to the relevant persona as a named thing to hunt —
that is where the value compounds, because a generic reviewer gives generic
findings.
