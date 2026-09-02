# Rationale — review-gate

Why the gate is shaped the way it is. Read once; the operating rules are in
[SKILL.md](SKILL.md).

## The blind spot the gate exists for

A change can pass every review it is given and still be broken, because reviews
that work from documents, specs, or single-layer code reads share one blind
spot: nobody boots the application, and nobody traces a value from a user action
through to an observable effect. A field the UI persists that no backend code
reads survives all of them. That failure is common, not exotic.

Two things catch it, and neither is a document review: a real smoke test, and a
hostile pass aimed specifically at cross-layer contracts. Reviews that grade the
author's own spec against the author's own code tend to rubber-stamp; per-layer
contract checks are blind to the seam between layers.

Hence the shape: every change needs an L1 review and a real smoke test — booted
system, executed user action, observed result. Anything user-facing or
cross-module also needs a cross-layer contract grep and a hostile pass. Anything
touching migration, flags, or production needs a runbook and a statement of what
reverting does not fix.

## Four rules people expect that do not exist

Sessions impose these on themselves, and each one multiplies rounds. The table
in SKILL.md states them; this is why each is wrong.

**Every required reviewer must approve the same commit.** Only `l1-reviewer`
must cover the commit you ship. Requiring simultaneity means N reviewers chase a
target that moves every time one of them is answered — the probability that all
N are satisfied at one commit falls off a cliff as N grows, and each fix resets
the ones that were already happy. The decomposition is principled rather than a
cost compromise: L1 is about the code as written, so it must see the final text;
adversarial and security are about design and integration, which a null-check
fix does not change.

**The working tree is frozen while a reviewer reads it.** There is no freeze
marker and no state machine. Inventing one produces a session that refuses to
edit files while waiting on a subagent, which is a deadlock with no exit.

**A source edit is blocked until a plan is approved.** There is no plan gate.
The one enforced gate is at push.

**A finding must be fixed across its whole class, with a test proving the class
is closed.** A reviewer may note that a finding looks like one of a class; it may
not demand a general fix. Fixing the instance and tracking the class in a ticket
is a normal answer, not a lesser one. The alternative turns a one-line change
into a predicate, a new method, a refactor and four test classes — all new
unreviewed code that the next round then finds defects in. That is how a branch
grows every round and never ships.

If you find yourself enforcing something the gate does not ask for, stop.
Self-imposed process is the most common cause of a branch that will not
converge, and it is invisible in the checklist afterwards.

## Why the lane is chosen and the tier is derived

Tiers scale *review depth*, and depth should follow the blast radius of the
diff — which is a property of the diff, so it is derived and not negotiable.
Ceremony is different: a spec, a plan and a fidelity audit are worth their cost
on a feature and are pure overhead on a one-line fix, and no amount of reading
the diff tells you which one you are in. That is a decision, so it is declared.

Collapsing the two axes is what makes a review protocol get abandoned. Scale
ceremony with blast radius and every small change pays for a spec; scale depth
with the declaration and a migration can be labelled a spike.

The guard rails follow from that. Sprint is refused at Tier 3 because
migrations, auth, tenancy, secrets and crypto are exactly the stakes that earn
rigour — "earned by stakes" has to cut both ways or it is a bypass with a
friendlier name. And a lane may never weaken the proof receipt, the smoke test,
the derived tier, or receipt forgery-resistance: a lane changes how much happens
before the code, never whether the evidence is real.

## Why /harden rather than a rewrite

A Sprint branch that turns out to matter recovers its spec from the diff that
now exists, flips the lane, and names what the higher bar requires. Nothing is
regenerated and no ref changes.

A spec written before the code is a guess. One recovered from code that runs and
passes its tests describes something real — which makes it the better review of
the two, not a salvage operation.

## Provenance attestation

When the gate is on, `/review-complete` records a Provenance block — whether AI
assisted, the model id, the human who directed the work, the base commit, the
date, and the fingerprint of the repository policy in force — and the hooks
refuse to ship without it. Bound to the reviewed commit, it is a committed audit
trail of *how* the change was produced. That is the evidence ISO 42001 and SOC 2
auditors and cyber-insurers ask for; position it there and not on the EU AI Act,
which governs synthetic media rather than source code.

The policy fingerprint is what lets a later reader tell that a change was
reviewed under a policy the repo has since changed — the code commit alone
cannot say that.

- **v1 (default).** The record is committed and commit-bound. Tamper-evident
  through git history; the model id is self-reported, which is cooperating-team
  trust rather than verification.
- **v2 (opt-in).** Create `.claude/exloom-provenance-signed.enabled` and the
  attestation commit must be a signed git commit — `/review-complete` uses
  `git commit -S` and the hooks `git verify-commit` it, giving verified-identity
  non-repudiation with an existing GPG or SSH key. No sigstore, cosign or
  in-toto. Verification needs the signer's key trusted wherever the hook runs,
  which is a documented setup step and fail-closed by design.

It is evidence, not compliance certification, and a branch-level declaration
rather than per-line attribution.
