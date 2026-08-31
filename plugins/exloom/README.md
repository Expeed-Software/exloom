# exloom

**Spec-driven development for teams — with a review gate that's actually enforced.**

exloom is a spec-driven development workflow for Claude Code, built for teams. You brainstorm → plan → execute → prove → review — with the **plan as a handoff contract** between developers (deviations logged, what-shipped checked against what-was-planned), a **multi-pass review** (correctness, cross-layer, adversarial, and a scanner-backed **security** pass for how AI code tends to fail) plus a **boot-and-prove smoke test**, and an **opt-in gate that blocks "done" and `git push`** until the review evidence exists. Excellent solo; built to scale to a team.

It sits in the same family as other spec-driven / structured-agentic development frameworks — the spec → plan → execute → review loop is the standard they share. exloom's focus within that category is the two things teams feel most: making the **handoff auditable** and the **review enforced** — a committed evidence gate, not a suggestion.

## Requirements

- Claude Code with plugin support.
- Git, because the review gate binds evidence to commits and blocks stale reviews.
- Bash for the hook scripts. On Windows, Claude Code runs plugin hooks through Git Bash; if you run the validator or the worktree helper scripts manually, use Git Bash rather than WSL or PowerShell.
- `jq` **or** `python3` for the full review gate. The **push gate** (`git push` / `gh pr create`) works without either — it falls back to coarse raw-text matching of the command (which, being fail-closed, can occasionally over-block a benign command that mentions `git push`). The **Stop hook** (which nudges you not to *claim* "done" prematurely) parses the session transcript and needs `jq` or `python3`; without one it won't fire, though the push gate still blocks the actual push. Git Bash on Windows bundles neither, so install `jq` (or Python) if you want the complete gate.

## Why exloom

Claude Code is fast, and the model already plans, tests, and reviews its own work without being told. What it cannot do is produce evidence about itself that anyone else should trust. exloom produces that evidence:

- **The plan is a contract.** `planning-for-handoff` produces a plan a different person can execute without guessing, committed so the next session can find it.
- **Tests are proved, not claimed.** `prove-change-is-tested.sh` runs your suite with your change removed and your tests kept. If they still pass, they do not test your change. This is an experiment, not a judgement, and it costs zero model tokens — the highest-value thing in the plugin.
- **Review leaves a receipt.** A reviewer dispatch writes `.claude/reviews/<branch>.verdicts/<agent>.json` naming the commit it saw and the verdict it reached. The model cannot write that file. "Was this reviewed?" is answered by an event, not a checkbox.
- **One gate, at push.** Not at "done", not at the first edit, not during review. Blocking the push is the one interruption worth its cost.
- **Brownfield-first.** Your existing conventions win — exloom defers to the repo's `CLAUDE.md`; its defaults only fill gaps.

## How it works: skills nudge, one gate enforces

Be clear about the mechanism, because it matters:

- **Most of exloom is discipline** — skills Claude reads and follows. They guide the work; they don't force it.
- **One part is enforcement** — the optional review-gate hooks. When a repo turns them on, the Claude Code harness (not the model) **blocks "done" and `git push`** until the review evidence is committed to `.claude/reviews/<branch>.md`.

And enforcement means more than "a document exists." Most of the checklist is self-attested and the gate can only check it is filled in — but the two fields that decide everything else are not the author's to write:

- **Reviewer dispatch is recorded, not claimed.** A `PostToolUse` hook writes a receipt to `.claude/reviews/<branch>.verdicts/<agent>.json` when a reviewer subagent actually completes; another hook refuses to let that file be written by hand. The gate requires one receipt per reviewer the tier needs, covering the reviewed commit. Fix findings afterwards and the receipt no longer covers the tip — that reviewer runs again.
- **The tier is derived from the diff, not declared.** A migration or an auth/tenancy/secrets/crypto path earns Tier 3, a deployment or API surface or a five-file blast radius earns Tier 2, and a checklist declaring less is blocked. There is no escape hatch, because an escapable tier makes every other gate optional.

It proves a reviewer ran; it does not prove the review was good, and a determined author can still disable the plugin or use the documented bypass. This is a cooperating-team gate. What it changes is that the lazy path no longer produces a passing artifact.

> **Upgrading from 1.x** — this is why 2.0 is a major version. A branch whose checklist was completed under 1.x has no verdict receipts and may declare a tier below what its diff derives to, so its next push is blocked. Re-run `/review-complete` on it: the reviewers dispatch for real, the receipts are written and committed, and it passes. Nothing is lost, but in-flight branches need one extra pass.

That's the difference between *hoping* review happened and *guaranteeing* it did — the one thing you can't get from instructions alone. It's also what separates exloom from most workflow plugins: they *guide* the loop; exloom guides it and, with the gate on, **enforces** it — committed evidence, a smoke proof, and a review bound to the exact commit you're shipping.

## The loop

```
brainstorming → planning-for-handoff → [execute] → review-gate → push
```

Four artifacts, one gate. The plan is written handoff-ready even solo, because future-you is a different person. exloom does not tell you how to debug, how to write tests, or how to be careful — the model does that already. It produces the evidence that the next person needs and the model cannot self-certify.

## Install

```
/plugin marketplace add https://github.com/Expeed-Software/exloom
/plugin install exloom@exloom
```

Or from the terminal: `claude plugin marketplace add https://github.com/Expeed-Software/exloom` then `claude plugin install exloom@exloom`.

## Use it

Skills surface based on what you're doing — just start working:

```
> Design a CSV-export feature for the orders page.
> Write a plan for PROJ-1234 that another developer can pick up.
> I'm joining an unfamiliar service — help me get oriented.
> Before I open this PR, review it.
```

## Turn on the enforcement gate (optional, per repo)

