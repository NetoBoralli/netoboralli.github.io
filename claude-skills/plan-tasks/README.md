# plan-tasks

Runs at plan time, before any code exists. Takes an Asana task and turns it
into a grounded, sequenced subtask checklist plus the open questions worth
resolving out loud first — meant to seed the team's planning discussion, not
replace it.

## Install

Claude Code: copy this folder to `~/.claude/skills/plan-tasks` (every project)
or `<repo>/.claude/skills/plan-tasks` (that repo only). Cursor: same folder,
`~/.cursor/skills/plan-tasks` or `<repo>/.cursor/skills/plan-tasks`.

## Use

```bash
/plan-tasks
```

Paste the Asana task's title and description along with the command — no
Asana integration, the task arrives as text. The skill greps the relevant part
of the codebase before proposing anything, so the breakdown is grounded in
what's actually there rather than generic.

## Output

Two things, both meant to be pasted straight back into the Asana task: open
questions that would change the shape of the work if answered differently, and
a checklist of subtasks sized to land as individual reviewable PRs.
