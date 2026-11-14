// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `jobLog 400` as `line`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"jobLog","station":"ws/maple","job":"job-maple-0","lines":400}
  let messages =
    #|[[{"path":["last"],"set":"2026-10-06T09:00:00.000Z ✔ src/views/views.test.ts › Bump iroh to 0.95 and test the relays (400 ms, 0 assertions)"},{"path":["lines"],"key":["n"],"drop":0},{"path":["lines"],"key":["n"],"put":{"n":400,"runs":[{"text":"2026-10-06T09:00:00.000Z","dim":true},{"text":" "},{"text":"✔","fg":"2"},{"text":" src/views/views.test.ts › Bump iroh to 0.95 and test the relays "},{"text":"(400 ms, 0 assertions)","dim":true}]},"before":null},{"path":["outputAt"],"set":1791277198900}]]
  put_changes(asked, "line", messages)
}
