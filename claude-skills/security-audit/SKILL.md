---
name: security-audit
description: End-to-end cybersecurity audit of the application in the current repo — finds existing breaches and likely-future breaches across authentication, authorization, input validation, secrets management, data storage, transport, dependencies, infrastructure, and CI/CD — then produces a prioritized mitigation plan with concrete fixes. Use when the user asks to "do a security review", "audit the app's security", "find vulnerabilities", "check for breaches", "OWASP review", or after an incident/before a release. For supply-chain-specific concerns (malicious dependencies, Shai-Hulud-style worms), call the `supply-chain-audit` skill instead or in addition.
---

# Security Audit

Goal: produce a credible, prioritized security posture report for this codebase — what is already broken, what is likely to break under an attacker, and a concrete plan to fix each finding.

This is a **read-only investigation skill**. Never exploit, never send payloads at any live system, never exfiltrate. Static analysis + config review only, unless the user explicitly asks you to run a specific tool.

## Process

1. **Map the app first.** Don't audit blind. Identify in parallel:
   - Languages, frameworks, and runtime (e.g. Next.js + Postgres, FastAPI + Redis, Rails + S3).
   - Entry points: HTTP routes, GraphQL schema, background jobs, webhooks, public S3 buckets, exposed cron / queue consumers.
   - Trust boundaries: where user input crosses into DB, into shells, into HTML, into other services.
   - Auth model: session vs JWT vs OAuth, where roles/permissions are checked.
   - Data classification: PII, payment data, health data, credentials, internal-only.
   - Hosting/infra: Vercel / AWS / Supabase / Cloudflare / self-hosted — relevant because controls live there too.
2. **Run the checklist below**, in the order given. Stop and ask the user only if a check needs production knowledge you can't infer (e.g. "is this endpoint actually public?").
3. **For every finding**, record: file:line, category, severity (CRITICAL/HIGH/MEDIUM/LOW), concrete attack scenario, concrete fix.
4. **Cross-reference with the supply chain.** If dependency-related issues come up, defer to `supply-chain-audit` rather than duplicating.
5. **Synthesize a Mitigation Plan** — prioritized, with effort estimates and ordering rules (see *Mitigation Plan*).

## Audit checklist

Run as many of these in parallel via grep/find as fit. Cite file:line for every finding.

### 1. Secrets & credentials
- Hard-coded API keys, JWT secrets, DB URLs, OAuth client secrets, private keys in any tracked file. Grep for: `AKIA`, `sk_live_`, `xoxb-`, `ghp_`, `BEGIN PRIVATE KEY`, `password\s*=`, `SECRET\s*=`, `Bearer\s+ey`.
- `.env`, `.env.local`, `.env.production` committed to git history (`git log --all --full-history -- .env*`).
- Secrets in CI yaml as plaintext instead of `${{ secrets.X }}`.
- `console.log` / `print` of tokens, sessions, full request bodies, password fields.
- Secrets baked into client-side bundle (`NEXT_PUBLIC_*` holding anything sensitive, secrets in Expo/React Native JS, secrets in mobile binaries).

### 2. Authentication
- Password hashing: must be bcrypt/argon2/scrypt with per-user salt — flag MD5/SHA1/SHA256-of-password, missing salts, low cost factors.
- Session: secure cookie flags (`HttpOnly`, `Secure`, `SameSite`), session fixation, missing rotation on privilege change, no logout server-side invalidation.
- JWT: `alg: none`, HS256 with weak/leaked secret, no `exp`, no audience/issuer check, stored in `localStorage` (XSS-stealable), no refresh-token rotation, no revocation list.
- OAuth/SSO: missing `state` parameter (CSRF), open redirect on `redirect_uri`, ID-token signature not verified, `nonce` not checked.
- MFA bypass paths, password reset tokens that don't expire or aren't single-use, account-enumeration on login / reset / signup endpoints.

### 3. Authorization (this is where most real breaches happen)
- IDOR: routes like `/api/users/:id` / `/orders/:id` where the handler trusts the URL param without checking ownership.
- Missing role checks on admin routes; relying on UI hiding the button.
- GraphQL: field-level auth missing, introspection enabled in production, no query depth/complexity limits.
- Row-level security: if Supabase/Postgres RLS — are policies actually `ENABLED` on every table holding user data? Are `service_role` keys used from client/edge?
- Webhook endpoints with no signature verification.
- Multi-tenant: tenant ID derived from request body/header instead of session.

