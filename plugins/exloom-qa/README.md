# exloom-qa — Claude Code plugin

Turns an Azure DevOps user story into reviewed, traceable, **human-executable** manual test cases — published to the board and linked to the story only after a QA engineer explicitly approves them.

The QA-side sibling of [exloom](../exloom/README.md).

> **Status: 0.1.0 — pre-pilot.** Skills, coverage auditor, and the approval gate are built and tested. Not yet exercised against real stories; see the build plan for the pilot.

## Install

```
/plugin marketplace add https://github.com/Expeed-Software/exloom
/plugin install exloom-qa@exloom
```

## Setup

Three one-time steps. There is **no MCP server to configure** and no personal access token to create.

```
az login --tenant <your-org-tenant>
az extension add --name azure-devops
```

> **Watch the tenant.** If your `az` session is on the wrong tenant, Azure DevOps does not return a clear
> "not authorized" error — it returns a **302 redirect to a sign-in page**, which surfaces as an odd HTML
> response or a silent failure. If board calls behave strangely, check `az account show` before anything else.

The plugin uses whatever board access you already have. If you can write test cases by hand, you can run this.

## What it does

1. **Captures story context** — the story is a delta, not a spec. It fetches the work item, then proposes the navigation path and upstream/downstream dependencies for you to confirm or correct, one at a time.
2. **Generates test cases** — assesses story complexity first and scales volume to it, applies named test-design techniques, and traces every case back to an acceptance criterion.
3. **Audits coverage** — a separate reviewer looks for both gaps *and* padding before you see anything.
4. **Reviews with you** — summary table in chat, full details below it, surgical edits only. Nothing is renumbered.
5. **Publishes on approval** — creates approved Test Cases, sets the Steps grid, and links each one `Tests → User Story`.
6. **Learns** — your corrections to generated steps become durable knowledge about the application, so the next story starts closer to right.

## The approval gate

A `PreToolUse` hook inspects every Bash command and blocks Azure DevOps writes that it cannot tie to an approved test case. It is on by default and **fails closed** — a command it recognises as a tracker write but cannot verify is denied.

| Command | Result |
|---|---|
| Reading a work item, WIQL queries, `az login` | allowed |
| Creating a Test Case tagged with an approved TC id | allowed |
| Creating a Test Case with no artifact, no approval record, or an unapproved id | **denied** |
| Creating a Test Case with no provenance tag | **denied** |
| Deleting any work item | **denied** |
| Anything touching Test Plans or Test Suites | **denied** |

Denials explain the failure and name the command that fixes it.

Audited bypass: set `EXLOOM_QA_SKIP=1` in your session env (`settings.json` → `env`). An inline `EXLOOM_QA_SKIP=1 <cmd>` will not work — the hook reads its own environment, not the command's.

Behaviour is covered by `scripts/test-qa-gate.sh` in the repository root; run it after any change to the hook.

## Two things to know

**Test cases are authored, not runnable.** Test Plans and Test Suites are out of scope by design. Published cases are linked and traceable, but a case belonging to no suite cannot be executed through the Test Plans runner, so there is nowhere to record pass/fail per run. Adding cases to a suite remains a manual step.

**Test Cases cannot be un-created easily.** Azure DevOps refuses to delete Test Case work items through the normal work-item API, and the Test Management API deletes them permanently with no recycle bin. This is why approval is enforced by a hook rather than requested politely.

## License

[MIT](../../LICENSE).
