// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatRow` as `message`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatRow","station":"ws/maple","session":"k-maple-0"}
  let messages =
    #|[[{"path":["last","preview"],"set":"好的，我先跑一遍测试再合。"},{"path":["last","seq"],"set":301},{"path":["time","lastActiveAt","ago"],"set":"刚刚"},{"path":["time","lastActiveAt","full"],"set":"10/6 09:00:00"}]]
  put_changes(asked, "message", messages)
}
