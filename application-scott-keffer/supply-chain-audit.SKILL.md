---
name: supply-chain-audit
description: Detect supply-chain compromise in the current repository — malicious dependencies, worm-style self-propagating packages (Shai-Hulud / mini Shai-Hulud), typosquats, suspicious lifecycle scripts, hijacked maintainer releases, and credential-exfiltration payloads. Works for npm/pnpm/yarn, pip/uv/poetry, cargo, gomod, composer, gem. Use when the user asks to "audit supply chain", "check for compromised dependencies", "scan for Shai-Hulud", "verify packages are clean", or after a public incident affecting a dependency the project uses.
---

# Supply Chain Audit

Goal: prove the repo is NOT compromised by a malicious dependency, lifecycle script, or hijacked release — or, if it is, surface exactly what's wrong and how to recover.

This is a **forensic / read-only** skill. Never run `npm install`, `pip install`, lifecycle scripts, or anything that would execute third-party code as part of the audit. Inspect files, lockfiles, and metadata only.

## Process

1. **Detect ecosystems present.** Look for `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `pyproject.toml`, `poetry.lock`, `uv.lock`, `requirements*.txt`, `Pipfile.lock`, `Cargo.lock`, `go.sum`, `composer.lock`, `Gemfile.lock`. Run multiple `find`/`ls` checks in parallel.
2. **Pull the known-bad IoC set** (see *Known IoCs* below). If the user mentioned a specific incident, ask them for the IoC list or fetch the advisory via WebFetch before scanning.
3. **Scan in this order** (cheap → expensive):
   a. Lockfiles for known-malicious package@version pairs.
   b. `package.json` / equivalents for suspicious lifecycle scripts (`postinstall`, `preinstall`, `prepare`, `prepublish`) — especially obfuscated, base64, `curl | sh`, `eval`, network calls, or writes to `~/.npmrc`, `~/.ssh`, `~/.aws`, env-var dumps.
   c. `node_modules/` (if present) for the same patterns inside installed packages — worms hide payloads here, not in the repo's own `package.json`.
   d. Recent git history for unexpected dependency bumps, new maintainers' first releases pinned in, or `.npmrc`/`.yarnrc`/`pip.conf` changes that redirect registries.
   e. CI config (`.github/workflows/*`, `.gitlab-ci.yml`, `circleci`, etc.) for secret-exfiltration patterns or unpinned third-party actions.
   f. Repo for unexpected files written by past installs: `.github/workflows/shai-hulud-workflow.yml`, `data.json` at repo root, new branches like `shai-hulud`, unexpected public gists/repos created under the user's GitHub.
4. **Run native audit tools** (read-only): `npm audit --json`, `pnpm audit --json`, `yarn npm audit --json`, `pip-audit`, `cargo audit`, `bundle audit`, `composer audit`. Capture output, don't auto-fix.
5. **Cross-check maintainers / release recency.** For each top-level dependency, note packages published within the last 7 days or whose maintainer set changed recently (common compromise window). Use `npm view <pkg> time --json` and `npm view <pkg> maintainers --json`.
6. **Report findings** using the severity buckets below.
7. **Produce a recovery plan** only if anything ≥ High is found — see *Recovery Plan*.

## Known IoCs — Shai-Hulud / "mini Shai-Hulud" family

The Shai-Hulud npm worm (first major wave Sept 2025, "mini" variants ongoing — including the TanStack-adjacent wave) self-propagates by stealing npm/GitHub tokens from a developer's machine during `postinstall`, then republishing trojaned versions of every package that token can publish. Hallmarks to grep for:

**File / repo artifacts**
- A workflow file named `shai-hulud-workflow.yml` or any workflow under `.github/workflows/` that the team didn't add and contains a `curl`/`wget` to a non-GitHub host.
- A public GitHub repo named `Shai-Hulud` under the developer's account (the worm exfiltrates secrets there).
- A repo-root `data.json` containing base64 blobs.
- A branch named `shai-hulud` on any of the user's repos.

**Code patterns inside installed packages (`node_modules/<pkg>/`)**
- `postinstall` / `preinstall` scripts invoking `node -e "<base64>"`, `eval(Buffer.from(...,'base64').toString())`, or `child_process.exec` with obfuscated strings.
- Reads of `~/.npmrc`, `process.env.NPM_TOKEN`, `process.env.GITHUB_TOKEN`, `~/.config/gh/hosts.yml`, `~/.aws/credentials`, `~/.ssh/`.
- Outbound POSTs to `webhook.site`, `pastebin.com`, `requestbin`, raw IPs, or freshly-registered domains.
- Calls to `trufflehog` / embedded secret-scanners bundled inside a runtime dependency (the worm uses TruffleHog to harvest credentials).
- A bundled `bundle.js` ~3–4 MB in size that doesn't match the package's stated purpose.

**Package-set red flags**
- Any of the original Shai-Hulud confirmed packages (e.g. compromised `@ctrl/tinycolor` v4.1.1+ window, `rxnt-*`, `ngx-bootstrap` hijack window, and the 180+ packages from the Sept 2025 wave). When auditing, ask the user for the latest IoC list or fetch StepSecurity / Socket / Snyk advisories via WebFetch — do not rely solely on what's in this file, the list grows.
- A direct dependency was bumped to a `.0` patch of a brand-new minor within hours of an upstream maintainer-account compromise advisory.

**Behaviour at install time** (only relevant if user reports they already ran install)
- `npm install` printed unexpected log lines, opened network connections to unknown hosts, or created files under `~/.config/`.
- `gh auth status` shows a token the user doesn't recognise; new SSH keys in `~/.ssh/authorized_keys`.

## Severity buckets

- **CRITICAL — confirmed compromise.** A known-bad `pkg@version` is in a lockfile, OR a worm artifact (shai-hulud-workflow.yml, Shai-Hulud repo, exfil postinstall) exists. → Trigger Recovery Plan immediately.
- **HIGH — strong signal.** Suspicious lifecycle script, unpinned third-party GH Action with write scope, registry override pointing to a non-official mirror, secret-shaped string in a dep's source.
- **MEDIUM — needs human judgement.** Direct dep was published in the last 72 h by a new maintainer; transitive dep with a CVE but no exploit path; `.npmrc` containing tokens checked into git history.
- **LOW — hygiene.** Outdated `npm audit` advisories with patches available, missing `engines.node` pin, no lockfile committed, no `package-lock=true` enforcement.

## Recovery Plan (only emit when ≥ HIGH found)

Produce a numbered, copy-pasteable plan. Order matters — do credential rotation BEFORE cleanup, because the worm exfiltrates as soon as install runs.

1. **Contain.** On every machine that ran `install` since the suspected window: disconnect from network, do NOT run further npm/git commands until step 2 is done from a clean machine.
2. **Rotate from a clean device.** npm tokens (`npm token revoke`), GitHub PATs + fine-grained tokens, GitHub OAuth apps, SSH keys, cloud provider keys (AWS/GCP/Azure), any token visible in `~/.config/*` or shell history. Revoke, don't just rotate, where the provider supports it.
3. **Audit GitHub account.** Check `https://github.com/settings/security-log` for unknown sessions, new SSH/GPG keys, new OAuth apps, new repos (especially `Shai-Hulud`), new branches named `shai-hulud` across owned repos.
4. **Clean the repo.** Delete `node_modules/` and all lockfiles, pin every direct dep to a known-clean version (published BEFORE the compromise window), reinstall on a clean machine with `--ignore-scripts` first, then re-enable scripts only after verifying.
5. **Re-publish only after recovery.** If the user is themselves a package maintainer, assume their published packages are also trojaned during the window the token was live — yank/deprecate and republish clean versions.
6. **Add guard rails.** Recommend (don't auto-apply): `npm config set ignore-scripts true` globally, Socket / StepSecurity / Snyk in CI, `minimumReleaseAge` (pnpm) or equivalent cooldown, pinned GH Actions by SHA, branch protection requiring signed commits.
7. **Notify.** If the repo is shared, advise the user to notify their team and (if applicable) downstream consumers. Do NOT post anywhere yourself.

## Output format

```
## Supply Chain Audit — <repo name>

Ecosystems scanned: npm, pip, …
Lockfiles inspected: pnpm-lock.yaml (1423 deps), …
Native audit tools run: npm audit, pip-audit

### CRITICAL
- <pkg@version> in pnpm-lock.yaml:<line> — matches Shai-Hulud IoC (source: <advisory URL>)
- .github/workflows/shai-hulud-workflow.yml present — worm artifact

### HIGH
- <pkg>/postinstall in node_modules/<pkg>/package.json — base64-eval'd payload, exfiltrates ~/.npmrc

### MEDIUM
- <pkg>@x.y.z published 14 h ago by maintainer added 3 days ago

### LOW
- npm audit: 2 moderate advisories with patches available

### Recovery Plan
1. …
2. …
```

If everything is clean, say so plainly with the scope of what was checked — don't manufacture findings.

## What this skill must NOT do

- Never run `npm install`, `pip install`, `yarn`, `pnpm i`, `cargo build`, or any lifecycle script as part of auditing. Inspect lockfiles and already-installed `node_modules` only.
- Never auto-rotate credentials or push commits. Surface what needs rotating; the user does it.
- Never post findings to Slack/issues/gists/external services. This skill is local-only output.
- Never claim "clean" without naming the ecosystems and lockfiles you actually inspected.
