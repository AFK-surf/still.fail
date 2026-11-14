// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatJobs compact` as `job`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatJobs","station":"ws/maple","session":"k-maple-0","compact":true}
  let messages =
    #|[{"value":{"jobs":[{"id":"job-maple-0","session":"k-maple-0","name":"dev server","state":"failed","port":5173,"command":"pnpm dev --host 127.0.0.1","restarts":0,"notices":[],"watch":false,"tone":"fail","service":true,"open":false,"word":"启动失败","meta":[{"text":"启动失败","kind":"word"},{"text":" · 刚刚"}],"detail":"启动失败 · 刚刚","outputSaid":"最后输出 · 刚刚","age":"5 小时"}],"alarm":"fail","servicesNote":"","jobsNote":"","allText":"全部 1 个"}}]
  put_changes(asked, "job", messages)
}
