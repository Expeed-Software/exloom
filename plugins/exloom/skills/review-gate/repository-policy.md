# Repository policy — `.exloom.yml`

## Why it exists

Tier derivation matches hard-coded words: `auth`, `tenant`, `secret`, `crypto`,
`jwt`, `apikey`, `migrations/`. A repository that calls the same thing
`identity`, `iam`, `rbac`, `membership` or `access-control` derives a *lower*
tier for a change that should be the highest one.

That is not a configuration inconvenience. The tier is the one thing with no
escape hatch, precisely because it decides which gates apply — so a tier that
cannot be taught a repository's own vocabulary misclassifies exactly the changes
the gate exists for, silently, and the checklist afterwards looks correct.

`.exloom.yml` is repository **policy**, and only policy. The operational
settings — gate on/off, lane, round cap, test command — stay in their marker
files under `.claude/`. This file answers one question: what does risk look like
in *this* codebase.

## The file

```yaml
version: 1

risk:
  tier3:
    paths:
      - "**/identity/**"
      - "**/iam/**"
      - "**/rbac/**"
      - "**/access-control/**"
  tier2:
    paths:
      - "**/integration/**"

reviewers:
  require:
    security-auditor:
      paths:
        - "**/identity/**"
```

Commit it at the repository root. **Policy is read from `HEAD`, never from the
working tree** — an uncommitted edit is not in force. Without that rule a
developer could delete a line locally, push past the gate, and the policy the
team agreed on would never have applied to the one change that needed it.

## Two rules that are not negotiable

**Repository policy may only escalate.** Built-in rules always run. The
effective tier is the highest anything matched, and reviewers are added, never
removed. A `risk.tier1` rule over a path the built-ins call Tier 3 leaves it at
Tier 3.

There is no downgrade key, and no flag reserving one — a configuration that can
lower a built-in protection is an escape hatch on the check that deliberately
has none.

**An invalid policy blocks.** Three outcomes, no fourth:

| State | Behaviour |
|---|---|
| Valid `.exloom.yml` | enforced alongside the built-ins |
| No `.exloom.yml` | built-in rules alone — normal, not a warning |
| Invalid `.exloom.yml` | the gate refuses to run until it is fixed |

Falling back to the defaults on a parse error is the worst outcome available: an
author writes a Tier 3 rule for their identity module, a typo means it never
loads, the built-ins score the change Tier 1, and everybody believes a rule is
in force that never ran.

An unknown key is an error for the same reason. `risk.teir3` does not get
ignored; it stops the gate and names the likely fix.

## The format is deliberately tiny

This is a strict format that happens to look like YAML — not YAML.

**Supported:** `version:` with an integer; the fixed keys above; lists of
double-quoted glob strings; whole-line `#` comments; two-space indentation.

**Rejected, with an error naming the line:** tabs; three-space indent; trailing
comments; unquoted values; inline arrays (`paths: ["a", "b"]`); inline maps;
block scalars (`|`, `>`); anchors, aliases and merge keys; document markers
(`---`); any key not in the schema; any character in a glob outside
`A-Za-z0-9_./*?-`.

That boundary is the point. A reader this small cannot grow into a bad YAML
implementation, because the next value that would need richer syntax gets a
validation error instead of an accommodating patch to the parser. If a real need
for quoted colons or multi-line strings ever appears, that is the signal to
reach for a real parser — and by then you will know which values need one.

## Glob semantics

Patterns are matched against paths from `git diff --name-only`. They are **not**
shell globs: nothing depends on `globstar`, on what exists on disk, or on the
host's case rules.

| Form | Means |
|---|---|
| `**/` at the start | zero or more leading directories — so it also matches at the root |
| `/**` at the end | this path, or anything beneath it |
| `**` elsewhere | anything, separators included |
| `*` | anything **except** `/` |
| `?` | exactly one character except `/` |
| `.` | a literal dot |

```
**/identity/**    src/identity/TokenService.java    match
identity/**       identity/Auth.java                match
identity/**       src/identity/Auth.java            no match
src/*/auth/**     src/main/auth/X.java              match
src/*/auth/**     src/a/b/auth/X.java               no match
**/*.sql          db/migration/V1.sql               match
**/IAM/**         src/iam/Auth.java                 no match
```

The separator rule is the one that matters: a `*` that quietly spans `/` turns a
narrow rule into a broad one, and nothing in the output would say so.

**Matching is case-sensitive on every platform.** Git paths are case-sensitive
and Windows filesystems often are not; a case-insensitive matcher would derive
different tiers for the same repository on different machines, which is not a
property a review gate may have.

## Docs are still docs

A markdown file under a Tier 3 path stays Tier 0. The docs-only check runs
before any path rule, and a glob matching a `.md` file does not make it code.

## Seeing what it does

`/exloom-config` prints the effective configuration: built-in rules, repository
rules, the derived tier for the current diff, and which rule produced it.

`/review-init` writes the same reasoning into the checklist under **Tier derived
from**, so the PR reader sees why a two-file change is Tier 3 without running
anything, and CI can re-derive the tier and compare.

The Provenance block records a **policy fingerprint**, binding the review to the
policy that was in force rather than only to the code — so a change reviewed
under a policy the repo has since changed is visible as exactly that.
