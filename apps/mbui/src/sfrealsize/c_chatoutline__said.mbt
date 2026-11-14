// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatOutline` as `said`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatOutline","station":"ws/maple","thread":2002}
  let messages =
    #|[[{"path":["count"],"set":534},{"path":["days"],"key":["date"],"patch":"2026-10-06","ops":[{"path":["seqs"],"append":[1602]}]},{"path":["held"],"set":1601},{"path":["of"],"set":1602},{"path":["whole"],"set":false}]]
  put_changes(asked, "said", messages)
}
