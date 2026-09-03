---
name: explain-work
description: Run after finishing a task and before opening the PR — reads the diff and the task it was meant to satisfy (pasted from Asana), then reports what changed, why, how it maps to the task's requirements, and the questions a reviewer is likely to ask. A comprehension check for the engineer, not a code review. Use when the user asks to "explain what I did", "check I understand my own change", "sanity check before PR", or runs /explain-work.
metadata:
  author: Nelson Boralli Neto
  version: "1.0.0"
---

# Explain Work

A slice of work is ready for review when the code passes, and when the person
who wrote it can explain it without the chat that produced it.

This skill is not a review. Nothing here blocks a PR, fixes anything, or grades
the work — that's `review-crew`'s job. This one reads the diff and the task,
reports back what it found in plain terms, and hands the engineer a small set
of questions a reviewer is likely to ask. If any land as a surprise, that's the
signal to look again before opening the PR — the skill doesn't decide that for
you.

## Why this exists

A generated PR summary the engineer skims is not knowledge — it's a
description they didn't have to produce themselves. The value here isn't the
explanation; it's finding out, before a human asks, whether the engineer can
give it. So this produces the explanation and then hands it back as questions,
closer to an oral check than a report.

---

## Process

### Step 0 — Resolve scope, and get the task

**Scope.** Same order of preference as `review-crew`: `$ARGUMENTS` range or path
→ staged changes → branch ahead of default → uncommitted working-tree changes.
Say which you picked. If it's empty, stop — there's nothing to explain.

**The task.** There's no Asana access here — the task's title, description and
acceptance criteria arrive pasted, in `$ARGUMENTS` or the message that invoked
this skill. **If they're missing, stop and ask for them rather than guessing
what the task was.** The entire point of this skill is checking the diff
against the task; without the task there's nothing to check against, and an
explanation with no requirement mapping is just a summary — which was
explicitly not the goal.

A bare Asana URL isn't enough — this skill can't fetch it. Ask the engineer to
paste the task's title, description, and acceptance criteria if all they gave
you was a link.

### Step 1 — Read the diff

Get the diff for the resolved scope, the list of changed files, and read the
actual files, not only the diff — the surrounding code is what makes "why"
answerable instead of guessed.

### Step 2 — Explain it

**What changed.** A plain-language walkthrough grouped by concern, the way
you'd explain it out loud to a teammate who hasn't seen the diff — not a
mechanical file-by-file listing.

**Why.** The reasoning behind the non-obvious choices. Where the diff doesn't
make the reasoning legible — no comment, no clear signal — say exactly that
rather than inventing a plausible-sounding rationale. A fabricated "why" is
worse than no "why": the engineer would walk away believing they explained
something they didn't.

**Requirement mapping.** Walk the task's stated requirements and acceptance
criteria one by one: `✅ done` / `⚠️ partial` / `❌ missing` / `— n/a`, one line
each, pointing at where in the diff it's satisfied (or noting that nothing
does). Silent scope narrowing — something asked for, not delivered, not
mentioned anywhere — is the single most valuable thing this section can catch,
and the most common thing a rushed PR description omits.

### Step 3 — The check-back

Write 2–4 questions — the sharpest ones a reviewer would actually ask about
*this* diff, not generic ones ("did you test this?"). Concrete to the code: an
edge case the diff doesn't obviously handle, why this approach over an adjacent
one, what happens on a specific input the diff doesn't mention.

This skill does not answer them. It hands them to the engineer to answer
before opening the PR — if one lands as a surprise, that's the finding.

### Step 4 — Report

```
Task      <task title, one line>
Scope     <what was reviewed> (N files, +X/-Y)

## What changed
...

## Why
...

## Requirement mapping
✅ <requirement> — <where>
⚠️ <requirement> — <what's partial>
❌ <requirement> — nothing addresses this
— <requirement> — n/a because <reason>

## Before you open the PR
1. <question>
2. <question>
```

---

## Rules

- **Read-only.** Never modifies code, never stages anything, never touches a
  PR. If something needs fixing, that's `review-crew`, run separately.
- **Never invent a "why."** "Not clear from the diff" is a valid, useful
  answer; a guessed rationale presented as fact is not.
- **Not a review.** No severity, no blocking, no verdict on whether the code is
  good — only whether the engineer can account for what it does.
- **Stop and ask if the task is missing.** Do not explain a diff against a task
  you assumed.