Off by default — exloom never blocks a repo that didn't ask for it. To make the review gate enforce on a repository:

```
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

In Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force .claude | Out-Null
New-Item -ItemType File -Force .claude/exloom-gate.enabled | Out-Null
```

Commit that marker and the whole team gets the gate. Then `/review-init` starts a branch's checklist, `/smoke-test` captures real evidence, and `/review-complete` runs the final gate. Those commands intentionally create checklist-only commits so the evidence lands in the PR. The hooks refuse to let anyone push until the checklist is complete, committed, and bound to the reviewed code commit. The gate applies on feature branches only — work committed directly to `main`/`master`/`dev`/`develop` is deliberately not gated, so start on a feature branch. A repo can extend that protected set with its own integration branches, or exempt throwaway branches, using two optional **committed** glob files: `.claude/exloom-protected-branches` (e.g. add `pre-dev`) and `.claude/exloom-skip-branches` (e.g. `spike/*`, `tmp/*`). Both are honored only when committed, and every skip is logged; keep integration/merge branches gated (a botched merge is new, unreviewed code). The gate covers `git push` (including pushes of a different branch than the one checked out) / `gh pr create` **and** the common GitHub MCP push/PR tools (`push_files`, `create_pull_request`, …), so switching to the MCP integration doesn't dodge it; a push through some other MCP server, a raw API call, or a deliberately obfuscated shell command could still slip by. Emergency bypass: `EXLOOM_REVIEW_SKIP=1` in your Claude Code session env.

## Try the gate in 2 minutes

Prove the enforcement is real on a throwaway branch:

1. Install exloom and enable the gate (above).
2. `git checkout -b try/exloom-gate`, then make a small code change **and commit it**.
3. `/review-init` — bootstraps and commits the checklist (pick a tier).
4. `/smoke-test` — boot the change, paste real evidence, and commit it to the checklist.
5. `/review-complete` — records the reviewed commit and commits the final verdict.
6. `git push` is now allowed by the gate. Your usual Git remote/upstream setup still applies.
7. Make **another** code commit without re-reviewing, then `git push` again — the gate **blocks** it: the review no longer covers the tip. Re-run `/review-complete` and it passes.

Step 7 is the point: the review is bound to the exact commit it reviewed, not just "some checklist exists."

Two more worth trying, because they are what stops a checklist from being self-written:

8. Try to create `.claude/reviews/<branch>.verdicts/l1-reviewer.json` yourself — the gate **denies the write**. Receipts are only produced by real reviewer dispatches.
9. Set the checklist's `Tier:` to `1` on a branch that touches `auth/` or a migration — `git push` is **blocked** with the tier the diff actually earns. There is no way to talk it down.

## What's inside

- **6 skills** — `brainstorming` (spec), `planning-for-handoff` (plan), `review-gate` (the gate), `capturing-learnings`, `authoring-claude-md`, and `using-exloom` (the index).
- **3 review agents** — `l1-reviewer` at low effort for the per-commit pass, `adversarial-reviewer` and `security-auditor` at medium effort for the single pre-push pass. The adversarial dispatch carries the cross-layer contract check.
- **1 proof script** — `prove-change-is-tested.sh`. Runs your suite at the base commit, at the base with your tests added, and with the change and tests together. If your tests pass without your change, they do not test it. Costs zero model tokens.
- **4 commands** — `/review-init`, `/smoke-test`, `/review-complete`, `/review-cleanup`.
- **3 opt-in hooks** — record a receipt on real reviewer dispatch, deny writing receipts by hand, block the push without evidence.
- **CLAUDE.md templates** — starting points for common stacks.

### What was removed, and why

Version 4 cut the plugin roughly in half. Gone: the `Stop` hook that matched natural-language completion claims, the review freeze and its state machine, the plan-approval gate on the first source edit, the dispatch-token protocol, the `SessionStart` context injection, and fourteen skills that told the model how to think — TDD, systematic debugging, proving-done, plan-fidelity auditing, and the rest.

They were built for a model that would skip work if permitted. Current models verify their own work unprompted, and Anthropic's guidance is explicit that carrying over verification scaffolding causes over-verification rather than better results. Enforcement that duplicates what the model already does is not free: it costs on every iteration, and the machinery generates its own defects. What survives is the part prompting cannot reproduce — an artifact the model did not author.

## Honest scope

- exloom guides Claude with skills; only the gate **enforces**. Plan discipline, TDD, and review quality are strong defaults, not guarantees — turn the gate on for the part that genuinely can't be skipped.
- The **security review** runs the scanners a repo has (secrets, dependency-vuln audit, static analysis) and reviews the diff for how AI code commonly fails — injection, missing authorization, secrets, weak crypto, hallucinated dependencies. It's a **first-pass aid, not a guarantee**: it never certifies code "secure," its coverage is only as good as the tools installed, and it doesn't replace SAST/DAST or a pentest for high-risk changes.
- It reviews the change in front of it, not your whole codebase. It gates `git push` / `gh pr create` plus the common GitHub MCP push/PR tools — but a push through some other MCP server, a raw API call, or a deliberately obfuscated shell command could still slip by — and, being a fail-closed text matcher, it can occasionally over-block a benign command that literally contains the words `git push` (bypass or rephrase). It's a cooperating-team gate, not an adversarial security boundary.
- When the gate is on, every change also carries a committed **provenance** record — AI-assisted, model, who directed it, base commit — bound to the reviewed commit. It's an audit trail (ISO 42001 / SOC 2 / insurance kind), **not a compliance certificate**; the model id is self-reported. An opt-in signed-commit mode (`git commit -S` + `git verify-commit`) adds verified-identity non-repudiation with your existing key — no sigstore/cosign.
- Claude Code only, for now.

## License

[MIT](../../LICENSE).
