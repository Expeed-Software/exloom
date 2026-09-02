---
name: review-gate
description: Use when closing work — when claiming done / complete / ready / shipping / about to push or open a PR — or when reviewing quality of a change before merge. Runs the tiered review gate (L1 code review, smoke test, proof the change is tested, adversarial review with cross-layer contract check, a recovery plan for Tier 3) and refuses to mark complete until the tier's required evidence is in `.claude/reviews/<branch>.md`.
---

# Review Gate

**This is exloom's one enforced mechanism — the rest of exloom is guidance.** When the gate is turned on, a `PreToolUse` hook run by the Claude Code harness — not by the model — *physically blocks* a `git push` or PR (shell **and** GitHub MCP) until the tier's evidence is in `.claude/reviews/<branch>.md`. That is the difference between *hoping* review happened and *knowing* it did, and it is the part of exloom you cannot reproduce by prompting.

**One gate, at push.** Nothing blocks a completion claim, freezes the working tree during review, or gates the first source edit. Blocking the push is the one point where stopping is worth more than it costs.

Enforcement is text-based command/tool matching plus the checklist's git checks: it catches the common `git push` / `gh pr create` forms and the listed GitHub MCP tools. A deliberately obfuscated shell command or a raw API call can still evade it, and a benign command that literally contains the words `git push` can occasionally be over-blocked (bypass with `EXLOOM_REVIEW_SKIP=1`, or rephrase). It is a cooperating-team gate, not an adversarial security boundary.

## Why this exists

A change can pass every review it is given and still be broken, because reviews that work from documents, specs, or single-layer code reads share one blind spot: nobody boots the application, and nobody traces a value from a user action through to an observable effect. A field the UI persists that no backend code reads survives all of them. That failure is common, not exotic.

Two things catch it, and neither is a document review: a real smoke test, and a hostile pass aimed specifically at cross-layer contracts. Reviews that grade the author's own spec against the author's own code tend to rubber-stamp; per-layer contract checks are blind to the seam between layers.

So: every change, regardless of size, needs an L1 code review and a real smoke test — booted system, executed user action, observed result. Anything user-facing or cross-module also needs a cross-layer contract grep and a hostile adversarial review. Anything touching data migration, flags, or production needs a runbook and a statement of what reverting does not fix. The checklist at `.claude/reviews/<branch>.md` is the artifact, committed with the PR; the hooks refuse the push without it filled.

## Four rules people expect that do not exist

Sessions impose these on themselves and each one is a round multiplier.

| Not a rule | What is true |
|---|---|
| Every required reviewer must approve the **same commit** | Only `l1-reviewer` must cover the commit you ship. Adversarial and security must have run and approved *anywhere* on the branch; a later fix does not invalidate them. Requiring simultaneity means N reviewers chase a target that moves each time one of them is answered. |
| The working tree is **frozen** while a reviewer reads it | There is no freeze marker and no state machine. Do not invent one. |
| A source edit is blocked until a **plan is approved** | There is no plan gate. |
| A finding must be fixed **across its whole class**, with a test proving the class is closed | A reviewer may note that a finding looks like one of a class; it may not demand a general fix. Fixing the instance and tracking the class in a ticket is a normal answer. |

If you find yourself enforcing something on this branch that exloom does not ask for, stop. Self-imposed process is the most common cause of a branch that will not converge, and it is invisible in the checklist afterwards.

## Lanes: the tier is derived, the lane is chosen

Tiers scale *review depth* and are derived from the diff. They do not scale *ceremony*, and ceremony is what a small change cannot afford — so the lane is a separate axis, chosen rather than derived.

`**Lane:**` in the checklist, defaulting to a committed `.claude/exloom-lane`, else `standard`:

- **`sprint`** — no spec, no plan, no fidelity audit; the reviewer set is capped at Tier 1. Branch, build, prove, smoke, L1, push.
- **`standard`** — the full flow, and the default.
- **`certified`** — standard, with **no escape hatches** and a signed checklist commit.

**A lane may not weaken a safety check.** The proof receipt, the smoke test, the tier derived from the diff, receipt forgery-resistance, and the security auditor when the *surface* demands it are identical in all three. A lane changes how much happens before the code and which reviewers the ceremony asks for after it — never whether the evidence is real.

Two consequences worth stating plainly:

**Sprint is refused at Tier 3.** Migrations, auth, tenancy, secrets and crypto are exactly the stakes that earn rigour, and the tier is derived from the diff — so a migration cannot be re-labelled a weekend spike. "Earned by stakes" has to cut both ways or it is a bypass with a friendlier name.

**A Sprint branch that turns out to matter gets `/harden`, not a rewrite.** It recovers the spec from the diff that now exists, flips the lane, and names what the higher bar requires. Nothing is regenerated and no ref changes. A spec written before the code is a guess; one recovered from code that runs and passes its tests describes something real, which makes it the better review of the two.

