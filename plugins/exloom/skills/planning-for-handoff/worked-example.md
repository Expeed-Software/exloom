# Worked Example — planning-for-handoff

One feature taken through every step.

**Scenario:** Add CSV export to the orders page in an existing app (Angular frontend, FastAPI backend, PostgreSQL database). This is a brownfield feature — the app already has an orders listing page with filters, a reports module with a streaming PDF endpoint, and a shared download utility on the frontend.

What follows is a condensed but structurally complete plan. A real plan would have 8-12 tasks; we show 4 to illustrate the pattern.

---

**Acceptance Criteria** — taken from `docs/exloom/specs/F-024-orders-csv-export.md`, not written here. The plan cites; the spec defines.

| Ref | Criterion |
|---|---|
| `F-024/R-1/AC-1` | An "Export CSV" button appears on `/orders`, right-aligned in the filter bar |
| `F-024/R-1/AC-2` | Clicking it downloads a CSV of the currently filtered orders |
| `F-024/R-2/AC-1` | The CSV carries the columns `order_id`, `date`, `customer_name`, `total`, `status` |
| `F-024/R-2/AC-2` | The export respects the active filters — date range, status, search term |
| `F-024/R-3/AC-1` | 100k rows export without a browser timeout: streamed, never fully buffered |
| `F-024/R-4/AC-1` | An empty result set produces a CSV with headers only, and no error dialog |

**Non-Goals:**

- PDF export (separate feature, separate plan)
- Scheduled or recurring exports
- Email delivery of export files
- Export of individual order line items

**Files to Touch:**

| File | Action | Reason |
|---|---|---|
| `backend/app/api/orders.py` | Modify | Add `/api/orders/export` GET endpoint |
| `backend/app/services/order_export.py` | Create | Streaming CSV generation service |
| `frontend/src/app/orders/orders.component.ts` | Modify | Add export button click handler |
| `frontend/src/app/orders/orders.component.html` | Modify | Add export button to filter bar |
| `frontend/src/app/orders/orders.service.ts` | Modify | Add `exportCsv()` method |
| `tests/api/test_order_export.py` | Create | Endpoint and integration tests |

**Existing Patterns to Follow:**

- Streaming response: see `backend/app/api/reports.py:34-52` for `StreamingResponse` usage with CSV content type
- Angular service method: see `frontend/src/app/orders/orders.service.ts:28-35` for how `getOrders()` passes filter params to the API
- Test structure: see `tests/api/test_orders.py` for fixture setup and the `authenticated_client` helper

**Edge Cases:**

| Case | Decision |
|---|---|
| Empty result set | Return CSV with header row only. No error, no empty file. |
| 100k+ rows | Stream rows using `StreamingResponse`. Do not load all rows into memory. |
| Special characters in customer name (commas, quotes, newlines) | Use Python `csv` module — it handles RFC 4180 escaping correctly. |
| Concurrent exports by same user | Stateless endpoint, no server-side state. No conflict possible. |
| Database timeout on large query | Set query timeout to 30s via `statement_timeout`. If exceeded, return 504 with structured `ApiError`. |
| User has no orders matching current filters | Same as empty result set — CSV with headers only. |

**Executor FAQ:**

Q: New endpoint or extend existing `/api/orders`?
A: New endpoint at `/api/orders/export`. Keeps export concerns (streaming, CSV formatting) separate from list/pagination concerns.

Q: Date format in the CSV output?
A: ISO 8601 (`2026-04-12T14:30:00Z`), consistent with the existing API response format.

Q: How does the frontend trigger the file download?
A: Create a temporary `<a>` element with a `blob:` URL. See the existing pattern in `frontend/src/app/shared/download.util.ts:5-18`.

Q: Does the export endpoint require authentication?
A: Yes. Apply the same `@require_auth` decorator used on all other order endpoints.

Q: What if the user changes filters while an export is in progress?
A: No issue. The export captures the filter state at request time. The frontend disables the export button during the download to prevent confusion, but concurrent requests are safe.

Q: Should I add a progress indicator?
A: No. This is a non-goal for v1. Streaming means the browser shows its native download progress, which is sufficient.

