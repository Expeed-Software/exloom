---
name: review-gate
description: Use when closing work — when claiming done / complete / ready / shipping / about to push or open a PR — or when reviewing quality of a change before merge. Runs the tiered review gate (L1 code review, smoke test, proof the change is tested, adversarial review with cross-layer contract check, and at Tier 3 a security review plus what a revert will not undo) and refuses to mark complete until the tier's required evidence is in `.claude/reviews/<branch>.md`.
---

# Review Gate

**This is exloom's one enforced mechanism.** When the gate is on, a `PreToolUse` hook run by the harness, not the model, blocks `git push` or a PR (shell **and** GitHub MCP) until the tier's evidence is in `.claude/reviews/<branch>.md`.

**One gate, at push.** Nothing blocks a completion claim, freezes the working tree, or gates the first source edit.

The gate binds this session, not the repository: matching is text-based, so an obfuscated command, a push from outside Claude Code, or a raw API call gets through, and a benign command containing `git push` may be over-blocked (rephrase, or use `EXLOOM_REVIEW_SKIP=1`). See [failure-modes.md](failure-modes.md) and [rationale.md](rationale.md).

## Four rules people expect that do not exist

| Not a rule | What is true |
|---|---|
| Every required reviewer must approve the **same commit** | Only `l1-reviewer` must cover the commit you ship. Adversarial and security must have run and approved *anywhere* on the branch; a later fix does not invalidate them. |
| The working tree is **frozen** while a reviewer reads it | There is no freeze marker and no state machine. Do not invent one. |
| A source edit is blocked until a **plan is approved** | There is no plan gate. |
| A finding must be fixed **across its whole class** | Fix the instance; track the class in a ticket. |

If you are enforcing something exloom does not ask for, stop.

## Lanes: the tier is derived, the lane is chosen

`**Lane:**` in the checklist, defaulting to a committed `.claude/exloom-lane`, else `standard`:

- **`sprint`** — no spec, no plan, no fidelity audit; reviewer set capped at Tier 1. Branch, build, prove, smoke, L1, push.
- **`standard`** — the full flow, and the default.
- **`certified`** — standard, with **no workflow-step escape hatches** and a signed checklist commit. A skip under `## Escape hatches used` blocks the push. `EXLOOM_REVIEW_SKIP=1` still works on every lane and always writes a bypass receipt.

**A lane may not weaken a safety check.** The proof receipt where enabled, the smoke test, the derived tier, receipt forgery-resistance, and the security auditor when the *surface* demands it are identical in all three.

**Sprint is refused at Tier 3.** A Sprint branch that turns out to matter gets `/harden`: it recovers the spec from the diff, flips the lane, and names what the higher bar requires.

## What the gate actually verifies

The checklist text is self-attested (present, not placeholder). Four things are **not**:

- **Reviewer dispatch.** When a reviewer subagent completes, a `PostToolUse` hook writes `.claude/reviews/<branch>.verdicts/<agent>.json` naming the commit it saw. A `PreToolUse` hook denies writing that file by hand. The gate requires one receipt per reviewer the tier needs, covering the reviewed commit. Commit a fix and that reviewer runs again.

  Reviewing yourself from the agent's instructions produces no receipt. Dispatch reviewers **without a name**: a named subagent reports through the mailbox, not the tool result the hook reads, so its receipt records a launch and no verdict.

- **The tier.** `lib.sh` derives a minimum tier from the diff (the rules `/review-init` proposes) and blocks a checklist declaring less. There is no escape hatch.

- **The verdict.** A receipt records the `VERDICT: APPROVED` / `VERDICT: REJECTED (n items)` line every reviewer emits. Neither `REJECTED` nor `UNKNOWN` (no readable verdict line) satisfies the gate. **A receipt with no verdict is a launch, not a review**, and is refused; re-dispatch the reviewer without a name.

