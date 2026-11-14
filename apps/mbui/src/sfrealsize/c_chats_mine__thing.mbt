// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chats mine` as `thing`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chats","scope":"ws","mine":true}
  let messages =
    #|[[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["ws/maple","k-maple-0"],"ops":[{"path":["last","preview"],"set":"截图和新的 PR：[链接] [图片]"},{"path":["last","seq"],"set":301}]}]}]]
  put_changes(asked, "thing", messages)
}