**Tasks (showing 4 of ~9 total):**

**Task 1: Create streaming CSV service**
- Serves: `F-024/R-2/AC-1`, `F-024/R-3/AC-1`
- File: Create `backend/app/services/order_export.py`
- Pattern: Follow service structure from `backend/app/services/order_service.py` — class with injected repository
- What to do: Implement `OrderExportService` with a `generate_csv_rows(filters)` generator method. Use `csv.writer` writing to `io.StringIO`, yielding each row as a string. First yield is the header row: `order_id,date,customer_name,total,status`.
- Validation: `python -c "from app.services.order_export import OrderExportService; print('import ok')"` prints `import ok` with no errors
- Commit: `feat(orders): add streaming CSV generation service`

**Task 2: Add export endpoint**
- Serves: `F-024/R-1/AC-2`, `F-024/R-2/AC-2`, `F-024/R-3/AC-1`
- File: Modify `backend/app/api/orders.py` — add new route after the existing `get_orders` route (line ~45)
- What to do: Add `GET /api/orders/export` that accepts the same query params as `get_orders` (`date_from`, `date_to`, `status`, `search`). Inject `OrderExportService`, call `generate_csv_rows(filters)`, wrap in `StreamingResponse(media_type="text/csv")`. Set header: `Content-Disposition: attachment; filename="orders-export-{iso_timestamp}.csv"`.
- Validation: `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "http://localhost:8000/api/orders/export"` returns `200`
- Commit: `feat(orders): add CSV export endpoint with streaming response`

**Task 3: Write export endpoint tests**
- Serves: `F-024/R-2/AC-1`, `F-024/R-2/AC-2`, `F-024/R-4/AC-1`
- File: Create `tests/api/test_order_export.py`
- Pattern: Follow `tests/api/test_orders.py` — same `authenticated_client` fixture, same database seeding approach
- What to do: Write 5 tests: (1) authenticated GET returns 200 with `text/csv` content type, (2) response body contains correct CSV header row, (3) filter params are applied (seed 3 orders, filter to 1, assert 1 data row), (4) empty result returns header row only, (5) unauthenticated GET returns 401
- Validation: `pytest tests/api/test_order_export.py -v` — all 5 tests pass. Name each test after the criterion it covers, e.g. `def test_F024_R4_AC1_empty_result_returns_header_only():`, so the proof run records which criteria the suite actually proved.
- Commit: `test(orders): add CSV export endpoint tests`

**Task 4: Add export button to orders page**
- Serves: `F-024/R-1/AC-1`, `F-024/R-1/AC-2`
- File: Modify `frontend/src/app/orders/orders.component.html` — insert after the filter bar closing div (line ~28)
- What to do: Add `<button class="btn btn-outline" (click)="onExportCsv()">Export CSV</button>` inside the filter bar, right-aligned using the existing `ml-auto` utility class pattern from the page header.
- File: Modify `frontend/src/app/orders/orders.component.ts` — add `onExportCsv()` method
- What to do: `onExportCsv()` calls `this.ordersService.exportCsv(this.currentFilters)`, subscribes to the blob response, and triggers download using the helper in `frontend/src/app/shared/download.util.ts`.
- Validation: `ng serve`, navigate to `/orders`, confirm the Export CSV button appears right-aligned in the filter bar. Click it, confirm a `.csv` file downloads.
- Commit: `feat(orders): add CSV export button to orders page`

Notice what this example plan does:

- Every task cites the criteria it serves, by ref — a task that cites nothing is scope creep, and writing the citation is where you notice
- Every task names exact files with paths, not descriptions
- Every task has a validation command with specific expected output
- Every edge case has a decision — handle it or mark it out of scope
- Every FAQ answers a question the executor would actually ask during execution
- Existing patterns are pointed to by file path and line number, not described in prose
- Non-goals are explicit — no one will accidentally build PDF export

The plan is long. It is also unambiguous. An executor picks this up and starts working within minutes — no Slack messages, no reverse-engineering intent, no rework from misunderstood requirements. That is the goal of every plan you write.

---
