// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `connects` as `session`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"connects","scope":"ws","mine":false}
  let messages =
    #|[[{"path":["items",0,"connect","sessions"],"set":34}]]
  put_changes(asked, "session", messages)
}
