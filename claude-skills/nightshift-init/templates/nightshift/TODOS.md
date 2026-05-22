# Night Shift — Work Queue

Durable shared state across cold-context iterations. Each session picks the
highest-priority unchecked `- [ ]`, completes it, checks it off, and appends any
newly-discovered work as fresh `- [ ]` items.

**Convention:** items prefixed `draft:` are NOT ready and the Night Shift
ignores them. Remove the prefix to arm.

---

## Queue

<!-- Add tasks here. For the first run on a new repo, a low-risk test-hardening
     pass is a good way to prove the loop + gates before trusting features: -->

- [ ] Baseline the suite: run every command in `nightshift.conf` GATES. For each
      failure, append a dedicated `- [ ]` fix task below (test name + root-cause
      hypothesis). Commit nothing this task except this file.

---

## Backlog (leave as `draft:` until armed)

<!-- Specs produced by /nightshift-spec land here as `draft:` entries. -->
