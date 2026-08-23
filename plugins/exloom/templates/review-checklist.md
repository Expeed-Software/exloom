# Review Checklist — <branch-name>

**Tier:** [0 | 1 | 2 | 3]
**Tier rationale:** <one sentence>
**Blast radius:** <N files changed, M modules touched, user-facing yes/no>
**Started:** YYYY-MM-DD

## L1 code review (all tiers)
- [ ] Dispatched l1-reviewer
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
- [ ] Dispatched cross-layer-auditor
- Grep 1 — Orphan fields (UI writes → backend reads):
- Grep 2 — Orphan endpoints (backend declares → frontend calls):
- Grep 3 — Unhandled events (emitted → handled):
- Grep 4 — Write-only DB columns (written → read):
- Grep 5 — Unread config keys (declared → read):
- Orphans requiring fix: <list, or "none">
- Intentional orphans with justification: <list, or "none">

## Adversarial review (Tier 2+)
- [ ] Dispatched adversarial-reviewer
- Blocking findings: <category + file:line + disposition, or "none">
- Non-blocking findings: <category + file:line + disposition, or "none">
- Reviewer's meta-notes: <which hostile question surfaced the most issues>

## Security review (Tier 3, or any change touching input / auth / secrets / deserialization / dependencies)
- [ ] Dispatched security-auditor
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
Signed: <Claude-session-or-human-reviewer>
Date: YYYY-MM-DD
