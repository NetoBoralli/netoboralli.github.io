# Ramblings → Spec inbox

Your manual day-shift authoring lives here.

1. Copy `_TEMPLATE.md` to a feature name, e.g. `credit-memos.md`.
2. Fill it in **by hand** — your ideas, scope, and decisions.
3. Run `/nightshift-spec` (or `/nightshift-spec nightshift/ramblings/credit-memos.md`).
   It **refines** your draft — it does not invent the feature. First it hunts for
   gaps and **asks you questions** so you can fill them; then it writes
   `docs/YYYY_MM_DD_<slug>/requirements.md`, adds the night-shift layers, and
   archives your draft to `processed/`.
4. It adds the spec to `nightshift/TODOS.md` as `draft:`. **Review the doc, then
   delete `draft:`** to arm it for a night.

The skill picks the newest unprocessed `*.md` here if you don't pass a path.
`_TEMPLATE.md`, this README, and `processed/` are skipped.
