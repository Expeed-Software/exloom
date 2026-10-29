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
- **The proof is an experiment.** `prove-change-is-tested.sh` runs your tests at the base commit, then at the base with your tests added, then with change and tests together. If your tests pass without your change, they do not test it. It costs zero model tokens and it is the highest-value thing here. It runs only the tests your diff touches, which is why it takes seconds; Certified and strict mode keep the whole suite.

### What the full-suite evidence is, and is not

Where committed `.claude/exloom-ci` says `none`, the gate requires a passing receipt from `record-full-suite.sh`, which runs the suite and records the command, its exit code and the commit. The receipt is agent-run and self-attested, exactly like a pasted smoke test: exloom records that a run happened and what it returned, not that the result is honest. A repository with CI gets the stronger guarantee from branch protection, which exloom neither sees nor claims to enforce. A receipt stays valid while only documentation (`.md`, `.mmd`, and anything in a committed `.claude/exloom-doc-patterns`) or comment-only source changes land on top.

### What the reviewers can and cannot do

The four reviewers — L1, adversarial, security and spec — have no file-editing tools. That is a narrower claim than read-only: they keep `Bash` because a review reads history with `git`, and `Bash` can write. What they cannot do is create a worktree; a hook refuses it by agent type and names `git diff` and `git show` instead, so reviewers stop leaving working copies behind.

A reviewer is dispatched, never resumed. Messaging one is refused, because a resumed reviewer carries its own earlier verdict and the session's framing into the next pass and leaves no receipt of its own. A verify pass is a fresh dispatch in `MODE: VERIFY <from>..<to>`.

The block reaches the three code reviewers two ways: by name, and by agent id resolved through the branch's recorded dispatches. The spec reviewer is caught **by name only** — it is advisory, so it is deliberately absent from the review log that makes ids resolvable. A message to any agent the branch did not dispatch as a reviewer, the fixer included, is allowed.

The spec reviewer is advisory throughout: it reads the spec and the code but never the conversation, reports under `## Spec review`, and does not gate, count as a review round, or get repeated at the gate.

### Raising the floor is itself a Tier 3 change

`.claude/exloom-min-tier` turns the gate off below the tier it names, so changing any `.claude/exloom-*` setting derives Tier 3 — nobody can add a floor and skip the gate in the same push. `/exloom-setup` asks before writing one, writes it on its own branch, and that branch reaches the main line through the normal Tier 3 review and a pull request, never a direct commit. Every skip writes `.claude/reviews/<branch>.skip.json` naming the derived tier, the floor, and who set it in which commit.

### Three ways a proof can fail to conclude

| | Which run | What it means | Exit |
|---|---|---|---|
| `PROOF VOID` | 1 | The suite does not pass at the base commit. Nothing can be concluded about your tests, because the base or the environment is already broken. | 1 |
| `PROOF_ERROR` | 2 | Your tests ran at base and failed, but the report says they neither asserted nor failed to compile — the run itself broke, on a fixture, a config or the harness. Whether your tests notice your change is unknown. | 2 |
| `NOT_APPLICABLE` | 2 | Your tests could not compile without the change, because they name code it introduces. That shows they depend on the change, not that they would notice it being wrong. Recorded as the weakest of the three methods. | 0 |

