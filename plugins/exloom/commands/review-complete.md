---
name: review-complete
description: Run the final gate for the current branch. Verifies every required checklist section for the declared tier is populated with real evidence, dispatches any missing reviewer agents, and marks the checklist ready to ship. Refuses to mark complete if sections are missing, naming each gap.
---

# /review-complete

You are the terminal gate. Nothing ships unless every tier-required section of `.claude/reviews/<branch>.md` is filled with real evidence. You do not take the operator's word; you read the file and verify.

## Step 1 — Open and parse

Open `.claude/reviews/<current-branch>.md`. If absent, refuse — tell the user to run `/review-init`.

Parse the Tier field. If missing or not `0`, `1`, `2`, or `3`, refuse — the tier must be explicit.

## Step 2 — Check required sections for the tier

### Tier 0 required
- L1 code review: "Dispatched" ticked, findings listed (or "no findings" stated), resolution for each Critical/Important.
- Smoke test / cross-layer / adversarial / runbook sections marked `N/A - Tier 0` (or left with their defaults) are acceptable — Tier 0 only requires L1.

### Tier 1 required
- L1 code review: "Dispatched" ticked, findings listed (or "no findings" stated), resolution for each Critical/Important.
- Smoke test: boot command filled, user action filled, expected result filled, actual observed result filled with real evidence (not `<paste output>` placeholder, not empty). "Test passed" ticked.

### Tier 2 required (Tier 1 +)
- Cross-layer contract check: "Dispatched cross-layer-auditor" ticked, grep output pasted for fields / endpoints / events / columns / config keys, orphan list resolved (fixed or annotated intentional).
- Adversarial review: "Dispatched adversarial-reviewer" ticked, findings listed with category, resolution per finding.

### Tier 3 required (Tier 2 +)
- Runbook path filled and the file exists at that path.
- Rollback command filled with an exact command, not a description.
- Reversal proof names a test id or path — and that test exists in the repo. If it reads `untestable in code`, a one-sentence deploy-time verification follows it.
- Both Tier 3 boxes ticked.

## Step 3 — Verify section content is real, not placeholder

For each required section, check the literal text is not one of the placeholder markers from the template:
- `<paste output / screenshot link>`
- `<exact command>`
- `<exact steps>`
- `<Critical / Important / Minor with file:line>`
- `<expected-result>`
- Empty after the header.

If any placeholder remains, the section is NOT filled — list it as missing.

## Step 4 — If sections are missing

Print a list like:

```
Cannot mark complete. Missing or placeholder sections:
- Smoke test: actual observed result contains placeholder text
- Adversarial review: no findings recorded, box unticked
```

For each missing section, offer to fix:
- Smoke test missing → suggest `/smoke-test`.
- L1 missing → offer to dispatch the `l1-reviewer` agent now against the current diff.
- Cross-layer missing → offer to dispatch the `cross-layer-auditor` agent now.
- Adversarial missing → offer to dispatch the `adversarial-reviewer` agent now.
- Runbook missing → ask the user for the path or tell them to write it.
- Reversal proof missing → ask which test exercises the rollback; if none exists, say so plainly and offer to write it rather than accepting prose.

Wait for the user. Do NOT mark complete while anything is missing.

## Step 5 — If everything is present

First capture the **reviewed code tip** — the commit this review covers:

`git rev-parse HEAD`

Fill the Final Verdict section, writing that SHA into `Reviewed code commit:`:

```
## Final verdict
- [x] All required gates passed for declared tier
- [x] Checklist committed
- [x] Ready to ship

Reviewed code commit: <the `git rev-parse HEAD` output>
Signed: Claude (exloom)
Date: <YYYY-MM-DD>
```

Capture the SHA **before** committing the checklist, so it names the last *code*
commit — the tip that was actually reviewed, not the checklist commit.

Then fill the **Provenance** section — who and what produced this change:

- **AI-assisted:** `yes` if a model wrote or co-wrote the change (the default for a
  Claude Code session), else `no`.
- **Model(s):** the model id you are running as (e.g. `claude-opus-4-8`), or
  `N/A — human-authored`. State it honestly; it is self-reported.
- **Directed by:** the human on whose behalf you are working — from
  `git config user.name` / `user.email`.
- **Base commit:** the fork point — `git merge-base HEAD <default-branch>` (try
  `origin/main`, then `origin/master`, then `origin/dev`); if there is no base, use
  the repository's first commit.
- **Attested:** today's date.

```
## Provenance
- AI-assisted: yes
- Model(s): claude-opus-4-8
- Directed by: Jane Dev <jane@example.com>
- Base commit: <merge-base output>
- Attested: <YYYY-MM-DD>
```

Then stage the checklist and commit. **If** the repo has
`.claude/exloom-provenance-signed.enabled`, the commit MUST be signed
(`git commit -S`) — the hooks `git verify-commit` it and block an unsigned commit.
Otherwise a normal commit is fine:

```
# signed-provenance repos:
git commit -S -m "chore(review): mark Tier <N> review complete for <branch-name>"
# otherwise:
git commit -m "chore(review): mark Tier <N> review complete for <branch-name>"
```

The reviewed SHA binds the review to the branch tip (the hooks block a push if any
non-checklist file changed after it), and the provenance record makes who/what
produced the change auditable. If `git commit -S` fails because no signing key is
configured, tell the user to set up git commit signing (GPG or SSH) or remove the
signed-provenance marker — do **not** fall back to an unsigned commit in a
signed-provenance repo.

## Step 6 — Tell the user what is now unblocked

Print:

> Review complete for Tier <N> — checklist committed (`chore(review): mark Tier <N> review complete`). You may now claim done and run `git push` / open a PR. The Stop hook and PreToolUse hook will no longer block.

## Rules

- You do NOT mark complete partially. All-or-nothing per the tier's required sections.
- You do NOT accept "I'll do that later" — the gate is terminal.
- Escape hatches (a skipped step with written justification in the "Escape hatches used" section) ARE acceptable — a step with a recorded escape hatch counts as "addressed" for this check. But an unjustified skip is not an escape hatch, it is an incomplete checklist.
- If the user says "skip this, emergency", offer the `EXLOOM_REVIEW_SKIP=1` bypass — it must be set in the Claude Code session env (`settings.json` `env`), not inline before the command, or the hook won't see it — and require a written one-sentence justification in the checklist before the hooks will honor it.
