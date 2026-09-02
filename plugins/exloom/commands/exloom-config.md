# /exloom-config

Print the effective exloom configuration for this repository: the built-in
rules, whatever `.exloom.yml` adds, and — if there is a diff — the tier those
rules derive for it and exactly which rule did it.

A gate that cannot say *why* it decided something is a gate people argue with
rather than fix. This is the command that answers "why the hell is this
Tier 3?" without anyone reading a shell script.

## Step 1 — Load the library

```bash
# ${CLAUDE_PLUGIN_ROOT} is set for plugin.json hooks, NOT in your shell.
# Resolve the installed plugin instead; several versions live in the cache,
# so take the highest.
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
. "$LIB"
```

`sort -V | tail -1` matters: `find` returns cached versions path-sorted, so
`head -1` would source the oldest one installed.

## Step 2 — Report the policy state first

```bash
exloom_policy_load; echo "rc=$?"
exloom_policy_error
exloom_policy_fingerprint
```

Three outcomes, and they are not the same thing:

- **rc 0, no error, fingerprint set** — a valid `.exloom.yml` is in force.
- **rc 0, no error, fingerprint `none`** — no policy file. The built-in rules
  stand alone. This is normal and not a warning.
- **non-zero rc with an error** — the policy is invalid and **the gate is
  currently blocking every push on this branch**. Print the error verbatim and
  stop; nothing below it is meaningful until the file parses.

## Step 3 — Print the effective configuration

Read the marker files directly (they are one value each) and the policy through
the functions. Do not re-implement the parsing.

```
exloom effective configuration — <repo name>

Gate:            enabled | off        (.claude/exloom-gate.enabled)
Lane:            standard             (.claude/exloom-lane, else default)
Max rounds:      3                    (.claude/exloom-max-rounds, else default)
Signed provenance: no                 (.claude/exloom-provenance-signed.enabled)
Test command:    <committed value>    (.claude/exloom-test-command)
Policy:          .exloom.yml @ <fingerprint prefix>   | none

Risk rules

  Built-in Tier 3
    data migration paths (migrations/, liquibase/, flyway/, changelog)
    auth / tenancy / secrets / crypto / jwt / apikey

  Built-in Tier 2
    deployment surface (deployment/, k8s/, helm/, docker/)
    API or route surface (controller, routes, api, endpoint, resolver)
    five or more files changed

  Repository Tier 3   (.exloom.yml)
    **/identity/**
    **/iam/**

  Repository Tier 2   (.exloom.yml)
    **/integration/**

Required reviewers by tier
  Tier 0, 1   l1-reviewer
  Tier 2      l1-reviewer, adversarial-reviewer
  Tier 3      l1-reviewer, adversarial-reviewer, security-auditor
  Repository adds   security-auditor for **/identity/**
```

State plainly that repository rules are **additive**: they can raise a tier and
add a reviewer, and there is no configuration that lowers either.

## Step 4 — If the branch has a diff, explain it

```bash
exloom_derive_tier HEAD; exloom_tier_reasons
```

```
Current change (12 files vs <fork point>)

Derived tier:  3

Why:
  src/identity/TokenService.java  →  **/identity/**    .exloom.yml:risk.tier3
  db/migrations/V14__roles.sql    →  data migration    built-in

Effective tier: 3   (sprint lane would cap the reviewer set at 1)
Required reviewers: l1-reviewer, adversarial-reviewer, security-auditor
```

If `exloom_tier_reasons` is empty and the tier is 0 or 1, say so — "no rule
matched; Tier 1 is the floor" is an answer, and an empty section is not.

On a protected branch, or with no fork point, `exloom_derive_tier` returns
nothing. Say that the tier cannot be derived here and why, rather than printing
a blank.

## Rules

- **Read, never write.** This command changes nothing. If the policy is
  invalid, print the error and tell the user to fix the file — do not offer to
  edit it as part of this command.
- **Report what is committed.** Policy is read from `HEAD`, so an uncommitted
  `.exloom.yml` edit is not in force yet. If the working tree differs from
  `HEAD`, say so explicitly — that gap is the most confusing state this file
  has, and it will produce a "but I fixed it" conversation otherwise.
- Do not guess at values you cannot read. A marker file that does not exist is
  reported as its default, named as the default.
