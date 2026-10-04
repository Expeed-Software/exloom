# exloom

**A review gate that is actually enforced, and the evidence to back it.**

Claude Code already plans, tests and reviews its own work without being told. What it cannot do is produce evidence about itself that anyone else should trust. exloom produces that evidence — a spec with numbered criteria, a proof that your tests notice your change, and a receipt naming which reviewer saw which commit — then blocks `git push` until it exists.

Most of exloom is guidance a model reads and follows. One part is enforcement: when a repository opts in, the Claude Code harness — not the model — refuses the push.

## Requirements

- Claude Code with plugin support.
- **Git.** The gate binds evidence to commits, so it needs history to check.
- **Bash.** On Windows, Claude Code runs plugin hooks through Git Bash. If you run the proof or lint scripts by hand, use Git Bash rather than WSL or PowerShell.
- **`jq` or `python3`**, for the full gate. Without either, the push block still works but falls back to coarse text matching, which can occasionally over-block a benign command that mentions `git push`. Git Bash bundles neither — install one if you want the complete gate.

## Install

```
/plugin marketplace add https://github.com/Expeed-Software/exloom
/plugin install exloom@exloom
```

Or from a terminal: `claude plugin marketplace add https://github.com/Expeed-Software/exloom`, then `claude plugin install exloom@exloom`.

Updating requires a session restart, not just a reload — hooks are read at session start.

## Quick start

1. `/exloom-setup` — once per repository: turns the gate on, pins your test command, and commits the settings.
2. `/exloom` — on any feature branch: runs the next step (review, fix, rulings, proof, report) until the branch can be pushed. `/exloom status` prints where it stands in one line.

[How it works](HOW-IT-WORKS.md) has the lanes and every step `/exloom` runs, for when you want to run one yourself.

## What the gate actually verifies

This matters more than the step list, because it is the difference between review and self-certification.

The checklist is **generated from receipts**: exloom writes the evidence block — derived tier, reviewed commit, criteria matrix, reviewer verdicts, findings, smoke evidence, provenance. People write only rulings, and the base branch when exloom cannot find one.

Four things are **not** the author's to write, and they decide everything else:

- **Reviewer dispatch is recorded, not claimed.** When a reviewer subagent completes, a hook writes `.claude/reviews/<branch>.verdicts/<agent>.json` naming the commit it saw and the verdict it reached. Another hook refuses to let that file be written by hand. The receipt names the commit at dispatch, so a commit made while the reviewer runs is not covered by its approval.
- **The tier is derived from the diff.** A migration or an auth, tenancy, secrets or crypto path earns Tier 3; a deployment or API surface or a five-file blast radius earns Tier 2. There is no tier field to argue with, and a branch whose base exloom cannot find is blocked until the checklist names it.
- **The proof is an experiment.** `prove-change-is-tested.sh` runs your suite at the base commit, then at the base with your tests added, then with change and tests together. If your tests pass without your change, they do not test it. It costs zero model tokens and it is the highest-value thing here.
- **The verdict is read, not assumed.** A receipt records `APPROVED` or `REJECTED`, and the latest one counts. A rejection is closed by a ruling on each of its findings, not by asking again; a report with no readable verdict line never passes.

**Only L1 must cover the commit you ship.** Adversarial and security must have run and approved somewhere on the branch; a later fix does not invalidate them. Requiring every reviewer to approve the same moving commit is what produces branches that never converge.

After every reviewer completes, the gate says where it stands — the tier it derives, which receipts are current, what is still unfilled. A satisfied gate is one line; anything actionable is a marked block. You do not have to run a command to learn the state.

## Turn on the gate

Off by default. exloom never blocks a repo that did not ask for it. Run `/exloom-setup` once: it creates the `.claude/exloom-gate.enabled` marker, pins and dry-runs the test command, checks that review files are not git-ignored, and asks about strict mode. Commit what it writes and the whole team has the gate.

It applies to **feature branches only** — work committed directly to `main`, `master`, `dev` or `develop` is deliberately not gated, so start on a branch. A repo can extend or narrow that with committed glob files: `.claude/exloom-protected-branches` and `.claude/exloom-skip-branches`. Both are honoured only when committed, and every skip is logged.

Optional, all committed:

