---
name: review-gate
description: Used by /exloom when closing work (done, ready, shipping, pushing, opening a PR); do not start it directly. Describes the tiered review gate that blocks a push until the evidence the tier requires is in `.claude/reviews/<branch>.md`.
---

# Review Gate

When the gate is on, a `PreToolUse` hook blocks `git push` and PR creation (shell and GitHub MCP) until the tier's evidence is in `.claude/reviews/<branch>.md`. That is the only gate: nothing blocks a completion claim, freezes the working tree, or gates a source edit.

Matching is text-based and binds this session only. A benign command containing `git push` may be over-blocked: rephrase it. See [failure-modes.md](failure-modes.md) and [rationale.md](rationale.md).

Only `l1-reviewer` must cover the commit you ship; adversarial and security need only have approved somewhere on the branch. If you are enforcing something exloom does not ask for, stop.

## Tier — derived from the diff, never declared or lowered

| Change | Tier | Required |
|---|---|---|
| Docs, typo or comment only | 0 | L1 review |
| <5 files, one module, no UI/API/DB change | 1 | L1 + smoke test + proof |
| User-facing, cross-module, API, event type or public config | 2 | Tier 1 + adversarial review |
| Migration, flag cutover, deploy, auth/tenant/secrets/crypto | 3 | Tier 2 + security review + runbook + what a revert will not undo |

A change touching user input, auth, tenancy, secrets, deserialization, outbound requests, cryptography or dependencies gets the security review at any tier. A repository can teach the tier its own vocabulary in `.exloom.yml`: [repository-policy.md](repository-policy.md).

## Lane — chosen, in `**Lane:**`

- **`sprint`** — no spec, plan or fidelity audit; reviewers capped at Tier 1. Refused at Tier 3: offer `/harden`.
- **`standard`** — the full flow, and the default.
- **`certified`** — standard, with no escape hatches and a signed checklist commit.

No lane weakens the proof, the smoke test, the derived tier, or the security review a surface demands.

## What the gate checks

- **A receipt per required reviewer**, `.claude/reviews/<branch>.verdicts/<agent>.json`, written by the reviewer itself through `record-verdict.sh` and never by hand. It must read `APPROVED`. Reviewing from the agent's instructions yourself produces no receipt.
- **The tier**, derived by `lib.sh`. There is no escape hatch.
- **The proof**, from Tier 1 up unless `.claude/exloom-proof.disabled` is committed: a `proof.json` written only by `scripts/prove-change-is-tested.sh`. It runs the tests at the base (must pass), at the base with your tests (must fail), and with both (must pass). `NOT_PROVED` is answered by a test that fails without the change, never by re-running. A purely additive change needs a committed `.claude/exloom-mutation-command`.
- **The smoke test**: the system booted, the user action performed, the observed result pasted. Passing unit tests is not a smoke test.

At Tier 3 the checklist also names a committed runbook, what reverting does not fix (`nothing` is valid), and what would recover it (`NOT RECOVERABLE` with a reason is valid). Every line must be answerable by the author, on the branch, before merge.

The gate proves a reviewer ran, never that the review was good.

## Bypass

`EXLOOM_REVIEW_SKIP=1` in the user's `settings.json` `env` is the user's choice; never set it yourself. The hook writes `.claude/reviews/<branch>.bypass.json`: commit it with the change and write the reason under `## Escape hatches used`.

## Entry points

`/exloom` is the only one to start: `/review-init`, `/smoke-test` and `/review-complete` are its steps, and doing them by hand produces no receipts. `/exloom-setup` sets a repository up once.