`PROOF_ERROR` is reached only from a machine-readable report — JUnit XML `errors` against `failures`, a TRX `Counters` row, Jest's `testExecError`, a `flutter --machine` error event. Where no such report exists, exloom has no opinion and falls back to the text check it has always used, which can reach `NOT_APPLICABLE` but never `PROOF_ERROR`. The receipt records which path was taken as `classification`.
- **The verdict is read, not assumed.** A receipt records `APPROVED` or `REJECTED`, and the latest one counts. A rejection is closed by a fix the verify marks ADDRESSED, or by the user's ruling on what stays open; a report with no readable verdict line never passes.

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
| `.claude/exloom-not-testable-patterns` | extra globs, one per line, for files the proof should treat as not testable |
| `.claude/exloom-docs` | where the reference docs live, when not `docs/db/`, `docs/api/`, `docs/data-model/`, `docs/architecture/`: one `<doc-dir>: <code globs>` line per doc |
| `.claude/exloom-doc-patterns` | extra globs, one per line, for document types in the reference-doc folders that need no re-review (e.g. `*.puml`) |
| `.claude/exloom-test-report` | where the runner writes JUnit XML, if it is somewhere unusual |
| `.claude/exloom-mutation-command` | proves a purely additive change, which the three-run proof cannot |
| `.claude/exloom-provenance-signed.enabled` | require a signed checklist commit |
| `.claude/exloom-ci` | `github`, `azure` or `none`. With CI, the full suite leaves the gate and branch protection carries it; with `none`, the gate requires a recorded `record-full-suite.sh` receipt before the push |
| `.claude/exloom-min-tier` | the tier below which the gate does not apply, capped at 2 so Tier 3 is never skippable. Ignored entirely under Certified and in strict mode |
| `.claude/exloom-fast-command` | the compile or type-check the fast check runs after each task; advisory, never blocking |
| `.claude/exloom-test-select` | one line with a `{tests}` placeholder, for a runner whose selection syntax exloom does not know |

Pin `.claude/exloom-test-command` in every repo. Auto-detection guesses, and for some stacks the guess hangs or tests nothing:

| Stack | Pinned command |
|---|---|
| Angular | `./node_modules/.bin/ng test --watch=false --browsers=ChromeHeadless` (plain `npm test` watches and opens a browser) |
| React (Vite / Vitest) | `./node_modules/.bin/vitest run` |
| React (CRA / Jest) | `CI=true npm test` |
| Strapi | `npm test`, once the repo defines a test script; Strapi scaffolds none |
| .NET | `dotnet test <App>.sln` |
| Flutter | `flutter test` |
| Java | `./gradlew test --rerun-tasks` or `./mvnw -q test` |

The proof records one of these results:

- `PROVED` or `PROVED_BY_MUTATION`: passes.
- `NOT_PROVED`: blocks.
- `NOT_APPLICABLE`: the tests do not compile without the change. Passes at every tier, reported as the weakest result.
- `NOT_TESTABLE`: every changed file is a style, asset, lockfile, dependency manifest or config file (`*.css`, `*.scss`, `*.less`, images, fonts, `package.json`, `*.lock`, `pom.xml`, `*.csproj`, `pubspec.yaml`, `*.yml`, `*.yaml`, `*.json`, plus `.claude/exloom-not-testable-patterns`). Passes at every tier; a dependency change still gets the security auditor.
- `TESTS_ONLY`: only tests changed. Passes at every tier.
- `NO_NEW_BEHAVIOUR`: no test changed, the diff only removes code and the suite passes at the tip. At Tier 2–3 it also needs a `- Proof: deletion only — <reason>` line from the user.
- `NO_TEST_CHANGED`: no test changed and the suite passes at the tip. Passes as a refactor with a committed `- Proof: refactor — <reason>` line from the user; `/exloom` asks.

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

- **Every fix is verified, and the user rules on what is left.** After a fix the reviewer runs in verify mode; findings it marks `ADDRESSED` close on their own. Each one still `NOT ADDRESSED` goes to the user with the reviewer's reason: fix again, `PARKED` (ignore) or `DEFERRED <ticket>` (fix later), under `## Rulings`; at Tier 3 and in strict mode a ruling on a Critical quotes the user.
- **Re-review checks the fix, not the branch.** From round 2 a reviewer verifies its earlier findings and the fix range only.
- **Minor findings go to a ledger**, `<branch>.ledger.md`, and never start another round.
- **A separate fixer** makes the smallest fix at the cited line; the main session cannot commit code while findings are unruled.
- **Budgets are enforced at dispatch:** `.claude/exloom-max-rounds` fix rounds per plan task (default 3), and one whole-branch review plus one verify pass per reviewer. A verify after a code change is never refused, so the last fix always gets one. A refused dispatch is answered with rulings; if the user wants another round anyway, a committed `- Extra round — "<their words>"` allows one, at that code.
- **Merging main costs no review.** A merge of the base branch alone keeps the L1 approval, the proof and the agent-run smoke receipt. Afterwards the verify range and the growth limit count only the branch's own changes, not main's. A conflicted merge falls back to the full diff.
- **Reference docs are warned on, never blocked.** When code behind an existing `docs/db/`, `docs/api/` or `docs/data-model/` changes without the doc, and without a `- Doc impact: none — <reason>` line, the push shows a warning. A commit touching only document files in the doc folders (`.md`, `.mmd`, `.txt`, `.adoc`, `.rst`, Office files, `.pdf`, `.drawio`, images, plus `.claude/exloom-doc-patterns`) keeps the L1 approval; anything else there, such as an OpenAPI or SQL file, needs review.
- **Tags are not branches.** `git push origin v1.0.0` for an existing tag, and `git push --tags`, push no branch code and are not gated.

