// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart logins` as `login`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"logins"}
  let messages =
    #|[{"value":[{"id":"login-1","runtime":"codex","job":{"profile":"codex-new","runtime":"codex","state":"needs_approval","url":"https://auth.openai.com/codex/device","userCode":"QH7K-2M9P","startedAt":1791277080650,"expiresAt":1791277980650,"browser":true}}]}]
  put_changes(asked, "login", messages)
}
