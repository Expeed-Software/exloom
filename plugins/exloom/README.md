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

## Pick a lane before you pick a step

Rigour is earned by stakes. Running the full flow on a null check is how a one-line fix becomes a feature, so the ceremony scales separately from the review.

| Lane | Before the code | After it | Declared |
|---|---|---|---|
| **Sprint** | nothing | L1, smoke test, proof | `**Lane:** sprint` |
| **Standard** | a spec and a plan | whatever the tier requires | the default |
| **Certified** | a spec and a plan | tier's requirements, no workflow-step escape hatches, signed commit | `**Lane:** certified` |

"No workflow-step escape hatches" means the gate refuses a Certified checklist that records a skipped step under `## Escape hatches used` — a step you chose not to do is not a step you may write your way past. It does not mean the branch cannot be pushed: `EXLOOM_REVIEW_SKIP=1` still bypasses the hooks on any lane, and always writes a bypass receipt. One is a workflow decision the gate reads; the other is an out-of-band override that leaves a trace.

The lane is your choice; the **tier** is derived from the diff and decides how deep the review goes. They are different axes: a migration is Tier 3 whatever lane you are on, and **Sprint is refused at Tier 3** — those are the stakes that earn the full flow.

Set a repo default in a committed `.claude/exloom-lane`, or per branch in the checklist. Absent both, it is `standard`, so nothing changes for a repo that does not opt in.

A Sprint branch that turns out to matter gets `/harden`: it recovers the spec from the diff that now exists, raises the lane, and names what the higher bar requires. Nothing is regenerated.

## The loop

| # | Step | Run | Produces |
|---|---|---|---|
| 1 | Decide what to build | `exloom:brainstorming` | a spec — problem, approach, numbered requirements, a criterion each |
| 2 | Turn it into a plan | `exloom:planning-for-handoff` | a plan — exact files, tasks citing the criteria they serve |
| 3 | Get on a branch | `exloom:isolating-execution` | a feature branch, because the gate skips protected ones |
| 4 | Start the record | `/review-init` | `.claude/reviews/<branch>.md` with a tier and a lane |
| 5 | Build it | `exloom:executing-handoff-plans` | the code — not more, not less; deviations logged |
| 6 | Prove the tests notice it | `scripts/prove-change-is-tested.sh` | `proof.json` — PROVED, or the reason it is not |
| 7 | Check for drift | `exloom:auditing-plan-fidelity` | criteria with no task, tasks with no criterion, files no task called for |
| 8 | Run it | `/smoke-test` | real output from the real thing |
| 9 | Review | `/review-complete` | reviewer receipts, findings, dispositions |
| 10 | Ship | `git push` | the gate lets it through |

**A small change starts at step 3.** Steps 1, 2, 5 and 7 need a plan to work against, and the Sprint lane skips them.

## What the gate actually verifies

This matters more than the step list, because it is the difference between review and self-certification.

Most of the checklist is **self-attested** — you write the findings, the smoke-test output, the dispositions. The gate checks those are present and not placeholder text. It cannot check they are true.

Four things are **not** the author's to write, and they decide everything else:

- **Reviewer dispatch is recorded, not claimed.** When a reviewer subagent completes, a hook writes `.claude/reviews/<branch>.verdicts/<agent>.json` naming the commit it saw and the verdict it reached. Another hook refuses to let that file be written by hand. Fix findings afterwards and the receipt no longer covers the tip, so that reviewer runs again.
- **The tier is derived from the diff.** A migration or an auth, tenancy, secrets or crypto path earns Tier 3; a deployment or API surface or a five-file blast radius earns Tier 2. A checklist declaring less is blocked, with no escape hatch — an escapable tier makes every other gate optional.
- **The proof is an experiment.** `prove-change-is-tested.sh` runs your suite at the base commit, then at the base with your tests added, then with change and tests together. If your tests pass without your change, they do not test it. It costs zero model tokens and it is the highest-value thing here.
- **The verdict is read, not assumed.** A receipt records `APPROVED` or `REJECTED`. A rejection does not satisfy the gate, and neither does a report with no readable verdict line.

**Only L1 must cover the commit you ship.** Adversarial and security must have run and approved somewhere on the branch; a later fix does not invalidate them. Requiring every reviewer to approve the same moving commit is what produces branches that never converge.

