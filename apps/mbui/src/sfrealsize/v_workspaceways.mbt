// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `workspaceWays` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"workspaceWays","workspace":"ws"}
  let value =
    #|{"ways":[{"id":"https://relay.still.fail","kind":"relay","name":"relay.still.fail","own":false,"on":true},{"id":"https://relay-bj.still.fail","kind":"relay","name":"北京","own":false,"on":true},{"id":"https://relay-sg.still.fail","kind":"relay","name":"新加坡","own":false,"on":true},{"id":"https://relay.acme.dev","kind":"relay","name":"relay.acme.dev","own":true,"on":true},{"id":"lan","kind":"lan","name":"","own":false,"on":true},{"id":"tailnet","kind":"tailnet","name":"","own":false,"on":false},{"id":"direct","kind":"direct","name":"","own":false,"on":true}],"off":1,"offLabel":"已关闭 1 项"}
  put(asked, value)
}