### 4. Input handling & injection
- SQL: string-concatenated queries, `raw()` / `unsafe()` ORM calls, dynamic `ORDER BY` / table names from user input.
- NoSQL injection (Mongo `$where`, operator injection via JSON body).
- Command injection: `exec`, `spawn`, `subprocess` with shell=True + user input; SSRF in image/file fetchers; `eval`, `Function()`, `vm.runInContext` on user input.
- XSS: `dangerouslySetInnerHTML`, `v-html`, `innerHTML =`, untrusted markdown rendered without sanitizer, missing CSP.
- SSRF: server fetching arbitrary URLs from user input without allowlist (image proxies, PDF generators, webhook callbacks). Especially check that `localhost` / `169.254.169.254` / private IP ranges are blocked.
- Path traversal: `fs.readFile`/`open` joining user input into paths; `../` not normalized; ZIP/TAR extraction without path checks (Zip Slip).
- XXE in XML parsers, SSRF via SVG, formula injection in CSV exports.
- File upload: missing MIME/extension allowlist, missing size limit, content served from same origin executing code, no AV/scan.

### 5. Transport, headers, CORS
- HTTP endpoints (non-TLS) for anything carrying auth.
- Missing security headers: `Strict-Transport-Security`, `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `Permissions-Policy`.
- CORS: `Access-Control-Allow-Origin: *` combined with `Allow-Credentials: true`; reflective origin echo; missing origin allowlist on state-changing routes.
- CSRF: cookie-auth state-changing endpoints without CSRF token / `SameSite=Strict|Lax` / origin check.

### 6. Cryptography
- Custom crypto. Reject unless there's a very specific reason.
- ECB mode, static IVs, MD5/SHA1 for integrity, RSA without padding (`PKCS1v15` for encryption, no OAEP), keys < 2048 RSA / 256 EC.
- Random tokens generated with `Math.random()` / `rand()` instead of CSPRNG.
- KMS/HSM keys exposed via overly permissive IAM.

### 7. Data storage & privacy
- PII stored unencrypted at rest where the threat model needs it (health, payment, government IDs).
- Backups unencrypted or in public buckets.
- Logs containing PII, tokens, full request/response bodies.
- DB migrations leaving columns with sensitive defaults; missing data-retention deletes.
- Compliance: PCI-scope data outside a tokenization vault; GDPR / LGPD subject-rights endpoints missing; HIPAA audit logs absent.

### 8. Rate limiting & abuse
- Login, password reset, signup, OTP send, magic-link, payment, AI-inference endpoints with no rate limit → credential stuffing, $$ exhaustion, prompt-injection floods.
- Webhooks without idempotency keys (double-charge risk).
- Public AI endpoints without per-user/IP throttling and token caps.

### 9. Infrastructure / IaC / cloud config
- Terraform / Pulumi / CloudFormation:
  - S3 buckets with `acl = "public-read"` or no `block_public_access`.
  - Security groups with `0.0.0.0/0` on management ports (22, 3389, 5432, 6379, 27017).
  - RDS / databases publicly accessible.
  - IAM policies with `Action: "*"` / `Resource: "*"`.
  - KMS keys without rotation, no deletion protection on prod data stores.
  - Lambda/Cloud Functions with broad invoke perms or env-var secrets unencrypted.
- Docker: running as root, `:latest` tags, secrets in build args, exposed unnecessary ports.
- Kubernetes: containers as root, `privileged: true`, no NetworkPolicies, secrets mounted as env vars, missing PodSecurity standards.

### 10. CI/CD & build pipeline
- Workflows triggered by `pull_request_target` running untrusted code with secret access.
- Third-party GitHub Actions used by tag (`@v3`) instead of SHA → maintainer hijack risk.
- Build steps that `curl | sh` from non-pinned URLs.
- Artifacts published without provenance/attestation.
- Branch protection: missing required reviews, missing required status checks, force-push allowed to default branch.
- Deploy keys / PATs with broader scope than necessary.

### 11. Frontend-specific (web)
- Prototype pollution sinks, unsafe `eval`/`new Function` in client code.
- `target="_blank"` without `rel="noopener noreferrer"`.
- Postmessage handlers without origin check.
- Service workers caching authenticated responses.
- Source maps shipping to production with internal paths.

### 12. Mobile / native
- Hardcoded API endpoints/secrets in app bundle.
- Insecure deeplink handlers (intent redirection, universal-link hijacking).
- WebView with `JavaScriptEnabled` + `addJavascriptInterface` exposing native code.
- Missing certificate pinning where the threat model warrants it.
- Insecure local storage (AsyncStorage / SharedPreferences holding tokens unencrypted).

### 13. AI / LLM specifics (if app uses LLMs)
- Prompt injection via untrusted content rendered into prompts.
- Tool-use / function-calling where the model can issue privileged actions without confirmation.
- PII or secrets sent to third-party model providers without DPA / redaction.
- Output rendered as HTML/Markdown without sanitization (XSS via model output).
- Unbounded token usage per user / no per-user cost cap.

### 14. Logging, monitoring, IR readiness
- No audit log for admin actions, auth events, permission changes, data exports.
- No alerting on auth anomalies, repeated 401/403, sudden export spikes.
- Logs not centralized or not retained per the threat model.
- No documented incident-response runbook.

## Optional dynamic tooling

Only run if the user explicitly opts in, since these touch the network or take time:
- `semgrep --config=auto` for code-level patterns.
- `trufflehog filesystem .` / `gitleaks detect` for historical secret leaks.
- `npm audit` / `pip-audit` / `cargo audit` (covered better by `supply-chain-audit`).
- `nuclei` / `zap-baseline` against a **non-production** instance only with explicit authorization.

Never point active scanners at production without the user explicitly confirming they own the target and want it scanned now.

## Severity rubric

- **CRITICAL** — currently exploitable, no auth or minimal skill required, exposes user data, money, or full system compromise. Examples: hardcoded prod DB credential in repo; IDOR returning any user's PII; SQLi on a public endpoint; admin route with no auth.
- **HIGH** — exploitable but requires some condition (authenticated user, specific timing, chained with another bug). Examples: stored XSS in user-only surface, missing CSRF on state-changing route, public S3 bucket with non-PII assets, JWT in localStorage with weak XSS posture.
- **MEDIUM** — defense-in-depth gap, exploitable only under unusual conditions. Examples: missing CSP, no rate limit on signup, weak password policy, verbose error messages.
- **LOW** — hygiene / future-proofing. Examples: missing `Permissions-Policy` header, outdated TLS suite enabled alongside modern ones, source maps in prod.

## Mitigation plan

After findings, emit a plan with:

1. **Immediate (do today)** — every CRITICAL, plus any HIGH with a one-line fix. Each item: file:line, the change, who/what could verify it.
2. **Short term (this week)** — remaining HIGH, plus MEDIUM items that block compliance or a release.
3. **Medium term (this quarter)** — remaining MEDIUM, architectural changes (e.g. introduce RLS, move secrets to a vault, add WAF, set up SSO).
4. **Continuous** — process recommendations: pre-commit secret scanning, dependabot / renovate with cooldown, branch protection rules, security review gate in PR template, scheduled re-audit cadence.

For each item include: **what to change**, **why (linked finding)**, **rough effort** (S/M/L), and **how to verify** (a test, a curl, a config inspection).

Order by *blast radius × ease of fix*, not by category. A one-line fix that closes a CRITICAL goes above a quarter-long re-architecture.

## Output format

```
## Security Audit — <repo>

