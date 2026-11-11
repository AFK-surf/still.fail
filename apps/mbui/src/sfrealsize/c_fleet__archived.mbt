// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `fleet` as `archived`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"fleet","scope":"ws"}
  let messages =
    #|[[{"path":["today","stats",0,"value"],"set":"1 个"},{"path":["week","days",6,"share"],"set":1},{"path":["week","days",6,"value"],"set":"1 个"},{"path":["week","stats",0,"value"],"set":"1 个"}]]
  put_changes(asked, "archived", messages)
}
