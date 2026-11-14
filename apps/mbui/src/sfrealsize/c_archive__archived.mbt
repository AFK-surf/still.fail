// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `archive` as `archived`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"archive","scope":"ws","limit":60}
  let messages =
    #|[[{"path":["days"],"key":["label"],"patch":"9月27日","ops":[{"path":["items"],"key":["station","id"],"drop":["ws/cedar","a-cedar-14"]}]},{"path":["days"],"key":["label"],"put":{"label":"今天","items":[{"station":"ws/maple","id":"k-maple-2","session":"k-maple-2","thread":2002,"title":"Slack 连接断开后不会自动重连","last":"原因是 Socket Mode 的 ping 超时后我们只关了连接没有重新打开。改成按 backoff 重连（1s 起，最多 60s），本地断网 10 分钟再恢复，3 秒内连上。","at":1791277200650,"clock":"09:00","how":"空闲后自动归档","deletable":false,"place":"Maple","stationEmoji":"🍁"}]},"before":"9月28日"},{"path":["total"],"set":241}]]
  put_changes(asked, "archived", messages)
}
