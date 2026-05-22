# REVIEW_PERSONAS.md — Night Shift reviewers

Read-only reviewer sub-agents, one per concern, defined as Claude Code custom
agents in `.claude/agents/ns-*.md`. The loop spawns them with the `Task` tool.
Reviewers **report**; the Night Shift agent applies their fixes.

<!-- /nightshift-init regenerates this table to match the personas it created
     for this repo. The two below are always present; repo-specific ones
     (domain / architecture / db / api / security …) are added as warranted. -->

| Persona | Agent | Owns | Spawn when |
|---------|-------|------|------------|
| Code Expert | `ns-code-expert` | Quality, placement, DRY/YAGNI, idioms, errors | every task |
| Human Advocate | `ns-human-advocate` | Intent match + morning reviewability | every task (last) |

## Dispatch rules (from AGENT_LOOP.md step 6)

- Spawn the reviewers whose domain the change touches (run them in parallel —
  multiple `Task` calls in one turn).
- Always end with `ns-code-expert` + `ns-human-advocate`.
- Each returns findings as `BLOCKING` / `SHOULD-FIX` / `NIT`. Resolve every
  `BLOCKING` before committing; loop until clean, then run the gates (step 7).
