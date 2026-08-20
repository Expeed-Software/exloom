# Manual Security Scope

Scoped to what manual QA reliably catches. Manual testers find authorization defects; they do not find injection defects. Testing outside this scope produces noise and false confidence.

## In scope — generate these

| Area | Cases |
|---|---|
| **Authentication** | Reach the feature without logging in; use the feature after logout; use it after session expiry; use browser Back to return to a post-logout page |
| **Vertical privilege escalation** | A lower role reaches a higher-role action via direct URL, a bookmarked link, or a control that should be hidden |
| **Horizontal privilege escalation (IDOR)** | Change a record ID in the URL to another user's record; open a record from a copied link belonging to someone else |
| **Cross-tenant access** | Reach a record belonging to another account or tenant by ID or URL |
| **Data exposure** | Sensitive values visible in the UI, in error messages, in URLs, in exported files, or in email notifications |

Every story that involves roles, records, or tenants gets at least one authorization case. This is enforced by `coverage-checklist.md`.

## One sanity case only

**Input sanitization.** A single case confirming that injection-shaped input is rejected or safely escaped:

> Enter `<script>alert(1)</script>` in a free-text field, save, and reopen the record. The value is displayed as literal text; no dialog appears and no markup renders.

Do not expand this into a suite. Do not vary the payload. Do not probe.

## Out of scope — route to AppSec

Never generate cases for these:

- Exploitation of any discovered weakness
- Fuzzing or automated scanning
- DAST tooling
- TLS, header, or cryptography analysis
- Dependency CVE review
- Anything destructive to data or environment

If a story's risk clearly exceeds this scope, raise it as a **note to development** requesting AppSec review. Do not attempt it.

## Expected results for security cases

State what the user sees, not what happens internally — see `human-executability.md`.

| Verdict | Expected Result |
|---|---|
| Bad | `Returns 403` |
| Bad | `Access is blocked at the API layer` |
| Good | `The page shows "You do not have permission to view this record"; no opportunity fields, customer name, or amounts are visible anywhere on the page or in the page title` |

The second half matters. An authorization failure that renders an error banner while still leaking the record title in the browser tab is a real defect, and only an expected result written this way catches it.