| File | Effect |
|---|---|
| `.claude/exloom-lane` | the repo's default lane |
| `.claude/exloom-strict` | strict mode: every branch on the Certified lane |
| `.claude/exloom-reviewer-model` | `<reviewer>: <model>` lines; every reviewer runs on Opus unless listed |
| `.claude/exloom-max-rounds` | fix rounds per plan task, default 3 |
| `.claude/exloom-proof.disabled` | turns the proof off, for a suite that cannot run from tracked files alone |
| `.claude/exloom-test-command` | the command the proof runs — pin one that is valid at any base, not one naming this branch's test classes |
| `.claude/exloom-test-patterns` | extra globs, one per line, for files the proof should treat as tests |
| `.claude/exloom-test-report` | where the runner writes JUnit XML, if it is somewhere unusual |
| `.claude/exloom-mutation-command` | proves a purely additive change, which the three-run proof cannot |
| `.claude/exloom-provenance-signed.enabled` | require a signed checklist commit |

Pin `.claude/exloom-test-command` in every repo. Auto-detection guesses, and for some stacks the guess hangs or tests nothing:

| Stack | Pinned command |
|---|---|
| Angular | `npx ng test --watch=false --browsers=ChromeHeadless` (plain `npm test` watches and opens a browser) |
| React (Vite / Vitest) | `npx vitest run` |
| React (CRA / Jest) | `CI=true npm test` |
| Strapi | `npm test`, once the repo defines a test script; Strapi scaffolds none |
| .NET | `dotnet test <App>.sln` |
| Flutter | `flutter test` |
| Java | `./gradlew test --rerun-tasks` or `./mvnw -q test` |

The proof records one of four results: `PROVED`; `NOT_PROVED`, which blocks; `NOT_APPLICABLE`, when the tests do not compile without the change, which passes at every tier and is reported as the weakest result; or `NO_NEW_BEHAVIOUR`, when no test changed, the diff only removes code and the suite passes at the tip, which at Tier 2–3 also needs a `- Proof: deletion only — <reason>` line from the user in the checklist.

**Upgrading from 5.x:** the proof is now on whenever the gate is on. `.claude/exloom-proof.enabled` no longer does anything; a repo that ran without the proof must either pin a working `.claude/exloom-test-command` or commit `.claude/exloom-proof.disabled`.

Smoke evidence: for a CLI or API change at Tier 0–2, `/smoke-test` runs the check through the plugin's `scripts/record-smoke.sh`, which records the command, exit code and output as a receipt. A UI change or Tier 3 needs a result pasted under `## Smoke test`.

Emergency bypass: `EXLOOM_REVIEW_SKIP=1` in your Claude Code session env. It is honoured unconditionally, and records itself in `.claude/reviews/<branch>.bypass.json` — commit that with the change so the bypass is findable afterwards.

### Teaching the tier your repository's vocabulary

The built-in Tier 3 rules match `auth`, `oauth`, `tenant`, `secret`, `crypto`, `jwt`, `apikey`, `security`, `password`, `credential`, `encrypt`, `cipher`, `rbac`, `acl`, `sso`, `saml`, `oidc`, `iam` and `migrations/`, in any case and across camelCase. A codebase that calls the same thing `identity`, `access-control` or `membership` derives a *lower* tier for a change that should be the highest one — and the tier is the one thing with no escape hatch, because it decides which gates apply.

Commit an `.exloom.yml` at the repo root:

```yaml
version: 1

risk:
  tier3:
    paths:
      - "**/identity/**"
      - "**/access-control/**"
  tier2:
    paths:
      - "**/integration/**"

reviewers:
  require:
    security-auditor:
      paths:
        - "**/identity/**"
```

Repository rules are **additive only** — they raise a tier and add a reviewer, and nothing in the file can lower either. Built-in rules always run; the effective tier is the higher of the two. An invalid policy **blocks** rather than falling back to the defaults, because a rule that silently failed to load is how a security check everyone believes in turns out never to have run.

`/exloom-setup` prints the effective configuration and why the current diff derives the tier it does. The reasoning is also written into the checklist, so a PR reader sees it without running anything.

## Try it in two minutes

