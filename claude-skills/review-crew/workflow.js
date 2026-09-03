export const meta = {
  name: 'review-crew',
  description: 'General review, then six specialists, then intent — every finding adversarially verified',
  whenToUse: 'A slice of work is code-complete and needs to pass a review gate before a human reads it.',
  phases: [
    { title: 'General', detail: 'broad quality pass, alone, before the specialists' },
    { title: 'Specialists', detail: 'test, code, database, security, design, infra — same snapshot' },
    { title: 'Intent', detail: 'does the diff match the task it came from' },
    { title: 'Verify', detail: 'refute every finding; survivors become work' },
  ],
}

// args, assembled by SKILL.md step 1:
//   { packet, depth, repo, tiers }
//
// `packet` is the review packet as a string — the scope, the stack facts, the
// design rules, what is deliberately out of scope, and the original task. Every
// reviewer gets the identical packet, which is the point: findings have to be
// reproducible against the diff the user actually wrote.
//
// `repo` is the absolute path of the repository under review. Reviewers read
// their brief from <repo>/.review-crew-run/personas/<name>.md and the diff from
// <repo>/.review-crew-run/slice.diff, both staged by step 1.
//
// Both of those live INSIDE the repo for a reason worth stating, because the
// obvious alternative — pointing agents at this skill's own personas/ directory
// — is what broke the first run. A background subagent cannot answer a
// permission prompt, so a read outside the project directory does not fail
// loudly; the agent simply hangs having produced nothing, and the user gets
// prompts instead of a review. Two of eight reviewers were lost that way.

// `args` arrives as a JSON **string**, not an object, whatever the tool
// documentation implies. Destructuring it directly yields `undefined` for every
// key — which fails silently and invisibly: the script simply falls back to its
// own defaults, so a caller asking for `depth: 'quick'` and one specialist gets
// the full crew at standard depth and no error to say otherwise. Verified with a
// zero-agent probe that reported `typeof args === "string"`.
const input = typeof args === 'string' ? JSON.parse(args) : (args ?? {})
const { packet, depth = 'standard', repo, tiers, specialists } = input

// Model and effort per stage. SKILL.md resolves these from --depth (or from a
// flat --model/--effort override) and passes them in; the fallback here keeps
// the script runnable on its own.
const TIER = tiers || {
  general: { model: 'opus', effort: 'medium' },
  specialist: { model: 'sonnet', effort: 'medium' },
  intent: { model: 'opus', effort: 'medium' },
  verify: { model: 'opus', effort: 'high' },
}

// At `quick`, one verifier reviews a persona's whole finding set instead of one
// per finding — the adjudication survives, the agent count roughly halves.
// At `max`, three verifiers vote and a finding needs a majority to live.
const BATCH_VERIFY = depth === 'quick'
const VERIFIER_VOTES = depth === 'max' ? 3 : 1

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    skipped: {
      type: 'boolean',
      description: 'True when this diff has no surface for this persona. Not a failure.',
    },
    skip_reason: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['file', 'summary', 'failure_scenario', 'severity'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['BLOCKING', 'SHOULD-FIX', 'NIT'] },
          category: { type: 'string' },
          summary: { type: 'string', description: 'One sentence stating the defect' },
          failure_scenario: {
            type: 'string',
            description: 'Concrete inputs or sequence, and the resulting wrong outcome',
          },
          suggested_fix: { type: 'string' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean' },
    severity: { type: 'string', enum: ['BLOCKING', 'SHOULD-FIX', 'NIT'] },
    reason: { type: 'string' },
  },
}

const BATCH_VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['verdicts'],
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['index', 'refuted', 'reason'],
        properties: {
          index: { type: 'integer', description: 'Position of the finding in the list given' },
          refuted: { type: 'boolean' },
          severity: { type: 'string', enum: ['BLOCKING', 'SHOULD-FIX', 'NIT'] },
          reason: { type: 'string' },
        },
      },
    },
  },
}

function briefPath(persona) {
  return `${repo}/.review-crew-run/personas/${persona}.md`
}

