# Tracker Adapters

All tracker access goes through the four operations below. No other file issues tracker commands.

Azure DevOps only in v1, via the `az` CLI. No MCP server. Organization and project are always passed explicitly, never hardcoded.

## Operations

| Operation | Command |
|---|---|
| `fetch_story` | `az boards work-item show --id <story-id> --org <org> --output json` |
| `create_test_case` | `az boards work-item create --type "Test Case" --title "<objective>" --org <org> --project <project> --fields "Microsoft.VSTS.TCM.Steps=<steps-xml>" "Microsoft.VSTS.Common.Priority=<0-3>" "System.Tags=<tags>"` |
| `update_test_case` | `az boards work-item update --id <mapped-id> --org <org> --fields ...` |
| `link_test_case` | `az boards work-item relation add --id <tc-id> --relation-type "tests" --target-id <story-id> --org <org>` |

`--relation-type` is lowercase `tests`; it maps to `Microsoft.VSTS.Common.TestedBy-Reverse`. One call writes both sides — the story gains a `Tested By` link automatically.

## Before approval

Read-only only. `fetch_story` is the sole permitted operation. No creates, no updates, no links.

## Steps XML

`Microsoft.VSTS.TCM.Steps` holds an XML blob. One `<step>` per test step; the first `parameterizedString` is the action, the second is the expected result. Inner HTML is entity-escaped.

```xml
<steps id="0" last="3">
  <step id="2" type="ActionStep">
    <parameterizedString isformatted="true">&lt;DIV&gt;&lt;P&gt;Open the webhook configuration screen.&lt;/P&gt;&lt;/DIV&gt;</parameterizedString>
    <parameterizedString isformatted="true">&lt;DIV&gt;&lt;P&gt;The list of configured webhooks is displayed.&lt;/P&gt;&lt;/DIV&gt;</parameterizedString>
    <description/>
  </step>
</steps>
```

Rules:
- Step `id` starts at **2** and increments by 1.
- `last` is the final step id.
- Escape `<`, `>`, `&`, and `"` inside the text as `&lt;` `&gt;` `&amp;` `&quot;`.
- The whole blob is a single `--fields` value; quote it so the shell passes it intact.

Verified working: angle brackets, entities, quotes, and `=` inside XML attributes all survive shell and CLI parsing.

## Tags

Every published case carries **two** provenance tags plus its test types:

```
System.Tags=exloom-qa:<story-id>; exloom-qa:<story-id>:TC-<nnn>; <Test Type>; <Test Type>
```

Example: `exloom-qa:24501; exloom-qa:24501:TC-007; Negative; Validation`

Both tags are required. WIQL `CONTAINS` on `System.Tags` matches **whole tags, not substrings** — verified. Without the separate story-level tag there is no way to enumerate a story's published cases in one query, only to look up TCs whose ids you already know.

| Query | WIQL |
|---|---|
| All cases published for a story | `[System.Tags] CONTAINS 'exloom-qa:<story-id>'` |
| One specific case | `[System.Tags] CONTAINS 'exloom-qa:<story-id>:TC-<nnn>'` |

The provenance tags serve four purposes:

| Purpose | How |
|---|---|
| Gate enforcement | The hook extracts it and checks the TC id against the approved list |
| Idempotency | Query by tag to find already-published cases before creating |
| Traceability | Anyone on the board sees which story's set a case came from |
| Test type | ADO has no multi-value type field, so types ride in tags |

A create command without a well-formed provenance tag is denied by the gate.

## Idempotency

Before creating, resolve what already exists:

1. Read the `TC → work-item-id` map in `.claude/qa/<story-id>.md`.
2. If the map is missing or incomplete, query the board by the story-level tag to recover the whole published set in one call.
3. Mapped or found → `update_test_case`. Not found → `create_test_case`, then record the id in the map.

Never create a case whose TC-level tag already exists on the board.

## Deletion

Not supported, and not a gap to fix. Azure DevOps refuses to delete Test Case work items through the work-item API; removal requires the Test Management API and is **permanent, with no recycle bin**.

Consequence: a wrong publish cannot be cleanly undone. Correct before publishing, never after.

## Jira

Deferred. Same shape — a shell command plus JSON, against Jira's REST API. Representation (Xray, Zephyr, or an issue-type convention) is unresolved. Nothing outside this file changes when it lands.
