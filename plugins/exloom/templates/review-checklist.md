# Review Checklist — <branch-name>

**Tier:** [0 | 1 | 2 | 3]
**Tier rationale:** <one sentence>
**Base branch:** auto
**Tier derived from:**
<one line per rule that matched, as `path` → `rule` → source; or `built-in defaults only`>
**Lane:** standard
**Blast radius:** <N files changed, M modules touched, user-facing yes/no>
**Started:** YYYY-MM-DD

> **Tier and Lane are different axes.** The tier is derived from the diff and
> decides how deep the review goes. The lane is your choice and decides how much
> happens *before* the code: `sprint` (no spec, no plan, L1 + smoke + proof),
> `standard` (the full flow), `certified` (standard, no workflow-step escape hatches, signed
> provenance). Sprint is not available at Tier 3. Omit the field and the repo
> default applies — `standard` unless `.claude/exloom-lane` says otherwise.

> Reviewer dispatch is NOT self-attested. exloom records a verdict receipt under
> `.claude/reviews/<branch-name>.verdicts/` when a reviewer subagent actually
> completes, and the gate requires one per reviewer the tier needs, covering the
> reviewed commit. Ticking a box here proves nothing and is not what is checked —
> dispatch the reviewer, then commit its receipt with this file.

## L1 code review (all tiers)
- Verdict receipt: `l1-reviewer.json` (written by exloom on dispatch — not by hand)
- Findings:
  - Critical: <file:line — problem, or "none">
  - Important: <file:line — problem, or "none">
  - Minor: <file:line — problem, or "none">
- [ ] Test-contract fidelity check (no test-lies — every `*IntegrationTest` / `*FanOutTest` / `*ContractTest` / `*EndToEndTest` / concurrency-test exercises the real contract, not a mock of the boundary it claims to verify)
- Resolution: <fixed / deferred with reason per finding>

## Smoke test (all tiers) — EVIDENCE REQUIRED
- Boot command (including prerequisites): `<exact command>`
- User action performed: `<exact steps>`
- Expected observable result: `<expected-result>`
- Actual observed result: `<paste output / screenshot link>`
- [ ] Test passed

## Proof the change is tested (Tier 1+)
- Proof receipt: `proof.json` (written only by `scripts/prove-change-is-tested.sh` — not by hand)
- Test command used: `<exact command, or "detected">`
- Result: `<PROVED / NOT_PROVED>`
- If NOT_PROVED: `<what is missing — a test that fails without this change>`

## Cross-layer contract check (Tier 2+) — part of the adversarial dispatch
- Grep 1 — Orphan fields (UI writes → backend reads):
- Grep 2 — Orphan endpoints (backend declares → frontend calls):
- Grep 3 — Unhandled events (emitted → handled):
- Grep 4 — Write-only DB columns (written → read):
- Grep 5 — Unread config keys (declared → read):
- Orphans requiring fix: <list, or "none">
- Intentional orphans with justification: <list, or "none">

## Adversarial review (Tier 2+)
- Verdict receipt: `adversarial-reviewer.json` (written by exloom on dispatch)
- Blocking findings: <category + file:line + disposition, or "none">
- Non-blocking findings: <category + file:line + disposition, or "none">
- Reviewer's meta-notes: <which hostile question surfaced the most issues>

## Security review (Tier 3, or any change touching input / auth / secrets / deserialization / dependencies)
- Verdict receipt: `security-auditor.json` (written by exloom on dispatch)
- Tools run (and unavailable): <secrets / dep-audit / static — ran or missing, one-line result each>
- Findings: <severity + category + file:line + disposition, or "none found by the checks run">
- New dependencies verified real (not hallucinated / typo-squatted): <list, or N/A>
- Note: first pass only — not a security guarantee.

## What a revert will not undo (Tier 3)

A committed runbook, and two lines. Both lines are facts about this diff and both
are answerable before merge. Not a recovery plan, and not a task for a later
reader.

- Runbook path: <path to committed runbook.md>
- **What reverting does not fix** - the state a revert leaves in the new shape:
  <rows rewritten / messages sent / events already consumed / caches rebuilt / credentials rotated / nothing>
- **What would recover it**:
  <the mechanism, e.g. restore the database from backup / replay from X / repaired by hand with this procedure / NOT RECOVERABLE and why shipping anyway is right>

- [ ] Runbook file exists at the path above (deploy order, health checks, signals to watch, failure modes)

NOT RECOVERABLE is a legitimate answer and sometimes the only true one - a
migration that drops values, an email already sent. It exists so a one-way door
is a decision on the record, not a discovery made during an incident.

## Re-finds (the same finding reported in more than one round)

One entry per repeated finding: the cite, then one of FIXED THE INSTANCE (say
where the class is tracked), DEFERRED (with the ticket), FIXED THE CLASS (name
the test), or GENUINELY SEPARATE (why it is unrelated). Fixing the instance and
tracking the class is a normal answer, not a lesser one.

none

## Escape hatches used
- [ ] None (default)

Each skipped step goes on its own line as a list item, naming the step and the
reason. If you answered the round-cap prompt by choosing to merge, record that
answer here as a list item reading "User approved at round cap", an em dash, then
their words - the branch stops asking once it is there, and the next reader sees
who decided. Do not write that line unless they actually answered.

## Provenance
- AI-assisted: <ai-assisted>
- Model(s): <model-id>
- Directed by: <directed-by>
- Base commit: <base-sha>
- Attested: <attested-date>
- Policy fingerprint: <policy-fingerprint>

## Final verdict
- [ ] All required gates passed for declared tier
- [ ] Checklist committed
- [ ] Ready to ship

Reviewed code commit: <reviewed-sha>
Attested by: <who-attests>
Date: YYYY-MM-DD



