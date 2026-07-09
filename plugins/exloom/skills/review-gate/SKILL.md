---
name: review-gate
description: Use when closing work — when claiming done / complete / ready / shipping / about to push or open a PR — or when reviewing quality of a change before merge. Runs the tiered review gate (L1 code review, smoke test, cross-layer contract check, adversarial review, runbook/rollback for Tier 3) and refuses to mark complete until the tier's required evidence is in `.claude/reviews/<branch>.md`.
---

# Review Gate

**This is exloom's one enforced mechanism — the rest of exloom is discipline a model can skip.** Every other skill is guidance the model reads and *chooses* to follow, and sometimes it won't. This gate is different: when it is turned on, the `Stop` and `PreToolUse` hooks are run by the Claude Code harness — not by the model. The `PreToolUse` hook *physically blocks* a `git push` / PR (shell **and** GitHub MCP), and the `Stop` hook blocks a completion claim it recognizes, until the tier's evidence is in `.claude/reviews/<branch>.md`. That is the difference between *hoping* review happened and *guaranteeing* it did, and it is the part of exloom you cannot reproduce by prompting. (Enforcement is text-based command/tool matching plus the checklist's git checks: it catches the common `git push` / `gh pr create` forms and the listed GitHub MCP tools; a deliberately obfuscated shell command or a raw API call can still evade it, and — because matching is textual and fail-closed — a benign command that literally contains the words `git push` / `gh pr create` (a commit message or echo about pushing) can occasionally be over-blocked during the review window (bypass with `EXLOOM_REVIEW_SKIP=1`, or rephrase). It's a cooperating-team gate with a documented `EXLOOM_REVIEW_SKIP` bypass, not an adversarial security boundary.)

## Why this exists

Consider a large, multi-batch refactor that passed every review it was given — per-batch code-quality reviews, per-batch spec-compliance reviews, plan-deviation passes, contract-integration checks, and a full adversarial review. Every gate said APPROVED. Then one question — "how do I test this?" — surfaced a structural gap: the UI was persisting a field that no backend code ever read. The gap was invisible to every previous review because each reviewer worked from documents, specs, or single-layer code reads. Nobody booted the application. Nobody traced a value from a UI action through to an observable runtime effect. This is the failure mode the gate exists to prevent — and it is common, not exotic.

The retrospective was clear about which gates carried signal. L1 found real bugs every batch. L2 tended to rubber-stamp when the author wrote both the spec and the code. Final passes were almost entirely performative. Per-plan contract checks caught within-layer issues but were blind to the UI ↔ backend seam. The two things that would have caught the gap — an actual smoke test and a hostile adversarial pass focused on cross-layer contracts — were either skipped or too narrowly scoped.

This protocol encodes those lessons. Every change, regardless of size, needs an L1 code review and a real smoke test (booted system, executed user action, observed result). Anything user-facing or cross-module also needs a cross-layer contract grep and a hostile adversarial review. Anything touching data migration, flags, or production needs a runbook and a rollback dry-run. The checklist at `.claude/reviews/<branch>.md` is the artifact, committed with the PR; the hooks refuse to let you declare done or push without it filled.

## Tier matrix

| Blast radius | Tier | Required gates |
|---|---|---|
| Docs-only, typo-only, comment-only (no runtime code modified) | 0 | L1 code review only |
| <5 files, single module, no UI/API/DB change, internal-only | 1 | L1 + smoke test + checklist |
| User-facing OR cross-module OR new/changed API OR new event type OR new public config | 2 | Tier 1 + cross-layer contract check + adversarial review |
| Data migration OR feature-flag cutover OR production deploy OR auth/tenant/secrets/crypto change | 3 | Tier 2 + security review + runbook + rollback test + staging dry-run |

Decide tier when the plan is written. Record in the checklist's Tier field. Do not downgrade mid-flight. When uncertain, go one tier higher — the cost of an extra adversarial review is an hour; the cost of a missed integration gap in production is measured in customer-visible incidents.

