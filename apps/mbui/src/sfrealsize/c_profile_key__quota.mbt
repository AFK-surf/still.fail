// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `profile key` as `quota`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"profile","scope":"ws","key":"sub:codex:me@x.com"}
  let messages =
    #|[[{"path":["profile","quota","time","checkedAt","ago"],"set":"刚刚"},{"path":["profile","quota","windows",0,"left"],"set":96}]]
  put_changes(asked, "quota", messages)
}
