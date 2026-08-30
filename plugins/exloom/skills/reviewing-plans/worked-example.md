# Worked Example — reviewing-plans

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


**Scenario:** Reviewing a plan titled "Add pagination to the products API" for a Micronaut service in an existing brownfield codebase. The plan was written by one developer and will be executed by another who is familiar with the codebase but was not involved in the design discussion.

The reviewer walks through all 9 checklist items.

**Item 1 — Sections present:** All 11 required sections found with substantive content, including a populated Tasks section. Deviation Log is empty as expected at plan time. PASS.

**Item 2 — Acceptance criteria testable:**
Criterion reads: "Products endpoint supports pagination." Can I verify this without asking the author? No. What does "supports" mean — query params, headers, response format? What page size? What response structure?
REJECT. Fixed: "GET /api/products?page=2&size=20 returns items 21-40 in the response body, with X-Total-Count header set to the total product count. Defaults: page=1, size=50."

**Item 3 — File paths exact:**
Plan lists `ProductController.java`, `ProductService.java`, `PagedResponse.java [new]`, and `ProductControllerTest.java` — all with full paths from repo root, extensions included, new file marked. PASS.

**Item 4 — Existing patterns referenced:**
Plan cites `CustomerController.java` for the existing offset-based pagination pattern using Micronaut Data Pageable, and explains how ProductController will follow it. PASS.

**Item 5 — Edge cases enumerated:**
Page beyond total: handled (empty array). Negative page: handled (400). Size exceeds max: handled (400). But size=0 is not listed. What happens — division by zero in offset calculation? Empty response? Error? The plan doesn't say.
REJECT. Author must add disposition for size=0 input.

**Item 6 — Non-goals explicit:**
"No cursor-based pagination. No infinite scroll. No caching (tracked in #312)." Each is specific and bounded. PASS.

**Item 7 — Executor FAQ populated:**
FAQ section is empty. On a multi-task plan, the executor will have questions: "Should existing unpaginated clients still get all results?" "Should I change the default page size?" "Does total count include soft-deleted products?"
REJECT. Author must populate FAQ with at least these questions answered.

**Item 8 — Review checklist agreed:**
Checklist covers pagination params, defaults, total count header, empty page response, existing tests, new edge case tests. Cross-references acceptance criteria. PASS.

**Item 9 — No TBDs:**
Text search finds "Test file for PagedResponse: TBD" in Files to Touch.
REJECT. Author must provide the exact test file path.

**Final result:** REJECTED — 4 items.

```
Plan rejected — 4 items require attention before execution.

Item 2 (Acceptance Criteria): "Products endpoint supports pagination" is not testable.
Fixed: "GET /api/products?page=2&size=20 returns items 21-40, X-Total-Count header equals total product count."

Item 5 (Edge Cases): size=0 input has no disposition.
Fixed: Add "size=0 returns 400 with validation error" or mark explicitly out of scope.

Item 7 (Executor FAQ): Empty on a multi-task plan.
Fixed: Answer at minimum — backward compat for unpaginated calls, default page size, soft-delete in counts.

Item 9 (No TBDs): "Test file for PagedResponse: TBD" is unresolved.
Fixed: Provide exact path, e.g., src/test/java/com/example/products/dto/PagedResponseTest.java.
```

Author fixes all four items and re-submits. Re-review covers the full checklist from scratch — do not assume passing items still pass after revision. Second review: all 9 items pass. Plan approved, executor assigned, work begins.

Note: this example had 4 rejections out of 9 items. That is typical for a first review of a plan written without the checklist in mind. After teams internalize the checklist, first-pass approval rates climb significantly — but never skip the review based on past approval rates.
