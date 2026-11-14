// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `history` as `step`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"history","station":"ws/maple","key":"k-maple-0"}
  let messages =
    #|[[{"path":["items"],"key":["key"],"patch":"e158","ops":[{"path":["body","content","pending"],"set":1},{"path":["body","content","rows"],"append":[{"kind":"step","content":{"name":"Bash","hint":"pnpm exec tsgo --noEmit && node --test test/topic-bytes.test.ts","meta":"进行中","failed":false,"call":"pnpm exec tsgo --noEmit && node --test test/topic-bytes.test.ts","entries":[161],"brief":false}}]},{"path":["body","content","summary"],"set":"运行 · 共 2 项"},{"path":["body","content","title"],"set":"搜索 1 次、运行 1 条命令"},{"path":["entries",1],"set":161}]},{"path":["items"],"key":["key"],"patch":"e157","ops":[{"path":["turn","text"],"set":"2 步 · 未发消息"}]},{"path":["live"],"set":[]},{"path":["usage",0,"value"],"set":"413 次"},{"path":["usage",3,"value"],"set":"211.6K"},{"path":["usage",5,"value"],"set":"144.1K / 1M（14%）"},{"path":["usageLine"],"set":"调用 413 次 · 输入 8.4M（缓存 94%） · 输出 211.6K · 上下文 144.1K · 约 $31.42"}]]
  put_changes(asked, "step", messages)
}