function reviewPrompt(persona, extra = '') {
  return [
    `Read your reviewer brief FIRST: ${briefPath(persona)}`,
    'Follow it exactly — it defines what you own, what you do not own, and how to judge.',
    '\n---\n\n# The change under review\n',
    packet,
    extra,
    '\n---\n',
    `The complete diff is at ${repo}/.review-crew-run/slice.diff.`,
    'Read the actual files too, not only the diff — the diff is your subject and',
    'the surrounding code is your evidence. Everything you need is inside the',
    'repo; do not read outside it, because you will not get an answer.',
    '',
    'Return findings through the structured output tool. An empty list is a valid,',
    'useful answer: say the code is clean rather than finding something to justify',
    'the run. If this diff has no surface for your speciality, set skipped=true.',
  ].join('\n')
}

// ── 1. General review, alone and first ──────────────────────────────────────
//
// Deliberately not parallel with the specialists. It is the broad quality pass,
// and running it first means the specialists inherit a settled picture of what
// the change is — without anything being FIXED in between, so every reviewer
// still sees the identical snapshot.
phase('General')
const general = await agent(reviewPrompt('general'), {
  label: 'review:general',
  phase: 'General',
  schema: FINDINGS_SCHEMA,
  ...TIER.general,
})

// ── 2. The specialists, in parallel ─────────────────────────────────────────
//
// Selected, not all six. Running the full set costs six agents plus a verifier
// per finding, and measured across a long run of reviews most of them returned
// nothing: `general` and `intent` produced almost every confirmed finding, while
// `test`, `code` and `database` came back empty far more often than not.
//
// So the caller names the ones the slice actually needs — `security` for an
// upload handler, `database` for a migration, `infra` for CI, `design` for UI —
// and the default is the two that carry their weight everywhere. Pass
// `specialists: []` for general + intent alone; pass the full list to get the
// old behaviour back.
const ALL_SPECIALISTS = ['test', 'code', 'database', 'security', 'design', 'infra']
const DEFAULT_SPECIALISTS = ['security', 'infra']

const SPECIALISTS = (specialists ?? DEFAULT_SPECIALISTS).filter(key => {
  if (ALL_SPECIALISTS.includes(key)) return true
  log(`unknown specialist ${JSON.stringify(key)} — skipping. Known: ${ALL_SPECIALISTS.join(', ')}`)
  return false
})

phase('Specialists')
if (!SPECIALISTS.length) log('No specialists selected — general and intent only.')
const specialistResults = await parallel(
  SPECIALISTS.map(key => () =>
    agent(reviewPrompt(key), {
      label: `review:${key}`,
      phase: 'Specialists',
      schema: FINDINGS_SCHEMA,
      ...TIER.specialist,
    }).then(r => ({ persona: key, result: r })),
  ),
)

// ── 3. Intent advocate, last ────────────────────────────────────────────────
//
// Runs after the others because its question — is this the right work, and can
// someone review it in the morning — is the one you ask about a finished thing.
phase('Intent')
const intent = await agent(reviewPrompt('intent'), {
  label: 'review:intent',
  phase: 'Intent',
  schema: FINDINGS_SCHEMA,
  ...TIER.intent,
})

// ── collect ─────────────────────────────────────────────────────────────────
const all = [
  { persona: 'general', result: general },
  ...specialistResults.filter(Boolean),
  { persona: 'intent', result: intent },
].filter(entry => entry.result)

const skipped = all
  .filter(e => e.result.skipped || !(e.result.findings || []).length)
  .map(e => e.persona)

const raw = all.flatMap(({ persona, result }) =>
  (result.findings || []).map(f => ({ ...f, persona })),
)

if (!raw.length) {
  log('No findings from any reviewer.')
  return { findings: [], refuted: [], skipped, personaCount: all.length }
}

log(`${raw.length} findings from ${all.length} reviewers — verifying`)

// ── 4. Verify ───────────────────────────────────────────────────────────────
//
// Every finding goes to a verifier told to refute it. This is what keeps the
// output a task list rather than a pile of plausible claims: reviewers misread
// code, restate handled cases, and flag deliberate decisions, and all three look
// identical to a real finding until someone checks.
phase('Verify')

