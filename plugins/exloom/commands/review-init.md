---
name: review-init
description: Bootstrap .claude/reviews/<branch>.md from the checklist template. Propose a tier from git diff stats and user description. Commit the skeleton so it's visible in the PR.
---

# /review-init

You are initializing your org's review checklist for the current branch. Execute the following steps in order; do not skip.

## Step 1 — Gather context

Run:
- `git rev-parse --abbrev-ref HEAD` — the branch name (refuse to proceed if it is `main`, `master`, `dev`, or `develop`; tell the user the protocol only applies to feature branches).
- The fork point — the merge-base **nearest** to HEAD, not the first candidate that resolves. Where `main` is a release branch and `dev` is the branch work merges into, taking `main` puts the whole release gap in the diff and every branch derives Tier 3. Compute it against each of `origin/main`, `origin/master`, `origin/dev`, `origin/develop` that exists and keep the one fewest commits from HEAD:

  ```bash
  for r in origin/main origin/master origin/dev origin/develop; do
    git rev-parse --verify --quiet "$r" >/dev/null || continue
    mb=$(git merge-base HEAD "$r") || continue
    echo "$(git rev-list --count "$mb..HEAD") $mb"
  done | sort -n | head -1
  ```
- `git diff --stat <fork-point>...HEAD` — the blast-radius summary.
- `git diff --name-only <fork-point>...HEAD` — the list of changed files.

Also check if `.claude/exloom.local.md` exists in the repo. If yes, read its frontmatter — it may override default boot commands and adversarial grep roots.

## Step 2 — Propose a tier

Use these rules mechanically first, then ask the user to confirm:

- If the ONLY changed files match `*.md`, `*.txt`, or live under doc-only directories (`docs/`, `README*`), AND no file contains non-comment code changes → Tier 0.
- If any file under a `migrations/`, `liquibase/`, `db/changelog/` path → Tier 3.
- Else if any file touches auth, tenancy, secrets, crypto (search paths for `auth`, `tenant`, `secret`, `crypto`, `jwt`, `apikey`) → Tier 3.
- Else if any file under a `deployment/`, `k8s/`, `docker/`, `helm/` path AND flag/prod-related → Tier 3.
- Else if any frontend file changed AND any backend file changed → Tier 2.
- Else if any controller / route / API definition file changed → Tier 2.
- Else if the diff touches more than one module / service / package → Tier 2.
- Else if the diff touches ≥5 files → Tier 2.
- Else → Tier 1.

Show the proposed tier, the rule that triggered it, and the `git diff --stat` output. Ask the user to confirm or override. Record the final tier and the one-sentence rationale.

**The override is upward only.** When the gate is enabled, `lib.sh` derives the same minimum from the diff at push time and blocks a checklist that declares less — with no escape hatch, because the tier decides which gates apply and an escapable tier makes every other gate optional. So a user asking to go lower is asking for a push that will fail; say so, and either raise the tier or fix the derivation rule. Going higher is always allowed and is the documented response to uncertainty.

Two of the rules above are judgment the hook cannot make, so it derives a lower floor and leaves the decision here: deployment/k8s/helm/docker paths floor at Tier 2 (raise to 3 when the change is flag- or prod-related), and "frontend AND backend changed" or "more than one module" need stack knowledge a file list does not carry. Apply them yourself.

**The repository may add rules of its own.** A committed `.exloom.yml` names path globs that this repo treats as Tier 2 or Tier 3 — its own words for risk, such as `identity`, `iam` or `rbac`, which the list above does not know. Those rules only ever raise the tier. Rather than reproducing them here, take the tier from the derivation itself, which already merges both sources:

```bash
# ${CLAUDE_PLUGIN_ROOT} is set for plugin.json hooks, NOT in your shell.
# Resolve the installed plugin instead; several versions live in the cache,
# so take the highest.
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
. "$LIB"
exloom_derive_tier HEAD; exloom_tier_reasons
```

If that disagrees with the rules above, it is right and they are the summary — it is the same function the push gate runs.

## Step 2b — Propose a lane

The tier is derived from the diff. The **lane** is the user's call, and it decides how much happens *before* the code — not how deep the review goes.

