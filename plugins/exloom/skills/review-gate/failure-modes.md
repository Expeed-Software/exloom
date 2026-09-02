# Failure modes — review-gate

What the gate catches, and what it does not. The second list is the useful one:
a gate whose limits are unwritten gets trusted for things it never did.

## Catches

- **A persisted-but-unread field.** The UI wrote a new field to a saved record;
  no backend code read it. The Tier 2 cross-layer contract check greps the
  backend for readers and flags zero; the adversarial review requires that check.
- **A silent parser or import regression.** A refactor quietly broke file import.
  The smoke test — importing a real file through the UI — fails immediately.
- **A write-only DB column.** A migration added a column, the entity persisted
  it, no query ever read it. Cross-layer contract step 4.

## Does not catch

### The reviewers share the implementer's model

L1, adversarial and security are separate *prompts*, not separate *reasoners*.
They give the change three different angles of attention, which is worth having,
and they do not give it three independent chances to be wrong.

Where a mistake comes from a misunderstanding the model holds — a framework's
actual behaviour, a library's default, what an annotation does — every reviewer
is liable to reproduce it, agree with the implementation, and record a clean
receipt. The receipt is honest: a reviewer really did run and really did
conclude that. It is evidence of attention, never of independence.

So a stack of green receipts is not grounds for "this was independently
verified." What closes this is a reviewer that does not share the model —
another vendor's model, a static analyser, a test the code has to survive, or a
person. Reach for one wherever being wrong is expensive.

### The gate binds this session, not the repository

The hooks run inside Claude Code. They see the tool calls this session makes,
and nothing else. A push from a terminal outside the session, a different
client, a disabled plugin, an edited `lib.sh`, a raw API call, or
`EXLOOM_REVIEW_SKIP=1` all reach the remote without passing anything.

That makes it a **developer-discipline gate, not an organisation-policy gate**.
It changes what the easy path produces — inside a cooperating session the lazy
route no longer yields a passing artifact — and it cannot make a claim about
what reached the default branch. Only something running where the code lands
can do that: CI reading the committed receipts, plus branch protection. The
evidence is committed and commit-bound precisely so that a checker on the other
side can read it, and until one exists, that side is unguarded.

### The rest

- **Performance regressions not visible in a single smoke run.** Load testing is
  out of scope.
- **Mid-flight state corruption during a cutover.** A flag cutover leaves some
  tenants on the old code path reading new-schema rows. Naming what a revert
  does not fix does not prove the system stays coherent *while* traffic is split
  across both paths. That is a property of a running deployment; only a staged
  rollout with real traffic observation surfaces it.
- **Code that lands after the adversarial pass.** Adversarial must approve
  somewhere on the branch, not on the tip, so fix commits made after it are
  never seen by it — and those are the commits most likely to touch the seam it
  exists to catch. Deliberate: requiring it to re-approve every fix is what
  makes a branch never converge. Still a real gap.
- **Security vulnerabilities in *unchanged* code.** The security review covers
  this change's security surface, not the pre-existing system. Audit the whole
  codebase separately.
- **Third-party API contract drift.** If a provider changes its webhook body and
  nothing in the diff reflects it, the gate notices nothing.
- **Race conditions that do not reproduce in a single-operator smoke test.**

For these, use dedicated tooling — load tests, chaos testing, a full-codebase
security audit. The protocol is necessary, not sufficient.

## What a receipt is and is not

A receipt proves a reviewer **ran** and states what it **concluded**. It says
nothing about whether the review was any good: a dispatched `l1-reviewer` that
returns "looks fine" writes a valid APPROVED receipt.

Most of the checklist is likewise self-attested — the findings, the smoke-test
output, the dispositions. The gate checks those are present and not placeholder
text. It cannot check they are true, and no additional field changes that.