## What the gate actually verifies

This matters more than the step list, because it is the difference between review and self-certification.

Most of the checklist is **self-attested**: you write the findings, the smoke-test output, the dispositions. The gate checks those are present and not placeholder text. It cannot check they are true. That is the honest limit of any artifact the author writes, and no amount of extra fields changes it.

Two things are **not** self-attested, and they are deliberately the two that decide everything else:

- **Reviewer dispatch.** When a reviewer subagent actually completes, a `PostToolUse` hook writes a receipt to `.claude/reviews/<branch>.verdicts/<agent>.json` naming the commit that reviewer saw. A `PreToolUse` hook denies writing that file by hand. The gate requires one receipt per reviewer the tier needs, covering the reviewed commit — so "was this reviewed?" is answered by an event the harness recorded, not by a box you ticked. Fix findings and commit? The receipt no longer covers the tip, and that reviewer runs again.
- **The tier.** `lib.sh` derives a minimum tier from the diff (the rules `/review-init` proposes) and blocks a checklist declaring less. There is no escape hatch, because the tier decides which gates apply: an escapable tier makes every other gate optional, and "this change is only Tier 1" is the specific judgment an author under time pressure gets wrong.

Reading a reviewer agent's instructions and performing the review yourself produces no receipt. That is intentional — the gate cannot tell a careful self-review from a skipped one, so it only counts what it can observe.

- **The verdict.** A receipt records what the reviewer *concluded*, read from the `VERDICT: APPROVED` / `VERDICT: REJECTED (n items)` line every reviewer agent is required to emit. `REJECTED` does not satisfy the gate, and neither does `UNKNOWN` (no readable verdict line) — a gate may not guess in the permissive direction. A receipt carrying no verdict key at all still counts, so a branch already in flight is never stranded.

- **Proof that the change is tested.** From Tier 1 up, the gate requires a `proof.json` receipt reading `PROVED` and covering the reviewed commit, written only by `scripts/prove-change-is-tested.sh`. It runs the suite at the base commit (must pass, or the proof is void), at the base with your tests added (must fail, or your tests do not notice your change), and with change and tests together (must pass). "I added tests" is an author claim; a test that passes with and without the change is the normal way that claim is false while being sincerely made.
  Two rules make the receipt worth having: the pinned `.claude/exloom-test-command` must be **committed**, because its contents are `eval`d; and an unresolvable `--base` is refused rather than recorded.

  **A purely additive change cannot satisfy this**, and that is not a test-writing problem: every test exercising a new API fails to *compile* at the base commit, which shows the tests depend on the change but not that they would notice it being wrong. Commit a `.claude/exloom-mutation-command` that exits 0 when your mutation threshold is met (PIT, Stryker, mutmut, go-mutesting) and the proof uses it instead. exloom parses no report and owns no threshold - the exit code is the whole contract.

  **Criterion coverage comes out of the same run.** Name a test after the criterion it covers - `@DisplayName("F-012/R-3/AC-2 - ...")` - and the receipt records which criteria passed *with* the change and did not pass without it, read from the runner's own JUnit XML. A test whose name claims a criterion but passes against the base source is reported as claimed-not-proved, because the name is the author's word and the run is not. Set `.claude/exloom-test-report` to a path glob only if your reports land somewhere unusual.

**Run the cheap pass often and the expensive pass once.** `l1-reviewer` runs at low effort, per commit. `adversarial-reviewer` and `security-auditor` run at medium effort, once, before push.

**Only L1 has to cover the commit you ship.** The other reviewers must have run and approved somewhere on this branch; a later fix does not invalidate them. Requiring all of them to approve the *same* commit is what produces a long review loop: a fix cancels the approvals of reviewers that were already satisfied, so every round starts over. Fix a finding, re-run L1, push.

**After three passes, the user decides.** A pass is a distinct commit that L1 reviewed. At the third the gate blocks and hands the session a report — findings per pass, which reviewers are outstanding, and a recommendation:

```
Review has run 4 passes on this branch (cap 3).

Findings by pass:
round 1: 1 critical, 0 important, 0 minor
round 2: 1 critical, 0 important, 0 minor
round 3: 0 critical, 0 important, 1 minor
round 4: 0 critical, 0 important, 1 minor

Reviewer status:
  l1-reviewer — approved earlier code, not the current tip

RECOMMENDATION: MERGE — no critical findings are open.
```

The session then asks you, with named options and the recommended one first:

- **Fix `OrderTotal.java:12`, `PromotionMapper.java:142`, then re-review** — the open Criticals, by cite
- **Merge as-is** — the open items are acceptable
- **Show me the findings first**

