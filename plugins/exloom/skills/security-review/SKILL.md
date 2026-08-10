---
name: security-review
description: Use when reviewing a change for security before shipping — especially code that touches user input, auth, tenancy, secrets, data exposure, deserialization, external calls, cryptography, or dependencies, and especially AI-generated code. Runs real scanners plus a category review and produces evidence-backed findings. A first-pass aid, not a security guarantee.
---

# Security Review

## Overview

AI-generated code fails in specific, repeatable security ways: it hardcodes
secrets, concatenates user input into queries and shells, forgets the
authorization check its neighbors have, deserializes untrusted data, and imports
dependencies that are vulnerable or do not exist — and generated code tends to be
over-trusted, so these flaws ship. This review catches them before they do; it is
the security surface exloom's other gates barely touch.

It is deliberately **evidence-based, not vibes-based**: it runs the security tools
that exist in the repo and pastes their real output, then reviews the diff against
a fixed taxonomy. "No findings" is only allowed when the tools actually ran.

## Honest scope (say this to the user)

This is a **first pass, not a guarantee.** It does not certify code "secure"; the
strongest claim it makes is "no issues found by the checks that ran." Real
assurance for a high-risk change needs SAST/DAST, a dependency-vulnerability
service, and human security review or a pentest. Treat a clean result as "nothing
obvious," not "safe." A green check that people over-trust is worse than no check.

## When to run it

Run a security review when the change touches any of: **user-input handling,
authentication/authorization, tenancy, secrets or credentials, PII or data
exposure, deserialization/parsing, server-side outbound requests, cryptography, or
dependencies (added or updated).** Within `exloom:review-gate` it is required on
every **Tier 3** change and on any lower-tier change that hits one of those
surfaces. When in doubt, run it — it is cheap relative to a breach.

## How to do it — tools first

1. **Run the scanners that exist; paste real output.** Secrets (`gitleaks`,
   `git secrets`, or a token-pattern grep), a dependency audit
   (`npm audit` / `pip-audit` / `osv-scanner` / `govulncheck` / `cargo audit`),
   and static analysis (`semgrep --config auto`). Note honestly which were
   unavailable — an unrun check is a gap, not a pass.
2. **Verify new dependencies are real.** For every added package, confirm it
   exists on its registry and is the intended name. AI models hallucinate and
   typo-squat package names, which is a live supply-chain attack vector
   ("slopsquatting").
3. **Review the diff by category** — injection, authz/authn, secrets/PII,
   insecure deserialization, SSRF, crypto/randomness, unsafe defaults and missing
   validation. For each finding record `path:line`, the source→sink, the impact, a
   confidence (CONFIRMED vs SUSPECTED), and a concrete fix.

For a change of any real blast radius, dispatch the `security-auditor` agent to do
this against the diff — it encodes the full method and output format.

## Recording it in the gate

Security findings go in the **Security review** section of
`.claude/reviews/<branch>.md`: which tools ran (and which were missing), each
finding with severity and disposition (fixed / accepted-with-written-reason), the
list of new dependencies verified real, and the honest caveat that this was a
first pass. A change that opens a **Critical or High** finding does not ship until
it is fixed or explicitly risk-accepted in writing.

## What this does NOT do

- It does not prove the code is secure, and it does not replace SAST/DAST or a
  pentest.
- It reviews **this diff**, not the whole system or pre-existing unchanged code.
- It cannot see business-logic abuse (a legitimate user abusing a legitimate
  feature) or flaws the run tools miss.
- LLM reasoning about security is fallible — it misses real issues and
  occasionally invents them. That is exactly why this skill leans on real tools for
  evidence and marks anything unconfirmed as SUSPECTED.

## Integration

- **Part of:** `exloom:review-gate` — a required dimension at Tier 3 and for any
  security-touching change.
- **Runs via:** the `security-auditor` agent.
- **Pairs with:** `exloom:reviewing-code` (general quality) and the
  `adversarial-reviewer` (integration gaps) — security is the dimension neither of
  those systematically covers.
