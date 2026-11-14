// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatJobs compact` as `minute`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatJobs","station":"ws/maple","session":"k-maple-0","compact":true}
  let messages =
    #|[[{"path":["jobs",0,"outputSaid"],"set":"最后输出 · 2 分钟前"},{"path":["jobs",1,"meta",1,"text"],"set":" · 21 分钟前"},{"path":["jobs",1,"notices",0,"ago"],"set":"21 分钟前"},{"path":["jobs",1,"outputSaid"],"set":"最后输出 · 3 分钟前"}]]
  put_changes(asked, "minute", messages)
}
