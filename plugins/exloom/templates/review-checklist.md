# Review Checklist — <branch-name>

**Tier:** [0 | 1 | 2 | 3]
**Tier rationale:** <one sentence>
**Lane:** standard
**Blast radius:** <N files changed, M modules touched, user-facing yes/no>
**Started:** YYYY-MM-DD

> **Tier and Lane are different axes.** The tier is derived from the diff and
> decides how deep the review goes. The lane is your choice and decides how much
> happens *before* the code: `sprint` (no spec, no plan, L1 + smoke + proof),
> `standard` (the full flow), `certified` (standard, no escape hatches, signed
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

## Runbook + rollback (Tier 3)
- Runbook path: <path to committed runbook.md>
- Rollback command: `<exact command>`
- Reversal proof: <test id or path, or "untestable in code" — what verifies it at deploy time>
- [ ] Runbook file exists at the path above (deploy order, health checks, signals to watch, failure modes)
- [ ] Reversal proof runs in CI on this commit

<!-- Keep examples OUT of the section below: exloom scans it for a cite and reads
     two lines past it for a keyword, so an example would dispose a real finding.
     Each entry is FILE:LINE followed by one of FIXED THE INSTANCE (and where the
     class is tracked), DEFERRED (with the ticket), FIXED THE CLASS (name the
     test), or GENUINELY SEPARATE (why it is unrelated). Fixing the instance and
     tracking the class is a normal answer, not a lesser one. -->

## Re-finds (the same finding reported in more than one round)

none

## Escape hatches used
- [ ] None (default)

<!-- Add a line per skipped step, in this form — the example lives in this comment
     because `<step name>` is a placeholder the gate rejects, so leaving it in the
     document blocks every branch that correctly skipped nothing:

       - Skipped steps with written justification:
         - smoke test — headless CI box, verified on staging instead

     After the round cap the gate blocks and the session asks you to choose: fix
     the open criticals, merge as-is, or see the findings first. If you choose to
     merge, record your answer here so the branch stops asking and the next
     reader sees who decided:

       - User approved at round cap — approved after 4 passes, remaining items are minor

     Do not add that line unless the user actually answered the prompt. -->

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

