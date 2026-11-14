// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `agentCard` as `job`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"agentCard","station":"ws/maple","key":"k-maple-0"}
  let messages =
    #|[[{"path":["jobs"],"remove":true}]]
  put_changes(asked, "job", messages)
}
