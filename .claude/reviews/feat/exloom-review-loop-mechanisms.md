# Review Checklist — feat/exloom-review-loop-mechanisms

**Tier:** 2
**Tier rationale:** 66 files across multiple modules of the plugin (hooks, agents, scripts, skills, templates, test suite); security review added by SURFACE trigger, not tier — the diff evals a repo-tracked file and a subagent_type injection vector was found and fixed in it.
**Blast radius:** 66 files changed, 6 modules touched (hooks, agents, scripts, skills, templates, test suite), user-facing: no — but it changes the enforcement mechanism 17 gate-enabled repos depend on, so a defect here silently disables review rather than breaking visibly.
**Started:** 2026-08-31

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

## Cross-layer contract check (Tier 2+)
- Verdict receipt: `cross-layer-auditor.json` (written by exloom on dispatch)
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

## Runbook + rollback (Tier 3)
- Runbook path: <path to committed runbook.md>
- Rollback command: `<exact command>`
- Reversal proof: <test id or path, or "untestable in code" — what verifies it at deploy time>
- [ ] Runbook file exists at the path above (deploy order, health checks, signals to watch, failure modes)
- [ ] Reversal proof runs in CI on this commit

## Re-finds (the same finding reported in more than one round)

A re-find means the previous fix addressed the instance you were shown, not the
rule behind it — which is why the next round found the adjacent case. Each one
needs a decision here, naming the cite:

- `<file:line>` — FIXED THE CLASS: <name the test that quantifies over the whole
  set — every codepoint, every branch, every member — not the instance>
- `<file:line>` — GENUINELY SEPARATE: <why this defect is unrelated to the earlier
  one despite matching it>

(none, if no finding was reported twice)

## Escape hatches used
- [ ] None (default)
- Skipped steps with written justification:
  - <step name> — <one sentence why>

## Provenance
- AI-assisted: <ai-assisted>
- Model(s): <model-id>
- Directed by: <directed-by>
- Base commit: <base-sha>
- Attested: <attested-date>

## Final verdict
- [ ] All required gates passed for declared tier
- [ ] Checklist committed
- [ ] Ready to ship

Reviewed code commit: <reviewed-sha>
Attested by: <who-attests>
Date: YYYY-MM-DD

<!-- "Attested by" is the AUTHOR's self-attestation, not a reviewer's sign-off.
     Who reviewed is recorded in .claude/reviews/<branch-name>.verdicts/, by
     exloom, on real dispatches. Do not treat this line as review evidence. -->

