---
name: nightshift-init
description: Scaffold the Night Shift autonomous overnight workflow into the CURRENT repo, tailored to its stack. Detects test/lint/migration commands, docker services, frontend, and a conventions doc; confirms the gates + the destructive denylist; then writes a tailored nightshift/ runner, reviewer personas, and the nightshift-spec skill. Use when Nelson says "set up night shift here", "port night shift to this repo", "init nightshift", or runs /nightshift-init.
metadata:
  author: Night Shift
  version: "1.0.0"
---

# Night Shift Initializer

Install the Night Shift workflow into the repo you're currently in, tailored to
its stack. The portable skeleton lives in
`~/.claude/skills/nightshift-init/templates/`; you copy it and tailor the
repo-specific bits. **Everything repo-specific is funneled into one file —
`nightshift/nightshift.conf`** — plus the AI-tailored personas and contracts.

Background on the workflow you're installing: humans write specs by day; an
autonomous loop (`nightshift/run.sh`) works tasks from `nightshift/TODOS.md` by
night — tests first, fix, persona review, gates, one commit per task on a
`night-shift/<date>` branch. Read a template file before copying it so you
understand what you're tailoring.

## Hard guardrails for THIS skill
- **Read-only detection, then confirm before writing.** Never guess the
  destructive denylist — it's the safety mechanism. Confirm it explicitly.
- Do **not** run the loop, commit, or push. You only scaffold files.
- If `nightshift/` already exists, ask before overwriting.

## Procedure

### Step 1 — Locate & guard the target repo
- `git rev-parse --show-toplevel` → REPO_DIR. **If not a git repo, stop** and
  explain: Night Shift's core safety is git branch isolation; offer `git init`.
- Note the default branch (`main`/`master`).

### Step 2 — Detect the stack (read-only)
Inspect the repo to PROPOSE the config (confirm in Step 3). Look for:
- **Language / runner:** `manage.py` (Django), `package.json` (read its
  `scripts`), `pyproject.toml`/`pytest.ini`, `Cargo.toml`, `go.mod`, `Gemfile`,
  `Makefile`, `mix.exs`.
- **Test command(s):** package.json `test`/`e2e`, a custom test runner script,
  `pytest`, Makefile targets. Prefer the project's real E2E/integration command.
- **Static checks / lint / typecheck:** a `checks/` dir, `.pre-commit-config`,
  ruff/mypy/eslint/biome, `tsc --noEmit`, package.json `lint`/`check`.
- **Migrations:** Django (`makemigrations` + `migrate` or `migrate_schemas` for
  django-tenants), Alembic, Prisma, active_record, etc. Note the exact commands.
- **Containers:** `docker-compose.yml` services — especially worker/queue
  services (celery, sidekiq, etc.) that must restart to pick up new code, and
  any named volumes whose removal would wipe data.
- **Cross-repo:** ask whether a sibling repo (e.g. a frontend) should be added
  via `--add-dir`.
- **Conventions doc:** `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or none.
- **Python venv / package manager** path (`venv/bin/python`, `.venv`, `poetry
  run`, `pnpm`, `yarn`, `npm`).

### Step 3 — Confirm gates + DENYLIST (interactive, the load-bearing step)
Use AskUserQuestion (with your detected values as recommended defaults) to lock:
1. **Gates** — the test/static/lint commands that must pass before any commit.
2. **Destructive denylist** — what to block for THIS repo (db resets, data
   wipes, destructive migrations, volume removal). Show the list you'll apply
   and ask if anything is missing. Never finalize this silently.
3. **Migrations** — allowed? which exact commands? (forward only; block reverse
   to zero / equivalents).
4. **Worker services** to restart (if any) so async code is refreshed pre-gate.
5. **Extra repo dir(s)** for cross-repo (if any).
6. **Conventions doc** to honor.

### Step 4 — Scaffold from templates
- Copy `~/.claude/skills/nightshift-init/templates/nightshift/` → `<repo>/nightshift/`.
- Copy `templates/agents/ns-code-expert.md` and `ns-human-advocate.md` →
  `<repo>/.claude/agents/` (these two are generic — always installed).
- Copy `templates/skills/nightshift-spec/` → `<repo>/.claude/skills/nightshift-spec/`.
- Write `<repo>/nightshift/nightshift.conf` from the Step 3 answers (use
  `nightshift.conf.example` as the shape). `chmod +x nightshift/run.sh`.
- **.gitignore:** if `nightshift/` isn't already ignored, append it. Decide
  `.claude/` handling: if `.claude/` is already ignored, the agents/skill are
  local-only (fine); otherwise tell Nelson and let him choose to ignore or track.

### Step 5 — Tailor the reviewer personas
- Always keep `ns-code-expert` + `ns-human-advocate`.
- From the conventions doc + the repo's architecture, generate ONLY the
  repo-specific reviewers it warrants, using `templates/agents/_PERSONA_TEMPLATE.md`.
  Common ones (create only if they apply): a **domain expert** (the business
  rules — accounting, healthcare, payments…), an **architecture/contract
  expert** (auth/tenancy/layering rules the repo enforces), a **db/perf
  expert** (schema, indexes, query patterns), an **api-contract expert**
  (endpoint/schema/type-sync rules). Name them `ns-<concern>.md`.
- Rewrite `nightshift/REVIEW_PERSONAS.md`'s table + dispatch rules to match the
  personas you actually created.

### Step 6 — Tailor the spec skill's contracts
In `<repo>/.claude/skills/nightshift-spec/SKILL.md`, replace the
`<<CONTRACTS_CHECKLIST>>` placeholder with THIS repo's real contracts (pulled
from its conventions doc), each mapped to one of the personas from Step 5. If
the repo has no conventions doc, use a minimal generic checklist (tests pass,
lint clean, no secrets, migrations present).

### Step 7 — Verify & report (run nothing)
- `bash -n nightshift/run.sh` (syntax) and `bash nightshift/run.sh --dry-run`
  (should print the plan, or abort cleanly if the tree is dirty).
- Report: files created, the resolved `nightshift.conf`, the personas generated,
  the launch command, and the reminder to **restart Claude Code** so the new
  project skill (`/nightshift-spec`) is discovered. Do not launch or commit.

## Notes
- The runner is generic; per-repo changes go in `nightshift.conf`. If a repo
  needs structurally different behavior, edit its copy of `run.sh` directly.
- Keep the denylist conservative: a recoverable code mistake (branch + no push)
  is cheap; an irreversible data wipe is not.