- **Proof that the change is tested.** Unless the repo has committed `.claude/exloom-proof.disabled`, the gate requires from Tier 1 up a `proof.json` receipt reading `PROVED`, covering the reviewed commit, written only by `scripts/prove-change-is-tested.sh`. The pinned `.claude/exloom-test-command` must be **committed**, because it is `eval`d; an unresolvable `--base` is refused.

  **A purely additive change cannot satisfy the three runs**: its tests do not compile at the base. Commit a `.claude/exloom-mutation-command` that exits 0 when your mutation threshold is met (PIT, Stryker, mutmut, go-mutesting) and the proof uses it instead. The exit code is the whole contract.

  **Criterion coverage comes from the same run.** Name a test after its criterion — `@DisplayName("F-012/R-3/AC-2 — ...")` — and the receipt records, from the runner's JUnit XML, which criteria passed with the change and failed without it; one passing at the base is claimed-not-proved. Set `.claude/exloom-test-report` to a path glob only if reports land somewhere unusual.

**Run the cheap pass often and the expensive pass once.** `l1-reviewer` runs at low effort, per commit. `adversarial-reviewer` and `security-auditor` run at medium effort, once, before push. Fix a finding, re-run L1, push.

The gate proves a reviewer ran, never that the review was good: [failure-modes.md](failure-modes.md).

## After three passes, the user decides

A pass is a distinct commit that L1 reviewed. At the third the gate blocks and prints findings per pass, outstanding reviewers, and a `RECOMMENDATION:` line.

Ask the user, recommended first:

- **Fix `OrderTotal.java:12`, `PromotionMapper.java:142`, then re-review** — the open Criticals, by cite
- **Merge as-is** — the open items are acceptable
- **Show me the findings first**

The recommendation follows open Criticals in the latest round, never the pass count. Re-reviewing an unchanged commit only repeats findings; fix first.

A merge answer is recorded in the checklist and settles **rounds** only. A missing, stale or rejecting reviewer still blocks after it.

Change the cap by committing `.claude/exloom-max-rounds` with a number.

## Tier matrix

| Blast radius | Tier | Required gates |
|---|---|---|
| Docs-only, typo-only, comment-only (no runtime code modified) | 0 | L1 code review only |
| <5 files, single module, no UI/API/DB change, internal-only | 1 | L1 + smoke test + proof-is-tested + checklist |
| User-facing OR cross-module OR new/changed API OR new event type OR new public config | 2 | Tier 1 + adversarial review |
| Data migration OR feature-flag cutover OR production deploy OR auth/tenant/secrets/crypto change | 3 | Tier 2 + security review + a committed runbook + what a revert will not undo |

Record the tier when the plan is written. Do not downgrade. When uncertain, go one higher.

**Teach the tier your repository's vocabulary.** Built-in Tier 3 rules match `auth`, `oauth`, `tenant`, `secret`, `crypto`, `jwt`, `apikey`, `security`, `password`, `credential`, `encrypt`, `cipher`, `rbac`, `acl`, `sso`, `saml`, `oidc`, `iam` and `migrations/`. If your code says `identity`, `membership` or `access-control`, commit an `.exloom.yml` naming those paths. Repository rules only raise a tier or add a reviewer; an invalid policy blocks the gate. See [repository-policy.md](repository-policy.md).

**Security review is triggered by surface, not only by tier.** Any change touching user input, authentication/authorization, tenancy, secrets, deserialization, server-side outbound requests, cryptography, or dependencies also runs the security review.

## Per-step procedure

### Step 1 — L1 code review (all tiers)

Dispatch the `l1-reviewer` agent against the branch diff (or per-batch diff for large changes). Every finding cites `path/to/file.ext:line`.

Resolve and record every Critical and Important. Minor findings may be deferred with a reason.

### Step 2 — Smoke test (all tiers) — EVIDENCE REQUIRED

> **Smoke test** = the operator booted the system, performed the exact user-facing action that exercises the change, and observed the user-visible result. Passing unit tests, compiling, or reading code is NOT a smoke test.

Checklist evidence:
- Exact boot command plus prerequisites.
- Exact user action.
- Expected observable result.
- Actual observed result — pasted log line, API response body, UI screenshot link, or DB row dump.
- Pass / fail box ticked.

Not user-facing: trigger the service and paste the side effect (log line, DB state, Kafka message). `/smoke-test` fills this section.

