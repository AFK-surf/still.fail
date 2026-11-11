// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `jobLog 300` as `line`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"jobLog","station":"ws/maple","job":"job-maple-0","lines":300}
  let messages =
    #|[[{"path":["last"],"set":"2026-10-06T09:00:00.000Z ✔ src/views/views.test.ts › 整理新人 onboarding 文档 (300 ms, 20 assertions)"},{"path":["lines"],"key":["n"],"drop":0},{"path":["lines"],"key":["n"],"put":{"n":300,"runs":[{"text":"2026-10-06T09:00:00.000Z","dim":true},{"text":" "},{"text":"✔","fg":"2"},{"text":" src/views/views.test.ts › 整理新人 onboarding 文档 "},{"text":"(300 ms, 20 assertions)","dim":true}]},"before":null},{"path":["outputAt"],"set":1791277198900}]]
  put_changes(asked, "line", messages)
}
