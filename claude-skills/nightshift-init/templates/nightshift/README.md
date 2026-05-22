# Night Shift

Autonomous overnight agent workflow, adapted from
[jamon.dev/night-shift](https://jamon.dev/night-shift). Humans architect and
write specs by day; an agent executes against the test harness by night,
committing reviewable work for the morning. Installed by `/nightshift-init`.

## Files

| File | Role |
|------|------|
| `run.sh` | The headless loop runner (generic — driven by `nightshift.conf`). |
| `nightshift.conf` | **The only repo-specific file** — gates, allow/deny, services. |
| `AGENT_LOOP.md` | The procedure each session follows (read cold every iteration). |
| `TODOS.md` | The work queue + durable cross-iteration state. |
| `REVIEW_PERSONAS.md` | This repo's reviewer sub-agents and when to spawn them. |
| `CHANGELOG.md` / `REPORT.md` | Per-task log / morning recap (REPORT written by the agent). |
| `ramblings/` | Your hand-written spec drafts (`/nightshift-spec` refines them). |
| `logs/<date>/` | Full transcript per iteration. |

## Launch

The runner **refuses to start on a dirty tree** — commit or stash your own WIP
first. Prereqs: whatever your GATES need running (dev server, DB, workers).

```bash
bash nightshift/run.sh --dry-run      # show the plan + permission box
bash nightshift/run.sh                # run the night
bash nightshift/run.sh --with-extra-dirs   # also mount EXTRA_DIRS (cross-repo)
```

It creates `night-shift/<date>` from the default branch, then loops: pick a task
→ tests first → fix → persona review → gates → one commit. Lock your screen;
review in the morning. Tunables live in `nightshift.conf` (`MAX_ITERS`,
`ITER_BUDGET`, `MODEL`, …).

## Safety model

- **Branch-only**, **never pushes**, **refuses a dirty tree** (no stash/discard).
- **Denylist** (base + `DENY_EXTRA`) blocks destructive commands; `DENY` always
  wins over `ALLOW`. Review `DENY_EXTRA` in `nightshift.conf` — it's the
  load-bearing safety list for this repo.
- **Bounded:** per-iteration timeout + `$` budget + max-turns, outer iteration
  cap, idle-stop.
- **Gated:** nothing commits until every `GATES` command is green.

## Authoring (day shift)

Drop a hand-written draft in `ramblings/` (copy `_TEMPLATE.md`), run
`/nightshift-spec`, answer its gap questions, then arm the resulting spec by
removing its `draft:` prefix in `TODOS.md`.
