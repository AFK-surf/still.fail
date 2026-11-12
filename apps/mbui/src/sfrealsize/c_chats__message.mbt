// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats` as `message`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":false}
  let messages =
    #|[[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["ws/maple","k-maple-0"],"ops":[{"path":["last","preview"],"set":"好的，我先跑一遍测试再合。"},{"path":["last","seq"],"set":301}]}]}]]
  put_changes(asked, "message", messages)
}
