// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats mine` as `member`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":true}
  let messages =
    #|[[{"path":["members"],"set":13}]]
  put_changes(asked, "member", messages)
}
