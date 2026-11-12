// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `changelog` as `release`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"changelog","limit":30}
  let messages =
    #|[[{"path":["tabs"],"key":["part"],"patch":"android","ops":[{"path":["days"],"key":["day"],"patch":20732,"ops":[{"path":["entries"],"key":["version"],"drop":8332},{"path":["entries"],"key":["version"],"patch":8394,"ops":[{"path":["note"],"set":"更新到 0.1.8394 后可用"}]},{"path":["entries"],"key":["version"],"patch":8396,"ops":[{"path":["note"],"set":"更新到 0.1.8396 后可用"}]},{"path":["entries"],"key":["version"],"patch":8398,"ops":[{"path":["note"],"set":"更新到 0.1.8398 后可用"}]},{"path":["entries"],"key":["version"],"put":{"version":8402,"versionName":"0.1.8402","lines":[{"kind":"improve","label":"改进","text":"命令面板字号调大以后文字不再被截断，按钮在窄屏上换行排列，长名字在中间省略"}],"has":false,"note":"更新到 0.1.8402 后可用"},"before":8398}]}]}]]
  put_changes(asked, "release", messages)
}