Pick one and the session carries it out. The recommendation comes from open Critical findings in the latest round, never from the pass count: an open Critical recommends fixing however few passes there have been, and none recommends merge however many there have been.

**The second option is fix-then-re-review, not "run another pass."** A pass does not fix anything — re-reviewing a commit nobody changed returns the previous pass's findings and spends a round doing it. If the last pass ran against the same code as the one before it, the report says so instead of counting it.

Once you choose merge, the answer is recorded in the checklist and the branch stops asking.

Change the cap by committing `.claude/exloom-max-rounds` with a number. Committed only, because raising it weakens the gate and that belongs in a diff.

What this does **not** buy: it proves a reviewer ran, never that the review was good. A dispatched `l1-reviewer` that returns "looks fine" produces a valid receipt. And anyone can disable the plugin, edit `lib.sh`, or set `EXLOOM_REVIEW_SKIP=1` — this is a cooperating-team gate, not an adversarial boundary. The change it makes is that within a cooperating session, the lazy path no longer produces a passing artifact.

## Tier matrix

| Blast radius | Tier | Required gates |
|---|---|---|
| Docs-only, typo-only, comment-only (no runtime code modified) | 0 | L1 code review only |
| <5 files, single module, no UI/API/DB change, internal-only | 1 | L1 + smoke test + proof-is-tested + checklist |
| User-facing OR cross-module OR new/changed API OR new event type OR new public config | 2 | Tier 1 + adversarial review |
| Data migration OR feature-flag cutover OR production deploy OR auth/tenant/secrets/crypto change | 3 | Tier 2 + security review + committed runbook + a three-part recovery plan |

Decide tier when the plan is written. Record in the checklist's Tier field. Do not downgrade mid-flight — the gate derives the minimum from the diff and blocks a downgrade, so this is enforced, not advised. When uncertain, go one tier higher — the cost of an extra adversarial review is an hour; the cost of a missed integration gap in production is measured in customer-visible incidents.

**Security review is triggered by surface, not only by tier.** Any change — at any tier — that touches user input, authentication/authorization, tenancy, secrets, deserialization, server-side outbound requests, cryptography, or dependencies also runs the security review (Step 5). This matters most for AI-generated code, which introduces exactly those flaws.

## Per-step procedure

### Step 1 — L1 code review (all tiers)

Dispatch the `l1-reviewer` agent against the branch diff (or per-batch diff for large changes). L1's job is correctness, null safety, resource leaks, test quality, and style. Every finding must cite `path/to/file.ext:line`.

