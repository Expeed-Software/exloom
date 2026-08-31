---
name: review-complete
description: Run the final gate for the current branch. Verifies every required checklist section for the declared tier is populated with real evidence, dispatches any missing reviewer agents, and marks the checklist ready to ship. Refuses to mark complete if sections are missing, naming each gap.
---

# /review-complete

You are the terminal gate. Nothing ships unless every tier-required section of `.claude/reviews/<branch>.md` is filled with real evidence. You do not take the operator's word; you read the file and verify.

**Reviewer dispatch is not something you attest to.** exloom writes a verdict receipt to `.claude/reviews/<branch>.verdicts/<agent>.json` when a reviewer subagent actually completes, and refuses to write one by hand. The gate requires one receipt per reviewer the tier needs, covering the reviewed commit. So there is no way to satisfy this command by filling in text: if a reviewer has not run, dispatch it. **The tier is also derived from the diff by the gate** — declaring a lower one than the diff earns does not reduce what is required, it blocks the push.

## Step 1 — Open and parse

Open `.claude/reviews/<current-branch>.md`. If absent, refuse — tell the user to run `/review-init`.

Parse the Tier field. If missing or not `0`, `1`, `2`, or `3`, refuse — the tier must be explicit.

Then check the tier against the diff, using the same rules `/review-init` applies (docs-only → 0; migrations or auth/tenancy/secrets/crypto → 3; deployment surface, API/route surface, or ≥5 files → 2; else 1). If the declared tier is lower than what the diff earns, say so and raise it before going further — the gate derives the same minimum and will block otherwise. There is no escape hatch for an under-declared tier.

## Step 2 — Check required sections for the tier

For every reviewer a tier requires, "was it dispatched?" is answered by the receipt file, never by the checklist. Check with:

```bash
ls .claude/reviews/<branch>.verdicts/
```

A receipt only counts if it names a commit with no code changes between it and the reviewed tip — if you fixed findings after a review, that reviewer must run again. Receipts must be committed alongside the checklist.

### When to stop reviewing

Each receipt carries `"round_needed"`, read from the `ROUND NEEDED AFTER FIX:` line every reviewer emits. **The loop is over when every required reviewer's current receipt reads `"verdict":"APPROVED"` and `"round_needed":"NO"`.** Check it:

```bash
grep -h '"round_needed"' .claude/reviews/<branch>.verdicts/*.json
```

If that holds, ship. Do not run another round to be thorough — an extra round on an approved commit produces thinner findings that then get treated as work, which is the specific way a two-round change becomes a nine-round one.

`"round_needed":"UNKNOWN"` means the reviewer gave no such line, and counts as `YES`: a reviewer that did not answer has not told you the loop can stop. Re-dispatch that one reviewer rather than the whole set.

### Tier 0 required
- L1 code review: `l1-reviewer.json` receipt present, findings listed (or "no findings" stated), resolution for each Critical/Important.
- Smoke test / cross-layer / adversarial / runbook sections marked `N/A - Tier 0` (or left with their defaults) are acceptable — Tier 0 only requires L1.

