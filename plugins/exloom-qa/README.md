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

There is **no MCP server to configure** and **no personal access token to create**. The plugin uses the board access you already have — if you can write test cases by hand, you can run this.

You need three things: the **Azure CLI** with its `azure-devops` extension, **Python**, and **bash** (already present on Windows via Git Bash, which is what Claude Code runs hooks in).

### 1. Azure CLI

If `az version` already works, skip ahead.

The official MSI installer, and `winget install Microsoft.AzureCLI`, both **require administrator rights**. If you have them, use the installer.

**Without admin rights**, install Python first and get the CLI through pip — this covers the Python requirement at the same time:

```
winget install Python.Python.3.12
```

Open a **new terminal** (the installer updates PATH; existing windows won't see it), then:

```
python -m pip install --user azure-cli
```

This takes a few minutes and prints warnings like *"The script … is installed in `C:\Users\<you>\AppData\Roaming\Python\Python312\Scripts` which is not on PATH"*. That is expected — note that directory and add it to your **user** PATH, in PowerShell:

```powershell
$u = [Environment]::GetEnvironmentVariable("Path","User")
[Environment]::SetEnvironmentVariable("Path", "$u;C:\Users\<you>\AppData\Roaming\Python\Python312\Scripts", "User")
```

Read the User value first rather than using `$env:Path`. `$env:Path` also contains the machine PATH, and writing that into the user PATH copies every system entry into it.

Open another new terminal and confirm:

```
az version
```

### 2. The Azure DevOps extension

```
az extension add --name azure-devops
```

### 3. Sign in

```
az login --allow-no-subscriptions
```

**`--allow-no-subscriptions` matters.** Azure DevOps access and Azure *subscription* access are different things, and most QA engineers have the first without the second. Plain `az login` insists on finding a subscription and fails with *"No subscriptions found for …"* even though your board access is fine.

If your account belongs to more than one tenant, name the one that owns the Azure DevOps organisation:

```
az login --allow-no-subscriptions --tenant <tenant-id>
```

### 4. Prove it

The login output is not the test — a board call is:

```
az boards work-item show --id <any work item id> --org https://dev.azure.com/<your-org>
```

If the work item comes back, you are set up.

### If something goes wrong

**Board calls behave strangely, or return HTML.** Your `az` session is probably on the wrong tenant. Azure DevOps does not return a clear "not authorized" — it returns a **302 redirect to a sign-in page**, which surfaces as odd output or a silent failure. Check `az account show` and re-run `az login` with the right `--tenant`.

**`python3` says "Python was not found; run without arguments to install from the Microsoft Store".** That is a Windows App Execution Alias stub, not your Python. Installs from winget and python.org provide `python` but not `python3`. The plugin handles this — it resolves the interpreter by running it rather than by name — so `python` alone is fine. To silence the stub: Settings → Apps → Advanced app settings → App execution aliases.

**`az: command not found` right after installing.** Either the Scripts directory is not on PATH (step 1), or the terminal predates the PATH change. Open a new one.

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
