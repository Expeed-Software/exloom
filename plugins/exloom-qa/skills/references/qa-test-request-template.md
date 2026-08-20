# QA Test Request Template

For async use — fill this in before starting, or let `capturing-story-context` interview you instead. Sections left blank or templated are covered by the interview.

```markdown
# AI QA TEST REQUEST

## Azure DevOps

Project Name:
<ENTER PROJECT NAME>

User Story ID:
<ENTER WORK ITEM ID>


## How to Reach the Functionality

Login > Menu > Sub Menu > Feature > Screen

Navigation / Steps:
<ENTER THE STEPS REQUIRED TO REACH THE FUNCTIONALITY>

If a specific account type or role is required, name the role only — never credentials.


## Upstream Dependencies

Things that must exist, happen, or be configured before this functionality can be used.

- <DEPENDENCY 1>
- <DEPENDENCY 2>
- <DEPENDENCY 3>

If there are none: None


## Downstream Dependencies

Things that may be affected after this functionality is completed.

- <DEPENDENCY 1>
- <DEPENDENCY 2>
- <DEPENDENCY 3>

If there are none: None
```

## Why these four things

The story describes a change. It does not describe how to reach the screen, what must exist first, or what breaks afterwards. Those three gaps are what turn acceptance criteria into a test set that reflects the real application.

Dependencies are not background information — they generate cases directly. Each upstream dependency produces missing / invalid / wrong-state cases; each downstream dependency produces a regression case. See `technique-catalog.md`.

## Examples

| Field | Example |
|---|---|
| Navigation | `Login as Manager > Dashboard > Customers > select a customer > Opportunities > Create Opportunity` |
| Upstream | `Customer must exist`, `Subscription must be active`, `User must have Manager role`, `At least one active product` |
| Downstream | `Invoice generation`, `Pipeline dashboard totals`, `Approval notification email`, `Audit log` |

Never include passwords or credentials. Name the role, not the account.
