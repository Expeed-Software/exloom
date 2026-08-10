# exloom

**Spec-driven development for teams — with a review gate that's actually enforced.**

exloom is a spec-driven development workflow for Claude Code, built for teams. You brainstorm → plan → execute → prove → review — with the **plan as a handoff contract** between developers (deviations logged, what-shipped checked against what-was-planned), a **multi-pass review** (correctness, cross-layer, adversarial, and a scanner-backed **security** pass for how AI code tends to fail) plus a **boot-and-prove smoke test**, and an **opt-in gate that blocks "done" and `git push`** until the review evidence exists. Excellent solo; built to scale to a team.

It sits in the same family as other spec-driven / structured-agentic development frameworks — the spec → plan → execute → review loop is the standard they share. exloom's focus within that category is the two things teams feel most: making the **handoff auditable** and the **review enforced** — a committed evidence gate, not a suggestion.

MIT-licensed. Works with any Claude Code marketplace.

## Requirements

- Claude Code with plugin support.
- Git, because the review gate binds evidence to commits and blocks stale reviews.
- Bash for the hook scripts. On Windows, Claude Code runs plugin hooks through Git Bash; if you run the validator or the worktree helper scripts manually, use Git Bash rather than WSL or PowerShell.
- `jq` **or** `python3` for the full review gate. The **push gate** (`git push` / `gh pr create`) works without either — it falls back to coarse raw-text matching of the command (which, being fail-closed, can occasionally over-block a benign command that mentions `git push`). The **Stop hook** (which nudges you not to *claim* "done" prematurely) parses the session transcript and needs `jq` or `python3`; without one it won't fire, though the push gate still blocks the actual push. Git Bash on Windows bundles neither, so install `jq` (or Python) if you want the complete gate.

## Why exloom

Claude Code is fast. On a team, fast-without-discipline produces plans nobody else can follow, "done" that wasn't, and reviews that rubber-stamp. exloom adds the discipline that makes AI-assisted work **provable and handoff-safe**:

- **The plan is a contract.** `planning-for-handoff` produces a plan a different person can execute without guessing; `reviewing-plans` approves it; `executing-handoff-plans` logs every deviation instead of improvising; `auditing-plan-fidelity` checks that what shipped matches what was planned.
- **Review is a panel, not a rubber stamp.** Correctness (`l1-reviewer`), cross-layer integration (`cross-layer-auditor`), hostile adversarial (`adversarial-reviewer`), and **security** (`security-auditor` — scanners + a review for the security flaws AI code tends to introduce) review agents, plus a **boot-and-prove smoke test** — you have to actually run the change and show the output, not assert it works.
- **"Done" needs evidence.** `proving-done` is an eight-item checklist that wants real command output, not a feeling.
- **Brownfield-first.** Your existing conventions win — exloom defers to the repo's `CLAUDE.md`; its defaults only fill gaps.

## How it works: skills nudge, one gate enforces

Be clear about the mechanism, because it matters:

- **Most of exloom is discipline** — skills Claude reads and follows. They guide the work; they don't force it.
- **One part is enforcement** — the optional review-gate hooks. When a repo turns them on, the Claude Code harness (not the model) **blocks "done" and `git push`** until the review evidence is committed to `.claude/reviews/<branch>.md`.

That's the difference between *hoping* review happened and *guaranteeing* it did — the one thing you can't get from instructions alone. It's also what separates exloom from most workflow plugins: they *guide* the loop; exloom guides it and, with the gate on, **enforces** it — committed evidence, a smoke proof, and a review bound to the exact commit you're shipping.

## The loop

```
brainstorming → planning-for-handoff → [reviewing-plans] → isolating-execution → executing-handoff-plans (TDD)
   → proving-done → [auditing-plan-fidelity] → reviewing-code / review-gate → requesting-review
```

The bracketed steps apply when work crosses from one person to another. Solo? The same loop, lighter — but every plan is still written handoff-ready, because future-you is a different person.

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