After every reviewer completes, the gate says where it stands — the tier it derives, which receipts are current, what is still unfilled. A satisfied gate is one line; anything actionable is a marked block. You do not have to run a command to learn the state.

## Turn on the gate

Off by default. exloom never blocks a repo that did not ask for it.

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

Commit that marker and the whole team has the gate.

It applies to **feature branches only** — work committed directly to `main`, `master`, `dev` or `develop` is deliberately not gated, so start on a branch. A repo can extend or narrow that with committed glob files: `.claude/exloom-protected-branches` and `.claude/exloom-skip-branches`. Both are honoured only when committed, and every skip is logged.

Optional, all committed:

| File | Effect |
|---|---|
| `.claude/exloom-lane` | the repo's default lane |
| `.claude/exloom-max-rounds` | the review-round cap, default 3 |
| `.claude/exloom-test-command` | the command the proof runs — pin one that is valid at any base, not one naming this branch's test classes |
| `.claude/exloom-test-report` | where the runner writes JUnit XML, if it is somewhere unusual |
| `.claude/exloom-mutation-command` | proves a purely additive change, which the three-run proof cannot |
| `.claude/exloom-provenance-signed.enabled` | require a signed checklist commit |

Emergency bypass: `EXLOOM_REVIEW_SKIP=1` in your Claude Code session env. It is honoured unconditionally, and records itself in `.claude/reviews/<branch>.bypass.json` — commit that with the change so the bypass is findable afterwards.

### Teaching the tier your repository's vocabulary

The built-in tier rules match `auth`, `tenant`, `secret`, `crypto`, `migrations/`. A codebase that calls the same thing `identity`, `iam`, `rbac` or `access-control` derives a *lower* tier for a change that should be the highest one — and the tier is the one thing with no escape hatch, because it decides which gates apply.

Commit an `.exloom.yml` at the repo root:

```yaml
version: 1

risk:
  tier3:
    paths:
      - "**/identity/**"
      - "**/iam/**"
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

`/exloom-config` prints the effective configuration and why the current diff derives the tier it does. The reasoning is also written into the checklist, so a PR reader sees it without running anything.

## Try it in two minutes

1. Install exloom and enable the gate.
2. `git checkout -b try/exloom-gate`, make a small code change, **commit it**.
3. `/review-init` — bootstraps and commits the checklist.
4. `/smoke-test` — boot the change, paste real evidence.
5. `/review-complete` — dispatches what is missing, records the reviewed commit.
6. `git push` is allowed.
7. Make **another** code commit without re-reviewing, then push again — **blocked**. The review no longer covers the tip.

Step 7 is the point: the review is bound to the exact commit it reviewed, not to the existence of a checklist.

Two more, because they are what stops a checklist being self-written:

8. Try to create `.claude/reviews/<branch>.verdicts/l1-reviewer.json` by hand — **denied**. Reading it is not.
9. Set `Tier:` to `1` on a branch touching `auth/` or a migration — **blocked**, naming the tier the diff earns.

## When the review will not converge

At three rounds the gate stops and asks you to choose: fix the open criticals by name, merge as-is, or see the findings first. The recommendation comes from whether a Critical is still open, never from the round number.

A review pass is not a fix. Re-reviewing a commit nobody changed returns the previous pass's findings, and the gate says so rather than counting it.

## What's inside

- **9 skills** — `brainstorming`, `planning-for-handoff`, `isolating-execution`, `executing-handoff-plans`, `auditing-plan-fidelity`, `review-gate`, `capturing-learnings`, `authoring-claude-md`, and `using-exloom` (the index).
- **3 reviewer agents** — `l1-reviewer` at low effort per commit; `adversarial-reviewer` and `security-auditor` at medium, once, before push. The adversarial dispatch carries the cross-layer contract check.
- **6 commands** — `/review-init`, `/smoke-test`, `/review-complete`, `/harden`, `/review-cleanup`, `/exloom-config`.
- **2 scripts** — `prove-change-is-tested.sh` and `lint-spec.sh` (gapless refs, a criterion under every requirement, no placeholders).
- **4 hooks** — record a receipt on real dispatch, deny writing one by hand, block the push without evidence, announce the flow at session start.
- **2 templates** — the review checklist and the spec format.

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
