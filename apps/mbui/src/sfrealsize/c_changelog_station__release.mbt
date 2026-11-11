// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `changelog station` as `release`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"changelog","part":"station","limit":30}
  let messages =
    #|[[{"path":["more"],"set":30},{"path":["tabs"],"key":["part"],"patch":"station","ops":[{"path":["days"],"key":["day"],"patch":20730,"ops":[{"path":["entries"],"key":["version"],"drop":8146}]},{"path":["days"],"key":["day"],"patch":20732,"ops":[{"path":["entries"],"key":["version"],"patch":8386,"ops":[{"path":["note"],"set":""}]},{"path":["entries"],"key":["version"],"patch":8392,"ops":[{"path":["note"],"set":""}]},{"path":["entries"],"key":["version"],"patch":8400,"ops":[{"path":["note"],"set":""}]},{"path":["entries"],"key":["version"],"put":{"version":8402,"versionName":"0.1.8402","lines":[{"kind":"improve","label":"改进","text":"命令面板字号调大以后文字不再被截断，按钮在窄屏上换行排列，长名字在中间省略"}],"note":""},"before":8400}]}]}]]
  put_changes(asked, "release", messages)
}
