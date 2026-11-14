// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chat` as `job`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chat","station":"ws/maple","session":"k-maple-0"}
  let messages =
    #|[[{"path":["agents",0,"jobs",0,"detail"],"set":"启动失败 · 刚刚"},{"path":["agents",0,"jobs",0,"meta",0,"text"],"set":"启动失败"},{"path":["agents",0,"jobs",0,"meta",1,"text"],"set":" · 刚刚"},{"path":["agents",0,"jobs",0,"open"],"set":false},{"path":["agents",0,"jobs",0,"outputSaid"],"set":"最后输出 · 刚刚"},{"path":["agents",0,"jobs",0,"state"],"set":"failed"},{"path":["agents",0,"jobs",0,"tone"],"set":"fail"},{"path":["agents",0,"jobs",0,"word"],"set":"启动失败"},{"path":["agents",0,"jobs",1,"detail"],"set":"意外退出 · 刚刚 · 2 条通知"},{"path":["agents",0,"jobs",1,"meta"],"set":[{"text":"意外退出","kind":"word"},{"text":" · 退出码 1"},{"text":" · 刚刚"}]},{"path":["agents",0,"jobs",1,"notices"],"append":[{"at":1791277200650,"text":"CI 失败：check-mbui native，2 个测试没过","ago":"刚刚","clock":"09:00"}]},{"path":["agents",0,"jobs",1,"outputSaid"],"set":"最后输出 · 刚刚"},{"path":["agents",0,"jobs",1,"state"],"set":"exited"},{"path":["agents",0,"jobs",1,"tone"],"set":"fail"},{"path":["agents",0,"jobs",1,"word"],"set":"意外退出"}]]
  put_changes(asked, "job", messages)
}
