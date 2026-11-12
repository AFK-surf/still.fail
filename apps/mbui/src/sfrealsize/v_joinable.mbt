// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `joinable` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"joinable","workspace":"ws"}
  let value =
    #|{"offered":true,"loading":false,"items":[{"station":"ws-labs/lab-1","id":"lab-1","name":"Lab GPU","workspace":"ws-labs","workspaceName":"Acme Labs","online":true,"line":"Acme Labs · 在线","needsLock":false},{"station":"ws-labs/lab-2","id":"lab-2","name":"Lab Mini","workspace":"ws-labs","workspaceName":"Acme Labs","online":true,"line":"Acme Labs · 在线","needsLock":false}]}
  put(asked, value)
}
