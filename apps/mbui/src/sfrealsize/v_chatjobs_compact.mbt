// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatJobs compact` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"chatJobs","station":"ws/maple","session":"k-maple-0","compact":true}
  let value =
    #|{"jobs":[{"id":"job-maple-0","session":"k-maple-0","name":"dev server","state":"running","port":5173,"command":"pnpm dev --host 127.0.0.1","restarts":0,"notices":[],"watch":false,"tone":"up","service":true,"open":true,"word":"在线","meta":[{"text":"在线","kind":"word"},{"text":" · 5 小时"}],"detail":"在线 · 5 小时","outputSaid":"最后输出 · 1 分钟前","age":"5 小时"},{"id":"job-maple-1","session":"k-maple-0","name":"watch CI #5244","state":"running","command":"gh run watch 11234567 --exit-status","restarts":0,"notices":[{"at":1791276000000,"text":"CI 绿了：check-mbui native 5 分 12 秒","ago":"20 分钟前","clock":"08:40"}],"watch":true,"tone":"live","service":false,"open":false,"word":"监控中","meta":[{"text":"CI 绿了：check-mbui native 5 分 12 秒","kind":"notice"},{"text":" · 20 分钟前"}],"detail":"监控中 · 10 小时 · 1 条通知","outputSaid":"最后输出 · 2 分钟前","age":"10 小时"}],"servicesNote":"1 个在线","jobsNote":"1 个运行中","allText":"全部 2 个"}
  put(asked, value)
}