### Tier 1 required
- L1 code review: `l1-reviewer.json` receipt present, findings listed (or "no findings" stated), resolution for each Critical/Important.
- Smoke test: boot command filled, user action filled, expected result filled, actual observed result filled with real evidence (not `<paste output>` placeholder, not empty). "Test passed" ticked.
- **Proof that the change is tested: `proof.json` receipt present, `"result":"PROVED"`, covering the reviewed commit.** Written only by:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/prove-change-is-tested.sh"
  ```

  It runs the suite three times — at the base commit (must pass, or the proof is void), at the base with your tests added (must fail, or your tests do not notice your change), and with the change and tests together (must pass). A `NOT_PROVED` receipt does not satisfy the gate; fix the tests rather than re-running.

  This applies to **every tier from 1 up**, including Tiers 2 and 3. It was enforced by the hooks and named in none of the tier lists, so a session could fill this file correctly, tick every box, commit, and then be blocked at Stop and at push by a check nothing had mentioned.

### Tier 2 required (Tier 1 +)
- Cross-layer contract check: `cross-layer-auditor.json` receipt present, grep output pasted for fields / endpoints / events / columns / config keys, orphan list resolved (fixed or annotated intentional).
- Adversarial review: `adversarial-reviewer.json` receipt present, findings listed with category, resolution per finding.

### Tier 3 required (Tier 2 +)
- Security review: `security-auditor.json` receipt present, tool output pasted, findings dispositioned.
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

For each missing section:
- Smoke test missing → run `/smoke-test`.
- Proof receipt missing, stale, or `NOT_PROVED` → run `prove-change-is-tested.sh` (above). If it reports NOT PROVED, the fix is a test that fails without your change — not another run.
- L1 receipt missing or stale → dispatch the `exloom:l1-reviewer` agent now against the current diff.
- Cross-layer receipt missing or stale → dispatch the `exloom:cross-layer-auditor` agent now.
- Adversarial receipt missing or stale → dispatch the `exloom:adversarial-reviewer` agent now.
- Security receipt missing or stale → dispatch the `exloom:security-auditor` agent now.
- Runbook missing → ask the user for the path or tell them to write it.

**Authorise the round before dispatching anything.** `require-command-dispatch.sh` denies every reviewer `Task` unless a dispatch token covers the current HEAD, and the only thing that writes that token is:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/begin-review-round.sh"
```

Run it once, before the first dispatch. It runs the author-side checks first and authorises dispatch only if they pass — so a round never starts on a tree that does not build. If this round is pointed at something specific, pass it and hand the same text to every reviewer verbatim:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/begin-review-round.sh" --focus "concentrate on X"
```

Skipping this is not a shortcut; it is a deadlock. The command used to instruct a dispatch that the hook then denied, naming a script that appeared in no command or skill — a session following this file to the letter could not get past it.

Then dispatch the reviewers rather than asking whether to — a missing review is not a decision the user needs to make, and asking is how a required gate turns into a skipped one. Use the `Agent`/`Task` tool with the agent type named above; that is what causes the receipt to be written. Reading the agent's instructions and performing the review yourself produces no receipt and does not satisfy the gate.

**Re-authorise after fixing findings.** The token covers one commit. Once you commit fixes, HEAD moves, the token no longer covers it, and dispatch is denied again — correctly, because the receipts are now stale too. Run `begin-review-round.sh` again for the next round.
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
Attested by: Claude (exloom session) — author self-attestation, not a reviewer sign-off
Date: <YYYY-MM-DD>
```

`Attested by` records who filled this document in. It is **not** evidence that anyone reviewed the code; the receipts under `.claude/reviews/<branch>.verdicts/` are. Never write a reviewer's name here.

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

Then stage the checklist **and the verdict receipts** and commit them together — the gate reads receipts from the committed ref, so an uncommitted receipt does not exist as far as the hooks are concerned:

```bash
git add .claude/reviews/<branch>.md ".claude/reviews/<branch>.verdicts"
```

**If** the repo has
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
- Escape hatches (a skipped step with written justification in the "Escape hatches used" section) ARE acceptable for narrative sections — a step with a recorded escape hatch counts as "addressed" for this check. But an unjustified skip is not an escape hatch, it is an incomplete checklist. **Two things have no escape hatch: an under-declared tier, and a missing reviewer receipt.** Those are the checks the gate does not take your word on, and writing prose at them will not move them.
- If the user says "skip this, emergency", the bypass is `EXLOOM_REVIEW_SKIP=1`, set in the Claude Code session env (`settings.json` `env`) — not inline before the command, or the hook won't see it. Be honest about what it does: the hooks honor it unconditionally and log the bypass to stderr; nothing requires or verifies a justification. Write one in the "Escape hatches used" section anyway, so the reason ships with the code, but do not tell the user the tooling enforces it.
