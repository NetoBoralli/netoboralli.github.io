---
name: nightshift-spec
description: Refine a hand-written markdown feature draft into a night-shift-ready requirements doc. You fill the draft manually first; this skill ONLY refines it — it does not invent the feature. Use when you say "refine my night shift spec", "turn this draft into requirements", or run /nightshift-spec [path]. Reads from nightshift/ramblings/, writes to docs/, arms it in nightshift/TODOS.md behind the draft: gate.
metadata:
  author: Night Shift
  version: "1.0.0"
---

# Night Shift Spec Refiner

You write the feature draft **by hand** (your ideas, scope, decisions). This
skill's job is to **refine** that draft into a requirements doc the autonomous
Night Shift can implement — not to author the feature.

## Prime directive: REFINE, don't generate

- **The doc contains ONLY what you wrote plus your answers to its gap questions
  — nothing else.** Reading reference PRDs, existing code, or the conventions
  doc is allowed *only to discover gaps to ask about* — never to import scope,
  features, or implementation decisions you didn't state or confirm.
- **Preserve content, intent, and decisions.** Keep clear wording; reorganize
  and tighten without rewriting the author's voice away.
- **Never invent product behavior.** When something is missing or ambiguous,
  ASK — that is how the doc gets robust. Only defer to **Open Questions** what
  genuinely can't be answered yet; never paper over a gap with an assumption.
- **The night-shift layers are derived, not additive.** Test scenarios cover
  only stated/confirmed behavior; the contracts checklist only flags which
  EXISTING rules apply; commit slices only sequence the stated scope.
- If the draft is thin, say so and ask — don't inflate it.

## Workflow

1. **Locate the draft** — path arg, else the newest `*.md` in
   `nightshift/ramblings/` (ignore `_TEMPLATE.md`, `README.md`, `processed/`).
   None found → ask the author to drop one in and stop.
2. **Light research** — read the conventions doc; resolve referenced files with
   Grep/Glob just enough to make paths concrete. Don't expand scope. If the
   draft references mockup/screenshot images, `Read` each (authoritative UI
   input; ask if a referenced image is missing).
3. **Hunt for gaps and ASK** — read adversarially for undefined outcomes, edge
   cases (concurrency, permissions, empty/zero/huge inputs, failure paths),
   missing acceptance criteria, ambiguous scope. Ask in batches via
   AskUserQuestion (concrete options + a recommended default), several rounds if
   needed. Fold answers back in. Only then route true deferrals to Open
   Questions — it is not a dumping ground for fillable gaps.
4. **Write** `docs/YYYY_MM_DD_<slug>/requirements.md` using the structure below;
   omit sections the draft gives no basis for. Copy any referenced mockups into
   `docs/YYYY_MM_DD_<slug>/assets/`, embed them with `![](assets/<file>)`, and
   rewrite paths so the spec + images stay co-located on the branch (the
   `nightshift/` inbox is usually git-ignored — don't leave mockups only there).
5. **Archive** the draft to `nightshift/ramblings/processed/`.
6. **Arm behind the gate** — append to `nightshift/TODOS.md`:
   `- draft: <Feature> — docs/YYYY_MM_DD_<slug>/requirements.md`. Tell the
   author to review it and delete `draft:` when ready.
7. **Summarize** — doc path, remaining Open Questions, and the one action to arm
   it. Commit nothing.

## Refined document structure

**Required:**
- **1. Overview** — what it does, the user-facing outcome, which area.
- **2. Behavior / Functional Requirements** — refined into clear, numbered,
  testable statements; keep the author's examples.
- **3. Acceptance Criteria & Test Scenarios** *(Night-Shift critical)* —
  given/when/then with EXACT expected results (status codes / outputs), the
  complete inputs needed, and where tests should live. Cover the author's edge
  cases as explicit scenarios.
- **4. Scope Boundaries** — In scope / Out of scope / Do NOT touch (taken from
  the draft; never widen or narrow scope the author set).

**Conditional** (only with a basis in the draft): **5. Data Model / API
Changes**, **6. References** (`File | Why it matters`).

**Required (last):**
- **7. Contracts to Respect** — tick the repo contracts this feature touches and
  name the reviewer persona for each:

<<CONTRACTS_CHECKLIST>>

- **8. Suggested Commit Slices** — small, independently-committable units (the
  Night Shift lands ONE per commit), in build order; each with its key scenario.
- **9. Open Questions** — items the Night Shift must NOT guess on. "None" if all
  resolved.

## Anti-patterns
- Rewriting the feature into something the author didn't describe.
- Importing scope/decisions from a reference PRD or the codebase the author
  didn't state or confirm via a question.
- Dumping fillable gaps into Open Questions instead of asking.
- Removing `draft:` yourself — arming is the author's manual decision.
