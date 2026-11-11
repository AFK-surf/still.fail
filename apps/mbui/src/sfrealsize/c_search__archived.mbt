// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `search` as `archived`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"search","scope":"ws","query":"迁移"}
  let messages =
    #|[[{"path":["messages"],"key":["station","thread","seq"],"drop":["ws/maple",2002,1599]},{"path":["messagesMore"],"set":false}]]
  put_changes(asked, "archived", messages)
}
