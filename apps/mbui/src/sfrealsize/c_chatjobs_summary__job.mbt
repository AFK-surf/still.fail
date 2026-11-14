// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatJobs summary` as `job`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"chatJobs","station":"ws/maple","session":"k-maple-0","compact":true,"summary":true}
  let messages =
    #|[[{"path":["alarm"],"set":"fail"}]]
  put_changes(asked, "job", messages)
}
