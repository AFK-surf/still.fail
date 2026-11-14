// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats` as `renamed`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":false}
  let messages =
    #|[[{"path":["days"],"key":["daysAgo"],"patch":-1,"ops":[{"path":["items"],"key":["station","id"],"patch":["ws/maple","k-maple-77"],"ops":[{"path":["title"],"set":"迁移演练：Postgres 15 → 17 切换"}]}]}]]
  put_changes(asked, "renamed", messages)
}
