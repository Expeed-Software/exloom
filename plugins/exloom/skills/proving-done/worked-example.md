# Worked Example — proving-done

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


**Scenario:** Verifying a "user profile update" feature in a Spring Boot service. The implementation adds a PUT endpoint at `/api/v1/profiles/{id}`, a service method with validation, a repository query, and modifies an existing DTO to include new fields.

### Check 1: Re-read every modified file

Reading `ProfileController.java`, `ProfileService.java`, `ProfileRepository.java`, `UserDTO.java`, and `ProfileControllerTest.java` top to bottom.

Findings:
- Found a leftover `System.out.println("DEBUG: " + user.getEmail())` in the service class. This prints user PII to stdout in production. Removed.
- Controller catches `Exception` broadly instead of `ProfileNotFoundException`. This swallows unexpected errors like `NullPointerException` and returns misleading 404s instead of 500s. Narrowed the catch clause.

### Check 2: Hardcoded values audit

- `timeout: 5000` in the HTTP client builder for avatar upload. Environment-dependent — externalized to `application.yml` as `profile.avatar-upload.timeout-ms: 5000`.
- `maxRetries = 3` in the same class. Also environment-dependent — externalized to `profile.avatar-upload.max-retries: 3`.
- `MAX_BIO_LENGTH = 500` in `UserDTO`. Product-defined domain constant that does not vary by environment. Kept as a named constant.

All literals classified and documented.

### Check 3: Runtime environment assumptions

Session stored in `HttpSession`, which defaults to in-memory storage in Spring Boot. Works single-instance, breaks immediately with multiple replicas behind a load balancer — each instance has its own session map.

Resolution: added `spring-session-data-redis` dependency and configured Redis-backed sessions so session state is shared across instances.

Also found: avatar upload writes to local `/tmp` before uploading to S3. Path was not configurable. Added `profile.avatar-upload.temp-dir` to application config with `/tmp` as default, so containerized deployments can override it.

### Check 4: Plan deviations

One deviation: changed `UserDTO` to add `@Size(max = 500)` validation annotation on the new `bio` field. Original plan specified only the endpoint, service logic, and repository query — did not mention DTO validation changes.

Reason: input validation at the API boundary was necessary to enforce the bio length constraint before data reaches the service layer. Documented as a minor plan deviation with justification.

### Check 5: Unhandled edge cases

Concurrent updates to the same user profile have no optimistic locking. Two simultaneous PUT requests for the same profile ID result in last-write-wins with no conflict detection or notification.

Declared as a known gap — acceptable for V1 because profile updates are low-frequency and user-initiated. Follow-up noted: add a `@Version` column and optimistic lock check if usage patterns show concurrent editing becomes a real scenario.

### Check 6: Run lint/build/test

First run: `./mvnw test` — 2 failures in `OrderServiceTest`, not in profile-related tests. Investigated rather than dismissing as "unrelated."

Root cause: `TestDataFactory.createUser()` initializes a `User` object without the new `bio` field, triggering a not-null constraint violation in the H2 test database. The test fixture is shared across multiple test classes. Fixed the fixture to include a default bio value.

Second run: `./mvnw test` exited 0. 247 passed, 0 failed, 0 skipped.
`./mvnw checkstyle:check` exited 0. 0 violations.

### Check 7: Staff engineer test

"Would the senior engineer approve this without comments?"

- Session storage with replicas — caught and fixed in check 3.
- Concurrent update scenario — documented as known gap in check 5 with rationale.
- Hardcoded timeout — externalized in check 2.
- Debug PII logging — caught and removed in check 1.

Assessment: passes review without blocking change requests.

### Check 8: Production readiness rating

Initial rating (before running checklist): **6/10**

Gaps found: in-memory session storage that breaks in production, hardcoded timeout nobody can tune, user PII leaking to stdout via debug logging, broken shared test fixture that would fail CI.

Rating after applying fixes from checks 1-6: **9/10**

Remaining documented gap: no optimistic locking on concurrent profile updates. Classified as non-blocking for this PR given the low-frequency, user-initiated access pattern. Gap listed in PR description under "Known Limitations" so the reviewer sees it immediately.
