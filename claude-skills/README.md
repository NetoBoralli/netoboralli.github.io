# Claude Code Skills

Agent skills I've built for [Claude Code](https://claude.com/claude-code). Each
folder is a self-contained skill: a `SKILL.md` with the instructions (and, where
needed, supporting templates).

## Installing a skill

Copy any skill folder into your skills directory:

```bash
# user-level (available in every project)
cp -R <skill-name> ~/.claude/skills/

# or project-level
cp -R <skill-name> .claude/skills/
```

Claude Code picks it up automatically — invoke it by name or let it trigger on
the situations described in the skill's `description`.

## Published skills

| Skill | What it does |
| --- | --- |
| [`enhance-code`](enhance-code/) | Scans staged git changes for bugs, edge cases, and quality issues, then applies idiomatic, DRY/YAGNI improvements. |
| [`native-data-fetching`](native-data-fetching/) | Guidance for implementing and debugging network requests, API calls, and data fetching (fetch, axios, React Query, SWR), with error handling, caching, and offline support. |
| [`security-audit`](security-audit/) | End-to-end security audit of the current repo across auth, input validation, secrets, transport, dependencies, infra, and CI/CD, ending in a prioritized mitigation plan. |
| [`supply-chain-audit`](supply-chain-audit/) | Detects supply-chain compromise — malicious deps, Shai-Hulud-style worms, typosquats, hijacked releases — across npm/pnpm/yarn, pip/uv/poetry, cargo, gomod, composer, and gem. |
| [`nightshift-init`](nightshift-init/) | Scaffolds the Night Shift autonomous overnight workflow into the current repo, tailored to its stack — runner, reviewer personas, gates, and the `nightshift-spec` skill. |
| [`review-crew`](review-crew/) | Runs a review panel over a slice of work — a general reviewer, six specialists (test, code, database, security, design, infra), and an intent advocate — adversarially verifies every finding, fixes what survives, and runs the project's gates. |
