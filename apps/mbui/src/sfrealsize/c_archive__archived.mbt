// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `archive` as `archived`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"archive","scope":"ws","limit":60}
  let messages =
    #|[[{"path":["days"],"key":["label"],"patch":"9月27日","ops":[{"path":["items"],"key":["station","id"],"drop":["ws/cedar","a-cedar-14"]}]},{"path":["days"],"key":["label"],"put":{"label":"今天","items":[{"station":"ws/maple","id":"k-maple-5","session":"k-maple-5","thread":2005,"title":"用量页按模型拆分，加周对比","last":"需要你决定：按模型拆分时，同一个模型在不同 runtime 上（Claude Code 和 OpenRouter）要合并成一行还是分开显示？两种我都做了截图。","at":1791277200650,"clock":"09:00","how":"空闲后自动归档","deletable":false,"place":"Maple","stationEmoji":"🍁"}]},"before":"9月28日"},{"path":["total"],"set":241}]]
  put_changes(asked, "archived", messages)
}