function verifyPrompt(finding) {
  return [
    `Read your brief FIRST: ${briefPath('verifier')}`,
    'Your job is to REFUTE the finding below. Default to refuted if you cannot',
    'confirm it by reading the actual code.',
    '\n---\n\n# The finding to refute\n',
    `Reported by: ${finding.persona}`,
    `Severity claimed: ${finding.severity}`,
    `File: ${finding.file}${finding.line ? `:${finding.line}` : ''}`,
    `Summary: ${finding.summary}`,
    `Failure scenario claimed: ${finding.failure_scenario}`,
    '\n---\n\n# The change it was found in\n',
    packet,
  ].join('\n')
}

let verified
if (BATCH_VERIFY) {
  // One verifier per persona's finding set. Same refute-by-default prompt,
  // roughly half the agents.
  const byPersona = {}
  for (const f of raw) (byPersona[f.persona] ||= []).push(f)

  const batches = await parallel(
    Object.entries(byPersona).map(([persona, findings]) => () =>
      agent(
        [
          `Read your brief FIRST: ${briefPath('verifier')}`,
          'Refute each finding below. Default to refuted when unsure.',
          '\n---\n\n# Findings to refute, one verdict each\n',
          findings
            .map((f, i) =>
              `[${i}] ${f.severity} ${f.file}${f.line ? `:${f.line}` : ''}\n` +
              `    ${f.summary}\n    scenario: ${f.failure_scenario}`,
            )
            .join('\n\n'),
          '\n---\n\n# The change they were found in\n',
          packet,
          '\nReturn one verdict per finding, keyed by its index.',
        ].join('\n'),
        {
          label: `verify:${persona}`,
          phase: 'Verify',
          schema: BATCH_VERDICT_SCHEMA,
          ...TIER.verify,
        },
      ).then(r => ({ persona, findings, verdicts: (r && r.verdicts) || [] })),
    ),
  )

  verified = batches.filter(Boolean).flatMap(({ findings, verdicts }) =>
    findings.map((f, i) => {
      const v = verdicts.find(x => x.index === i)
      // No verdict came back for this finding — keep it and say so, rather
      // than dropping it silently. A missing verdict is not a refutation.
      if (!v) return { ...f, verdict: { refuted: false, reason: 'no verdict returned' } }
      return { ...f, verdict: v, severity: v.severity || f.severity }
    }),
  )
} else {
  verified = await parallel(
    raw.map(finding => () =>
      parallel(
        Array.from({ length: VERIFIER_VOTES }, (_, i) => () =>
          agent(verifyPrompt(finding), {
            // Vary the label so concurrent votes on one finding stay legible.
            label: `verify:${finding.file}${VERIFIER_VOTES > 1 ? `#${i + 1}` : ''}`,
            phase: 'Verify',
            schema: VERDICT_SCHEMA,
            ...TIER.verify,
          }),
        ),
      ).then(votes => {
        const cast = votes.filter(Boolean)
        // A finding nobody could vote on stays alive — an agent that died is
        // not evidence the finding was wrong.
        if (!cast.length) {
          return { ...finding, verdict: { refuted: false, reason: 'no verdict returned' } }
        }
        const refutals = cast.filter(v => v.refuted).length
        const refuted = refutals > cast.length / 2
        const winner = cast.find(v => v.refuted === refuted) || cast[0]
        return {
          ...finding,
          verdict: { ...winner, refuted, votes: cast.length, refutals },
          severity: (!refuted && winner.severity) || finding.severity,
        }
      }),
    ),
  )
}

const survivors = verified.filter(Boolean).filter(f => !f.verdict.refuted)
const refuted = verified.filter(Boolean).filter(f => f.verdict.refuted)

const RANK = { BLOCKING: 0, 'SHOULD-FIX': 1, NIT: 2 }
survivors.sort((a, b) => (RANK[a.severity] ?? 3) - (RANK[b.severity] ?? 3))

log(`${survivors.length} confirmed, ${refuted.length} refuted`)

// Returned for the skill to adjudicate, fix, gate and stage. Refuted findings
// come back too — the count is worth reporting, and an occasional refutation is
// worth a human glance.
return {
  findings: survivors,
  refuted,
  skipped,
  personaCount: all.length,
  depth,
}