Commit that marker and the whole team gets the gate. Then `/review-init` starts a branch's checklist, `/smoke-test` captures real evidence, and `/review-complete` runs the final gate. Those commands intentionally create checklist-only commits so the evidence lands in the PR. The hooks refuse to let anyone declare done or push until the checklist is complete, committed, and bound to the reviewed code commit. The gate applies on feature branches only — work committed directly to `main`/`master`/`dev`/`develop` is deliberately not gated, so isolate onto a feature branch first (`exloom:isolating-execution`). A repo can extend that protected set with its own integration branches, or exempt throwaway branches, using two optional **committed** glob files: `.claude/exloom-protected-branches` (e.g. add `pre-dev`) and `.claude/exloom-skip-branches` (e.g. `spike/*`, `tmp/*`). Both are honored only when committed, and every skip is logged; keep integration/merge branches gated (a botched merge is new, unreviewed code). The gate covers `git push` (including pushes of a different branch than the one checked out) / `gh pr create` **and** the common GitHub MCP push/PR tools (`push_files`, `create_pull_request`, …), so switching to the MCP integration doesn't dodge it; a push through some other MCP server, a raw API call, or a deliberately obfuscated shell command could still slip by. Emergency bypass: `EXLOOM_REVIEW_SKIP=1` in your Claude Code session env.

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

## What's inside

- **20 skills** — the discipline loop (`brainstorming`, `planning-for-handoff`, `isolating-execution`, `executing-handoff-plans`, `orchestrating-execution` for multi-agent execution, `proving-done`, `reviewing-code`, `security-review`), handoff (`reviewing-plans`, `auditing-plan-fidelity`, `review-gate`), and support (`systematic-debugging`, `test-driven-development`, `exploring-codebase`, `authoring-claude-md`, `capturing-learnings`, `switching-projects`, `designing-ui`, `requesting-review`, `using-exloom`).
- **Isolated execution** — `isolating-execution` puts work on a gated feature branch (or a dedicated worktree); in the multi-agent mode, each parallel implementer gets its own worktree, gated then integrated back.
- **4 review agents** — `l1-reviewer`, `cross-layer-auditor`, `adversarial-reviewer`, `security-auditor`.
- **4 commands** — `/review-init`, `/smoke-test`, `/review-complete`, and `/review-cleanup` (archive orphaned checklists whose branch is gone).
- **Opt-in hooks** — the enforcement gate.
- **CLAUDE.md templates** — starting points for common stacks.

See [`plugins/exloom/`](plugins/exloom/).

## Honest scope

- exloom guides Claude with skills; only the gate **enforces**. Plan discipline, TDD, and review quality are strong defaults, not guarantees — turn the gate on for the part that genuinely can't be skipped.
- The **security review** runs the scanners a repo has (secrets, dependency-vuln audit, static analysis) and reviews the diff for how AI code commonly fails — injection, missing authorization, secrets, weak crypto, hallucinated dependencies. It's a **first-pass aid, not a guarantee**: it never certifies code "secure," its coverage is only as good as the tools installed, and it doesn't replace SAST/DAST or a pentest for high-risk changes.
- It reviews the change in front of it, not your whole codebase. It gates `git push` / `gh pr create` plus the common GitHub MCP push/PR tools — but a push through some other MCP server, a raw API call, or a deliberately obfuscated shell command could still slip by — and, being a fail-closed text matcher, it can occasionally over-block a benign command that literally contains the words `git push` (bypass or rephrase). It's a cooperating-team gate, not an adversarial security boundary.
- When the gate is on, every change also carries a committed **provenance** record — AI-assisted, model, who directed it, base commit — bound to the reviewed commit. It's an audit trail (ISO 42001 / SOC 2 / insurance kind), **not a compliance certificate**; the model id is self-reported. An opt-in signed-commit mode (`git commit -S` + `git verify-commit`) adds verified-identity non-repudiation with your existing key — no sigstore/cosign.
- Claude Code only, for now.

## License

[MIT](LICENSE). Built by [Expeed Software](https://github.com/Expeed-Software).