App profile: <stack, hosting, data sensitivity>
Scope inspected: <dirs/files/configs covered>
Out of scope: <what was NOT looked at — be honest>

### Findings

#### CRITICAL
- [AUTHZ] `app/api/users/[id]/route.ts:42` — handler returns the user record without checking session.userId === params.id (IDOR).
  Attack: any logged-in user can GET /api/users/<anyone> and read PII.
  Fix: add `if (session.userId !== params.id) return new Response(null,{status:404})` (404 not 403 to avoid enumeration).
  Verify: integration test with two users; second user's GET returns 404.

#### HIGH …
#### MEDIUM …
#### LOW …

### Mitigation Plan

#### Immediate (today)
1. …

#### Short term (this week)
…

#### Medium term (this quarter)
…

#### Continuous
…
```

If a category is genuinely clean, write "Clean — checked X, Y, Z." Don't omit the category silently; omission reads as "didn't look."

## Constraints

- Never run exploits or live payloads against any system.
- Never push code, open issues, or post findings externally — output stays in the conversation.
- Never claim a category is clean without naming what was inspected.
- For supply-chain / malicious-dependency concerns, defer to `supply-chain-audit`.
- If the app handles regulated data (PCI, HIPAA, GDPR/LGPD subject data) and the user hasn't said so, flag the assumption rather than guessing the threat model.
