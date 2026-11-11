// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `jobLog line` as `line`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"jobLog","station":"ws/maple","job":"job-maple-0","lines":1}
  let messages =
    #|[[{"path":["last"],"set":"2026-10-06T09:00:00.000Z ✔ src/station/scheduler.test.ts › 把 station 的日志轮转改成按天切 (37 ms, 13 assertions)"},{"path":["outputAt"],"set":1791277198900}]]
  put_changes(asked, "line", messages)
}