Prompt pattern (handled by the agent's system prompt, but useful to know):

> Review this diff for: (1) correctness bugs including off-by-one, null deref, wrong types, wrong operator; (2) resource leaks — unclosed streams, connections, subscriptions; (3) test quality — are the new tests asserting behavior or just calling methods; (4) style/consistency with neighbors. Output Critical / Important / Minor with file:line cites. No narrative — findings only.

Implementer resolves every Critical and Important, records resolution in the checklist. Minor findings may be deferred but must be listed with a reason.

### Step 2 — Smoke test (all tiers) — EVIDENCE REQUIRED

This is the step that catches a persisted-but-unread field. It has a strict definition:

> **Smoke test** = the operator booted the system, performed the exact user-facing action that exercises the change, and observed the user-visible result. Unit tests passing is NOT a smoke test. Compilation succeeding is NOT a smoke test. Reading code is NOT a smoke test.

Checklist evidence required:
- Exact boot command (e.g. `make run`, `docker compose up`, or your service's start command) plus any prerequisites.
- Exact user action (e.g. "opened the order form, applied a discount code, submitted, saw the total update").
- Expected observable result.
- Actual observed result — pasted log line, API response body, UI screenshot link, or DB row dump. Raw evidence.
- Pass / fail box ticked.

If the change is not user-facing (e.g. a background service refactor), the smoke test is: trigger the service, observe the expected side effect (log line, DB state change, Kafka message), paste the evidence.

`/smoke-test` walks through this interactively and fills the section with real commands and output.

### Step 3 — Adversarial review (Tier 2+)

Dispatch the `adversarial-reviewer` agent, once, before push. This carries the highest signal of any review type. The prompt is hostile by design and lives in the agent file; in short: assume every previous review missed things, try to break the change, look specifically for the integration gaps a per-file review cannot see.

Include the cross-layer contract check in the same dispatch:

1. For every field the frontend persists in this change: grep the backend for reads of that field name. Report fields with zero backend readers as orphans.
2. For every new API endpoint added: grep the frontend for the URL path or the generated client call. Report endpoints with zero frontend callers as orphans.
3. For every new event type / Kafka topic / WebSocket frame type: grep for the handler. Report unhandled emissions.
4. For every new DB column: grep the code for reads (SELECT/entity field access). Report write-only columns.
5. For every new config property: grep for the property key in code. Report config that is set but never read.

Orphans are not automatically bugs — some are intentional (fields persisted for audit-only, endpoints for future clients). Each orphan must be either fixed or annotated in the checklist with the intentional-orphan reason.

This is the highest-yield check in the protocol, because the dominant defect shape is a producer changed without its consumer: one side of a seam was edited and the other was not.

Implementer addresses every Blocking finding. Non-blocking findings go to the checklist with disposition (fixed / deferred with reason / won't fix with reason).

### Step 5 — Security review (Tier 3, and any change touching input / auth / secrets / deserialization / dependencies)

Dispatch the `security-auditor` agent. It runs the repo's security scanners — secrets detection, a dependency-vulnerability audit, and static analysis — and reviews the diff for the AI-generated-code failure modes: injection, missing authorization, secrets/PII exposure, insecure deserialization, SSRF, weak crypto, unsafe defaults, and hallucinated or vulnerable dependencies. Every finding carries a severity, a source→sink, and a confidence (CONFIRMED vs SUSPECTED), and the tool output is pasted as evidence.

This is a **first pass, not a guarantee** — it never certifies code "secure," only "no issues found by the checks that ran." A Critical or High finding blocks the change until it is fixed or risk-accepted in writing. The full method lives in the `security-auditor` agent.

### Step 6 - What a revert will not undo (Tier 3 only)

Two lines. Both are facts about the diff, and both are answerable by the person standing here: an author, on a feature branch, before merge.

- **Runbook path** - a markdown doc committed alongside the change: deploy order, health checks, signals to watch, common failure modes. The file must exist; `/review-complete` checks.
- **What reverting does not fix** - the state a revert leaves in the new shape. Rows already rewritten, messages already sent, events consumers already received, caches rebuilt, credentials rotated. `nothing` is a valid answer and must be written rather than left blank.
- **What would recover it** - the mechanism, or `NOT RECOVERABLE` with the reason shipping anyway is right.

`NOT RECOVERABLE` is legitimate and for some changes the only true answer. It is not an escape hatch and reviewers should not argue with it. It exists so a one-way door is a decision on the record rather than a discovery made during an incident.

Do not ask here whether the recovery has been tested, whether a backup restores, or who will check at deploy. That needs an environment a feature branch does not have. **The checklist is read between now and merge and never again**, so a line addressed to a later reader is a concern dropped while writing a sentence that makes it look handled.

**Every line must be answerable by the person standing where the gate is, at the moment it fires.** If it needs a different role or a different environment, it does not belong. If it defers something, it must name the system that now owns it — a ticket, something with a trigger. `DEFERRED — tracked in PROJ-421` moves ownership somewhere real; "verify before deploy" names nothing and owns nothing.

## Checklist template

The canonical template lives at `templates/review-checklist.md` in this plugin. `/review-init` copies it to `.claude/reviews/<branch>.md` and pre-fills the tier, branch, and blast-radius fields.

## Failure-mode examples — what this catches, what it doesn't

### Catches

- **A persisted-but-unread field.** The UI wrote a new field to a saved record; no backend code read it. Tier 2 cross-layer contract check step 1 grep flags zero backend readers on a newly-persisted field; the adversarial review prompt explicitly requires this check.
- **A silent parser/import regression.** A refactor quietly broke file import. The smoke test step (import a real file through the UI) fails immediately. Tier 2.
- **Write-only DB column.** Migration added a column, entity persisted it, no query ever read it. Cross-layer contract step 4.

### Doesn't catch (known blind spots)

- **Performance regressions not visible in a single smoke run.** Load testing is out of scope.
- **Mid-flight state corruption during a cutover.** A flag cutover leaves some tenants on the old code path reading new-schema rows. Naming what a revert does not fix does not prove the system stays coherent *while* traffic is split across both paths. That is a property of a running deployment, and only a staged rollout with real traffic observation will surface it.
- **Code that lands after the adversarial pass.** Adversarial must approve somewhere on the branch, not on the tip, so fix commits made after it are never seen by it — and those are the commits most likely to touch the seam it exists to catch. This is deliberate: requiring it to re-approve every fix is what makes a branch never converge. It is still a real gap.
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

**Invoke these yourself, with the Skill tool.** They are not instructions for the user to type. Reading them and performing the steps by hand produces the same checklist file but none of the receipts, so the gate will block the push — the commands exist to cause events, not to describe them.

The `PreToolUse` hooks refuse `git push`, `gh pr create`, and the common GitHub MCP push/PR tools (`push_files`, `create_or_update_file`, `create_pull_request`, `merge_pull_request`, `delete_file`) without the checklist complete — so switching from the shell to the MCP integration doesn't bypass the gate. They honour `EXLOOM_REVIEW_SKIP=1` for emergencies, logged to stderr.
