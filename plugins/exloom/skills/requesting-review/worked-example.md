# Worked Example — requesting-review

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


**Scenario:** You completed the CSV export feature for the orders module. The stack is Angular (frontend) + FastAPI (backend). A plan existed. One deviation occurred during implementation. Verification has already been run.

Here is the complete PR body as it would appear when the PR is opened:

---

**Title:** `feat(orders): add CSV export with streaming for large result sets`

### Summary

**What:** Adds a CSV export feature to the orders list page. Users can export filtered order data as a CSV file directly from the orders table toolbar.

**Why:** Operations team currently copies data manually from the UI into spreadsheets for monthly reconciliation. This takes 2-3 hours per report and is error-prone. CSV export eliminates the manual step entirely.

**How:** The backend uses a streaming response (`StreamingResponse` in FastAPI) to generate CSV rows on the fly, avoiding loading the full result set into memory. This handles exports up to 500k rows without memory pressure. The Angular frontend triggers the download via a hidden anchor element with a blob URL, which avoids browser popup blockers. Column selection matches the current table configuration — whatever columns the user has visible are the columns that export.

### Plan

`docs/exloom/plans/PROJ-234-csv-export.md`

### Deviations from Plan

| Plan Step | Expected | Actual | Justification |
|-----------|----------|--------|---------------|
| Step 6: No progress indicator | Export starts and completes silently | Added progress indicator for exports >10k rows | User testing showed exports over 10k rows took 4-8 seconds. Without feedback, users clicked the export button repeatedly, generating duplicate requests. Progress indicator prevents this. |

### Test Evidence

```
Command: pytest tests/ -v
Exit code: 0
Result: 12 passed, 0 failed, 0 skipped

Command: ng test --watch=false
Exit code: 0
Result: 8 specs, 0 failures

Command: ruff check src/
Exit code: 0
Result: All checks passed

Command: ng lint
Exit code: 0
Result: All files pass linting
```

### Screenshots

**Before:** Orders page without export capability
![Orders page before — no export button in toolbar](before-orders-page.png)

**After:** Orders page with export button and progress indicator
![Orders page after — export button in toolbar, progress bar shown during export](after-orders-export.png)

### Review Checklist

Review against the team's review checklist

---

**What this PR body accomplishes:** The reviewer knows the feature, the business justification, the technical approach (and why streaming was chosen over buffering), the one deviation and its rationale, the exact test results, and what the UI looks like. They can begin reviewing the code with full context immediately.

**What it does not do:** It does not restate the diff. It does not say "updated orders.component.ts" — the reviewer can see that in the file list. Every sentence in the body adds context that the diff alone cannot provide.

**For a trivial change,** the same structure applies but compressed. A typo fix PR body might be:

> **Summary:** Fixed typo in error message shown to users during checkout timeout — "timout" → "timeout".
> **Plan:** No plan — trivial fix.
> **Deviations:** N/A.
> **Test evidence:** `ng test --watch=false` exited 0 — 247 specs, 0 failures.
> **Screenshots:** N/A.
> **Review checklist:** Review against the team's review checklist

Five lines. Still structured. Still verifiable. The structure scales down gracefully — it does not require padding for small changes.

---