## What's inside

- **10 skills** — `brainstorming` (with a UI mock step for new screens), `planning-for-handoff`, `isolating-execution`, `executing-handoff-plans`, `auditing-plan-fidelity`, `review-gate`, `capturing-learnings`, `authoring-claude-md`, `maintaining-reference-docs`, and `using-exloom` (the index).
- **4 agents** — `l1-reviewer` per plan task and once over the branch; `adversarial-reviewer` and `security-auditor` once, before push (the adversarial dispatch carries the cross-layer contract check); `fixer`, which applies the smallest fix for findings it is given.
- **7 commands** — `/exloom`, `/exloom-setup`, `/review-init`, `/smoke-test`, `/review-complete`, `/harden`, `/review-cleanup`.
- **3 scripts** — `prove-change-is-tested.sh`, `record-smoke.sh`, and `lint-spec.sh` (gapless refs, a criterion under every requirement, no placeholders).
- **6 hooks** — record a receipt on real dispatch, deny writing one by hand, enforce review budgets at dispatch, keep code commits to the fixer during the fix loop, block the push without evidence, announce the flow at session start in a repository with the gate on.
- **2 templates** — the editable part of the review checklist, and the spec format.

## Honest scope

- **Only the gate enforces.** Plan discipline, test-first and review quality are strong defaults, not guarantees. Turn the gate on for the part that genuinely cannot be skipped.
- **It proves a reviewer ran, not that the review was good.** A determined author can disable the plugin or use the documented bypass. It is a cooperating-team gate, not an adversarial security boundary. What changes is that the lazy path no longer produces a passing artifact.
- **The push matcher is textual.** It covers `git push`, `gh pr create` and five GitHub MCP tools (`push_files`, `create_or_update_file`, `delete_file`, `create_pull_request`, `merge_pull_request`) under exactly two server prefixes: `mcp__github__` and `mcp__plugin_github_github__`. A GitHub server installed under any other name is not gated, and no other connector's tools are. A push through such a server, a raw API call, or a deliberately obfuscated command could still slip by — and being fail-closed, it can occasionally over-block a benign command containing the words `git push`.
- **The security review is a first pass, not a guarantee.** It runs the scanners a repo has — secrets, dependency audit, static analysis — and reviews the diff for how AI-written code commonly fails. It never certifies code secure, its coverage is only as good as the tools installed, and it does not replace SAST, DAST or a pentest.
- **Provenance is an audit trail, not a certificate.** Each gated change records AI-assisted, model, who directed it, and the base commit, bound to the reviewed commit. The model id is self-reported. The opt-in signed mode adds verified identity with your existing key — no sigstore or cosign.
- **Adversarial approval is bounded.** It must approve somewhere on the branch, not on the tip, so commits landing after it are not seen by it. That is deliberate — the alternative was branches that never converge — but it is a real coverage gap, and the fix commits it misses are the ones most likely to touch the seam it exists to catch.
- **Brownfield-first.** Your existing conventions win. exloom defers to the repo's `CLAUDE.md`; its defaults only fill gaps.
- **Claude Code only, for now.**

## License

[MIT](../../LICENSE).
