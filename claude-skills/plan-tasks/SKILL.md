---
name: plan-tasks
description: At plan time, before code is written, take an Asana task's title and description (pasted) and break it into a sequenced, reviewable-sized checklist of subtasks — grounded in the actual codebase, not generic — plus the open questions that need a decision before work starts. Meant to seed the team's planning discussion, not replace it. Use when the user asks to "break this task down", "plan this out", "what are the subtasks here", pastes a task to scope, or runs /plan-tasks.
metadata:
  author: Nelson Boralli Neto
  version: "1.0.0"
---

# Plan Tasks

The moment a task gets discussed is the moment ambiguity is cheap to resolve.
Once code exists, every open question becomes a decision someone already made
by accident.

This runs before any code is written. It reads the task, reads the parts of
the codebase it's actually going to touch, and produces two things: the open
questions worth resolving out loud before anyone starts, and a checklist of
subtasks sized to land as individual reviewable slices — ready to paste back
into the Asana task.

It does not decide anything on the engineers' behalf. Ambiguities get
surfaced, not resolved by guessing — the same failure mode the `intent`
persona in `review-crew` polices after the fact; this catches it before the
fact instead.

---

## Process

### Step 0 — Get the task

There's no Asana access here — the task's title, description, and any
acceptance criteria arrive pasted, in `$ARGUMENTS` or the message that invoked
this skill. **If none of that is there, stop and ask for it rather than
inventing a task to plan.**

### Step 1 — Ground it in the codebase

Before proposing anything, find what the task actually touches: grep for the
relevant module or feature area, read how similar work was already built in
this repo (a new county adapter reads the last three; a new API endpoint reads
the sibling endpoints), check the conventions doc if one exists.

Subtasks grounded in real code age better than subtasks grounded only in the
task description — this is what catches "this isn't as simple as it reads"
before anyone commits to an estimate.

### Step 2 — Restate it, then flag the gaps

**Restate the ask** in a line or two, plain enough that if the restatement is
wrong, the mismatch is obvious to whoever reads it — catching a misread before
it costs an implementation.

**Open questions.** Anything the task doesn't specify that would change what
gets built: an unstated edge case, a boundary the task doesn't draw, a
dependency on something not yet decided elsewhere. Rank by how much the answer
would change the shape of the work. A nontrivial task with zero open questions
here is more likely under-examined than genuinely unambiguous — look again
before reporting none.

### Step 3 — The breakdown

A sequenced checklist, each item sized to be one slice of reviewable work —
roughly one PR. Not "implement the feature" as a single line, and not
decomposed down to single-function busywork either.

- State dependencies explicitly (`(after #2)`) rather than implying them by
  list order.
- Word each item so it can be pasted directly into Asana as a subtask — 
  imperative, concrete, no restating the whole task's context.
- Note the file or module an item touches where it isn't obvious — orients
  whoever picks it up later.

### Step 4 — Report, copy-paste ready

```
## What this task is asking for
<restatement, 1-2 lines>

## Open questions (resolve before starting)
1. <question> — <why it changes the shape of the work>

## Subtasks
1. [ ] <concrete, imperative, pasteable subtask>
2. [ ] <subtask> (after #1)
...
```

---

## Rules

- **Never writes to Asana.** No MCP, no API call — output is for the human to
  paste in themselves.
- **Never silently resolves an ambiguity** by picking the most likely reading.
  It becomes an open question, not an assumption baked into a subtask.
- **Grounded, not generic.** A subtask list that could apply to almost any
  task is a sign step 1 was skipped.
- **A discussion starter, not a spec.** If the team pushes back on a subtask or
  a question, that's the process working, not something to smooth over.
