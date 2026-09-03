# explain-work

A comprehension check, not a review. Reads a finished diff against the Asana
task it was meant to satisfy, then hands back what changed, why, how it maps
to the task's requirements, and the questions a reviewer would ask — before
the PR opens, not after.

## Install

Claude Code: copy this folder to `~/.claude/skills/explain-work` (every
project) or `<repo>/.claude/skills/explain-work` (that repo only). Cursor:
same folder, `~/.cursor/skills/explain-work` or
`<repo>/.cursor/skills/explain-work`.

## Use

```bash
/explain-work
```

Paste the Asana task's title, description, and acceptance criteria along with
the command (or when asked) — there's no Asana integration, so the task
arrives as text, not a fetched link. Scope resolves the same way as
`review-crew`: an explicit argument, then staged changes, then the branch
against its default branch, then the working tree.

## What it doesn't do

No severity, no blocking, no fixing, and it doesn't touch a PR — that's
`review-crew`. This one only checks whether the person who wrote the diff can
account for it.