**Security review is triggered by surface, not only by tier.** Any change — at any tier — that touches user input, authentication/authorization, tenancy, secrets, deserialization, server-side outbound requests, cryptography, or dependencies also runs the security review (Step 5). This matters most for AI-generated code, which introduces exactly those flaws.

## Per-step procedure

### Step 1 — L1 code review (all tiers)

Dispatch the `l1-reviewer` agent against the branch diff (or per-batch diff for large changes). L1's job is correctness, null safety, resource leaks, test quality, and style. Every finding must cite `path/to/file.ext:line`.

Prompt pattern (handled by the agent's system prompt, but useful to know):

> Review this diff for: (1) correctness bugs including off-by-one, null deref, wrong types, wrong operator; (2) resource leaks — unclosed streams, connections, subscriptions; (3) test quality — are the new tests asserting behavior or just calling methods; (4) style/consistency with neighbors. Output Critical / Important / Minor with file:line cites. No narrative — findings only.

Implementer resolves every Critical and Important, records resolution in the checklist. Minor findings may be deferred but must be listed with a reason.

### Step 2 — Smoke test (all tiers) — EVIDENCE REQUIRED

This is the step that would have caught the persisted-but-unread-field gap above. It has a strict definition:

> **Smoke test** = the operator booted the system, performed the exact user-facing action that exercises the change, and observed the user-visible result. Unit tests passing is NOT a smoke test. Compilation succeeding is NOT a smoke test. Reading code is NOT a smoke test.

Checklist evidence required:
- Exact boot command (e.g. `make run`, `docker compose up`, or your service's start command) plus any prerequisites.
- Exact user action (e.g. "opened the order form, applied a discount code, submitted, saw the total update").
- Expected observable result.
- Actual observed result — pasted log line, API response body, UI screenshot link, or DB row dump. Raw evidence.
- Pass / fail box ticked.

If the change is not user-facing (e.g. a background service refactor), the smoke test is: trigger the service, observe the expected side effect (log line, DB state change, Kafka message), paste the evidence.

`/smoke-test` walks through this interactively and fills the section with real commands and output.

### Step 3 — Cross-layer contract check (Tier 2+)

Dispatch the `cross-layer-auditor` agent. Its grep discipline is:

1. For every field the frontend persists in this change: grep the backend for reads of that field name. Report fields with zero backend readers as orphans.
2. For every new API endpoint added: grep the frontend for the URL path or the generated client call. Report endpoints with zero frontend callers as orphans.
3. For every new event type / Kafka topic / WebSocket frame type: grep for the handler. Report unhandled emissions.
4. For every new DB column: grep the code for reads (SELECT/entity field access). Report write-only columns.
5. For every new config property: grep for the property key in code. Report config that is set but never read.

Orphans are not automatically bugs — some are intentional (fields persisted for audit-only, endpoints for future clients). Each orphan must be either fixed or annotated in the checklist with the intentional-orphan reason.

### Step 4 — Adversarial review (Tier 2+)

Dispatch the `adversarial-reviewer` agent. This tends to carry the highest signal of any review type. The prompt is hostile by design and lives in the agent file; in short: assume every previous review missed things, try to break the change, look specifically for the integration gaps that per-layer reviewers couldn't see.

Implementer addresses every Blocking finding. Non-blocking findings go to the checklist with disposition (fixed / deferred with reason / won't fix with reason).

### Step 5 — Security review (Tier 3, and any change touching input / auth / secrets / deserialization / dependencies)

Dispatch the `security-auditor` agent. It runs the repo's security scanners — secrets detection, a dependency-vulnerability audit, and static analysis — and reviews the diff for the AI-generated-code failure modes: injection, missing authorization, secrets/PII exposure, insecure deserialization, SSRF, weak crypto, unsafe defaults, and hallucinated or vulnerable dependencies. Every finding carries a severity, a source→sink, and a confidence (CONFIRMED vs SUSPECTED), and the tool output is pasted as evidence.

This is a **first pass, not a guarantee** — it never certifies code "secure," only "no issues found by the checks that ran." A Critical or High finding blocks the change until it is fixed or risk-accepted in writing. Full method: `exloom:security-review`.

### Step 6 — Runbook + rollback (Tier 3 only)

Required content in the checklist:
- Runbook path (a markdown doc committed alongside the change, listing: deploy order, health checks, signals to watch, common failure modes).
- Dry-run evidence — the runbook was executed in staging, paste the relevant log lines or screenshots proving success.
- Rollback command — the exact command to undo this change.
- Rollback verification — the rollback was executed in staging, system returned to the pre-change state, paste the evidence.

An untested rollback is not a rollback; it is a wish.

## Checklist template

The canonical template lives at `templates/review-checklist.md` in this plugin. `/review-init` copies it to `.claude/reviews/<branch>.md` and pre-fills the tier, branch, and blast-radius fields.

## Failure-mode examples — what this catches, what it doesn't

### Catches

- **A persisted-but-unread field.** The UI wrote a new field to a saved record; no backend code read it. Tier 2 cross-layer contract check step 1 grep flags zero backend readers on a newly-persisted field; the adversarial review prompt explicitly requires this check.
- **A silent parser/import regression.** A refactor quietly broke file import. The smoke test step (import a real file through the UI) fails immediately. Tier 2.
- **Mid-flight feature-flag corruption.** A flag cutover left some tenants with the old code path reading new-schema DB rows. Tier 3 rollback dry-run would have shown the corruption on the staging replica.
- **Write-only DB column.** Migration added a column, entity persisted it, no query ever read it. Cross-layer contract step 4.

### Doesn't catch (known blind spots)

- **Performance regressions not visible in a single smoke run.** Load testing is out of scope.
- **Security vulnerabilities in *unchanged* code** — the security review (Step 5) covers THIS change's security surface, not the pre-existing system. Audit the whole codebase separately.
- **Third-party API contract drift** — if Stripe changes its webhook body and nothing in the diff triggers the change, the gate won't notice.
- **Race conditions that don't reproduce in single-operator smoke tests.**

For those, use dedicated tooling (load tests, chaos testing) and, for the wider system, a full-codebase security audit. The review protocol is necessary, not sufficient.

## Turn it on (per repo)

The gate is **opt-in** — exloom never blocks a repo that did not ask for it. Enable it for a repository by creating the marker file once, and commit it so the whole team gets the gate:

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

With the marker present, the hooks enforce the gate on every branch. Without it, the hooks no-op and this skill is only a (strong) recommendation.

## Provenance attestation (who/what made the change)

When the gate is on, `/review-complete` also records a **Provenance** block in the checklist — whether AI assisted, the model id, the human who directed it, and the base commit — and the hooks refuse to ship without it. Bound to the reviewed commit, this is a committed audit trail of *how* the change was produced (the kind of evidence ISO 42001 / SOC 2 auditors and cyber-insurers ask for — position it there, not on the EU AI Act, which governs synthetic media, not source code).

- **v1 (default):** the record is committed and commit-bound. Tamper-evident through git history; the model id is **self-reported** (cooperating-team trust), not independently verified.
- **v2 (opt-in):** create `.claude/exloom-provenance-signed.enabled`, and the attestation commit must be a **signed git commit** — `/review-complete` commits with `git commit -S` and the hooks `git verify-commit` it, giving verified-identity non-repudiation with your existing GPG/SSH key (no sigstore/cosign/in-toto). Verification requires the signer's key to be trusted wherever the hook runs (a documented setup step; fail-closed by design).

It is **evidence, not compliance certification**, and a branch-level declaration, not per-line attribution.

## Entry points

- `/review-init` — create the checklist for the current branch.
- `/smoke-test` — fill the smoke-test section with real commands and observed output.
- `/review-complete` — verify all required sections populated for the tier, run any missing reviewer agents, mark ready to ship.

The `Stop` hook refuses to let you claim done without the checklist complete. The `PreToolUse` hooks refuse `git push`, `gh pr create`, and the common GitHub MCP push/PR tools (`push_files`, `create_or_update_file`, `create_pull_request`, `merge_pull_request`, `delete_file`) without it — so switching from the shell to the MCP integration doesn't bypass the gate. All honor `EXLOOM_REVIEW_SKIP=1` for emergencies, logged to stderr.
