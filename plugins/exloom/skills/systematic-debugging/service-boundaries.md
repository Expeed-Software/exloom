# Debugging Across Service Boundaries — systematic-debugging

Extracted from SKILL.md so the skill loads lean.


When a bug spans multiple services, the standard 7-step process still applies — but steps 1-2 (reproduce and isolate) require cross-service evidence. This is where most teams waste time: each service team assumes the bug is in the other service, and nobody reproduces it end-to-end.

**1. Reconstruct the timeline.** Collect logs from all involved services using the correlation ID (per your logging setup). Sort by timestamp. The goal is a single chronological narrative: request entered Service A at T1, left at T2, entered Service B at T3, failed at T4. If your services don't emit correlation IDs, add them before debugging — you cannot trace what you cannot correlate.

**2. Find the boundary where data changed.** The bug lives at the point where correct data becomes incorrect. Compare the outbound payload from Service A with the inbound payload at Service B. If they match and the data is already wrong, the bug is upstream. If Service A sent correct data but Service B received something different, the bug is in serialization, transport, or deserialization — check content types, encoding, field name casing, date format assumptions, and timezone handling. If Service B received correct data and produced wrong output, the bug is in Service B's logic.

**3. Own-service-first rule.** Assume the bug is in your service until evidence proves otherwise. Do not open a ticket on another team's service saying "your service returns wrong data" without a reproduction case that demonstrates their service returning wrong data for a valid request. The reproduction case must include the exact request you sent (not a paraphrase), the exact response you received, and why the response is wrong according to the API contract. Without this, you are sending another team on a wild goose chase based on your assumption.

**4. Reproduce at the boundary.** Once you've identified which service boundary the bug crosses, isolate it: call the upstream service directly with the same input and verify its output. Then call the downstream service directly with that output and verify its behavior. This turns a distributed bug into two local bugs that can each be debugged with the standard 7-step process.

**5. Shared state bugs.** The hardest cross-service bugs involve shared state — a database both services read, a cache one service writes and another reads, an event stream with ordering assumptions. For these, the timeline reconstruction in step 1 is critical: you need to know the exact order of reads and writes across services to identify the race or staleness window.
