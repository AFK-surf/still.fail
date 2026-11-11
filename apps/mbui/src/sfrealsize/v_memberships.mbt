// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `memberships` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"memberships","station":"ws/maple"}
  let value =
    #|{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"ws","name":"Acme","stationName":"Maple","home":true,"here":true,"line":"主 workspace"}]}
  put(asked, value)
}