### Step 3 — Adversarial review (Tier 2+)

Dispatch the `adversarial-reviewer` agent, once, before push, with the cross-layer contract check:

1. Every field the frontend persists: grep the backend for reads. Zero readers is an orphan.
2. Every new API endpoint: grep the frontend for the path or generated client call. Zero callers is an orphan.
3. Every new event type / Kafka topic / WebSocket frame type: grep for the handler. Report unhandled emissions.
4. Every new DB column: grep for reads. Report write-only columns.
5. Every new config property: grep for the key. Report config set but never read.

Each orphan is either fixed or annotated in the checklist with the intentional-orphan reason.

Address every Blocking finding; non-blocking ones get a checklist disposition (fixed / deferred / won't fix, with reason).

### Step 4 — Prove the change is tested (Tier 1+)

```bash
PROVE="$(find ~/.claude/plugins -path '*exloom*/scripts/prove-change-is-tested.sh' | sort -V | tail -1)"
bash "$PROVE"
```

It runs the suite three times in a throwaway worktree: at the base commit (must pass, or the proof is void), at the base with your tests added (must fail, or your tests do not notice your change), and with change and tests together (must pass). It writes `proof.json` beside the reviewer receipts.

`NOT_PROVED` is answered by a test that fails without your change, never by re-running.

### Step 5 — Security review (Tier 3, and any change touching input / auth / secrets / deserialization / dependencies)

Dispatch the `security-auditor` agent; its method, scanners and finding format live in the agent file. It is a first pass, never a certification of "secure". A Critical or High finding blocks until fixed or risk-accepted in writing.

### Step 6 — What a revert will not undo (Tier 3 only)

- **Runbook path** — a committed markdown doc: deploy order, health checks, signals to watch, common failure modes. `/review-complete` checks the file exists.
- **What reverting does not fix** — state a revert leaves in the new shape: rows rewritten, messages sent, events consumed, caches rebuilt, credentials rotated. Write `nothing` rather than leaving it blank.
- **What would recover it** — the mechanism, or `NOT RECOVERABLE` with the reason shipping anyway is right.

`NOT RECOVERABLE` is legitimate. Do not ask whether recovery was tested or who checks at deploy: **every line must be answerable by the author, on the branch, before merge.** A deferral names its owner: `DEFERRED — tracked in PROJ-421`, not "verify before deploy".

## Checklist template

`templates/review-checklist.md` holds only the editable part (base branch, lane, rulings). `/review-init` and `/exloom` generate the checklist with `exloom_render_report`, which adds an evidence block rebuilt from the receipts on every run.

## Turn it on (per repo)

The gate is **opt-in**; without this committed marker the hooks no-op:

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

`/review-complete` also records a **Provenance** block — AI-assisted, model id, directing human, base commit — bound to the reviewed commit. Signed-commit option: [rationale.md](rationale.md).

## The emergency bypass

`EXLOOM_REVIEW_SKIP=1`, set in the Claude Code session env (`settings.json` `env`), not inline before the command. The hooks honour it unconditionally.

The hook writes `.claude/reviews/<branch>.bypass.json` (commit, branch, action, git identity, timestamp). Commit it with the change and write the reason under "Escape hatches used". Nothing verifies the reason.

## Entry points

- `/review-init` — create the checklist for the current branch.
- `/smoke-test` — fill the smoke-test section with real commands and observed output.
- `/review-complete` — verify all required sections for the tier, run missing reviewers, mark ready to ship.
- `/exloom-setup` — set the repo up once; print the effective configuration and why the diff derives its tier.
- `/exloom` — run the next step for this branch; `/exloom status` for one line.

**Invoke these yourself, with the Skill tool.** Doing their steps by hand produces no receipts.

The `PreToolUse` hooks refuse `git push`, `gh pr create`, and the GitHub MCP push/PR tools (`push_files`, `create_or_update_file`, `create_pull_request`, `merge_pull_request`, `delete_file`) until the checklist is complete.

## Further reading

[rationale.md](rationale.md) · [repository-policy.md](repository-policy.md) · [failure-modes.md](failure-modes.md)
