// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `agentCard` as `step`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"agentCard","station":"ws/maple","key":"k-maple-0"}
  let messages =
    #|[[{"path":["context","text"],"set":"144.1K / 1M"},{"path":["latest",2,"key"],"set":"161"},{"path":["latest",2,"text"],"set":"运行"},{"path":["latest",2,"now"],"remove":true},{"path":["tokens"],"set":"输入 8.4M · 输出 211.6K"}]]
  put_changes(asked, "step", messages)
}