1. Install exloom and run `/exloom-setup`.
2. `git checkout -b try/exloom-gate`, make a small code change, **commit it**.
3. `/exloom` — creates the checklist, runs the proof and the smoke test, dispatches the reviewers and records the reviewed commit, until it reports the branch ready.
4. `git push` is allowed.
5. Make **another** code commit without re-reviewing, then push again — **blocked**. The review no longer covers the tip.

Step 5 is the point: the review is bound to the exact commit it reviewed, not to the existence of a checklist.

Two more, because they are what stops a checklist being self-written:

6. Try to create `.claude/reviews/<branch>.verdicts/l1-reviewer.json` by hand — **denied**. Reading it is not.
7. Touch `auth/` or a migration — the branch derives Tier 3 and the gate asks for all three reviewers.

## When the review will not converge

Every loop is bounded:

- **Rulings end a rejection.** Each finding gets `PARKED`, `DEFERRED <ticket>` or `FIXED` under `## Rulings`; at Tier 3 and in strict mode a ruling on a Critical quotes the user.
- **Re-review checks the fix, not the branch.** From round 2 a reviewer verifies its earlier findings and the fix range only.
- **Minor findings go to a ledger**, `<branch>.ledger.md`, and never start another round.
- **A separate fixer** makes the smallest fix at the cited line; the main session cannot commit code while findings are unruled.
- **Budgets are enforced at dispatch:** `.claude/exloom-max-rounds` fix rounds per plan task (default 3), and one whole-branch review plus one verify pass per reviewer. A refused dispatch is answered with rulings; if the user wants another round anyway, a committed `- Extra round — "<their words>"` allows one, at that code.

## What's inside

- **9 skills** — `brainstorming`, `planning-for-handoff`, `isolating-execution`, `executing-handoff-plans`, `auditing-plan-fidelity`, `review-gate`, `capturing-learnings`, `authoring-claude-md`, and `using-exloom` (the index).
- **4 agents** — `l1-reviewer` per plan task and once over the branch; `adversarial-reviewer` and `security-auditor` once, before push (the adversarial dispatch carries the cross-layer contract check); `fixer`, which applies the smallest fix for findings it is given.
- **7 commands** — `/exloom`, `/exloom-setup`, `/review-init`, `/smoke-test`, `/review-complete`, `/harden`, `/review-cleanup`.
- **3 scripts** — `prove-change-is-tested.sh`, `record-smoke.sh`, and `lint-spec.sh` (gapless refs, a criterion under every requirement, no placeholders).
- **6 hooks** — record a receipt on real dispatch, deny writing one by hand, enforce review budgets at dispatch, keep code commits to the fixer during the fix loop, block the push without evidence, announce the flow at session start.
- **2 templates** — the editable part of the review checklist, and the spec format.

## Honest scope

- **Only the gate enforces.** Plan discipline, test-first and review quality are strong defaults, not guarantees. Turn the gate on for the part that genuinely cannot be skipped.
- **It proves a reviewer ran, not that the review was good.** A determined author can disable the plugin or use the documented bypass. It is a cooperating-team gate, not an adversarial security boundary. What changes is that the lazy path no longer produces a passing artifact.
- **The push matcher is textual.** It covers `git push`, `gh pr create` and the common GitHub MCP push/PR tools, so switching to MCP does not dodge it. A push through another MCP server, a raw API call, or a deliberately obfuscated command could still slip by — and being fail-closed, it can occasionally over-block a benign command containing the words `git push`.
- **The security review is a first pass, not a guarantee.** It runs the scanners a repo has — secrets, dependency audit, static analysis — and reviews the diff for how AI-written code commonly fails. It never certifies code secure, its coverage is only as good as the tools installed, and it does not replace SAST, DAST or a pentest.
- **Provenance is an audit trail, not a certificate.** Each gated change records AI-assisted, model, who directed it, and the base commit, bound to the reviewed commit. The model id is self-reported. The opt-in signed mode adds verified identity with your existing key — no sigstore or cosign.
- **Adversarial approval is bounded.** It must approve somewhere on the branch, not on the tip, so commits landing after it are not seen by it. That is deliberate — the alternative was branches that never converge — but it is a real coverage gap, and the fix commits it misses are the ones most likely to touch the seam it exists to catch.
- **Brownfield-first.** Your existing conventions win. exloom defers to the repo's `CLAUDE.md`; its defaults only fill gaps.
- **Claude Code only, for now.**

## License

[MIT](../../LICENSE).