| Lane | For | Before the code | After it |
|---|---|---|---|
| `sprint` | a spike, a demo, a bug fix you already understand | nothing — branch and go | L1, smoke, proof |
| `standard` | work meant to become a real system | spec, plan, fidelity audit | whatever the tier requires |
| `certified` | regulated, or someone outside the team must be able to audit it | same as standard | tier's requirements, **no workflow-step escape hatches**, signed provenance |

On Certified, a skipped step recorded under `## Escape hatches used` blocks the push — writing a justification is not a way past a step. `EXLOOM_REVIEW_SKIP=1` is separate: it overrides the hooks on any lane and always leaves a bypass receipt.

Ask once, with a recommendation, and default to the repo's committed `.claude/exloom-lane` (or `standard` when there is none). Recommend `sprint` when the change is small and self-contained and the user described it as a fix or a spike; recommend `standard` otherwise.

**Sprint is not available at Tier 3.** If the derived tier is 3, do not offer it — say that migrations, auth, tenancy, secrets and crypto are the stakes that earn the full flow, and that the gate refuses the combination.

Write the answer into the checklist's `**Lane:**` field. A Sprint branch is not exempt from evidence, only from ceremony: the receipts, the proof and the smoke test are identical, and the checklist records the lane so a skipped step is a recorded fact rather than a silent absence.

## Step 3 — Create the checklist

Copy the plugin's `templates/review-checklist.md` to `.claude/reviews/<branch-name>.md`.

`${CLAUDE_PLUGIN_ROOT}` is interpolated by the harness into `plugin.json` hook
commands only — it is **not** set in your shell, so a command using it fails with
"No such file or directory". Locate the template instead:

```bash
find ~/.claude/plugins -path '*exloom*/templates/review-checklist.md' | sort -V | tail -1
```

**`| head -1` is wrong here and silently gives you a stale template.** Several
plugin versions stay in the cache and `find` returns them path-sorted, so
`head -1` picks the *lowest* version. The checklist it copies is missing sections
the gate checks for, so the branch is blocked by a check its template never
mentioned. `sort -V | tail -1` takes the highest version.

Sanity-check the file you copied: it must contain `## Re-finds`, `## Provenance`,
and a `**Tier derived from:**` field. If any is missing you have an old template —
go back and take the highest version.

Substitute:

- `<branch-name>` → actual branch.
- `[0 | 1 | 2 | 3]` → the confirmed tier.
- Tier rationale line → the user's confirmed rationale.
- **Tier derived from** → the output of `exloom_tier_reasons`, one line per rule, as `` `path` → `rule` → source ``. If the tier came from the built-in rules with no repository policy in play, write `built-in defaults only`. Get it by sourcing the hook library and running the derivation:

  ```bash
  LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
  . "$LIB"
  exloom_derive_tier HEAD >/dev/null; exloom_tier_reasons
  ```

  Same `sort -V | tail -1` rule as the template above, and for the same reason —
  several plugin versions live in the cache at once.

  Write the reasons down even when they are obvious. This is the line a PR reviewer reads when they want to know why a two-file change is Tier 3, and the line CI reads when it re-derives the tier and wants to compare.
- Blast radius line → "N files changed, M modules touched, user-facing: yes/no" from the diff analysis.
- Started date → today's date.

Create the parent directory chain first (branches like `feature/csv-export` require nested directories):

```bash
mkdir -p "$(dirname .claude/reviews/<branch-name>.md)"
```

This also creates `.claude/reviews/` if it does not exist.

## Step 4 — Commit the skeleton

Stage `.claude/reviews/<branch>.md` and commit with message:

```
chore(review): initialize Tier <N> review checklist for <branch-name>
```

Do NOT commit anything else. The checklist is the only file in this commit.

## Step 5 — Tell the user what comes next

Print:

> Review checklist initialized at `.claude/reviews/<branch>.md` (Tier <N>) — committed as `chore(review): initialize Tier <N> review checklist`.
> Required remaining steps for Tier <N>:
> - <list based on tier>
> Next commands: `/smoke-test` to fill the smoke-test section, then `/review-complete` when ready to ship.
> Tier <N> requires a real dispatch of: <reviewers for the tier>. exloom records a receipt under `.claude/reviews/<branch>.verdicts/` when each one completes; the gate requires those receipts and does not read any checkbox for them.

## Refusals

- Refuse on protected branches. Protocol is for feature branches only.
- Refuse if `.claude/reviews/<branch>.md` already exists — tell the user to open it and continue, or delete it explicitly if they want to start over.
