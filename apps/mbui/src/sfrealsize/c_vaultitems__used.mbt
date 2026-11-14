// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `vaultItems` as `used`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"vaultItems","workspace":"ws","vault":"plain"}
  let messages =
    #|[[{"path":["items"],"key":["id"],"patch":"item-0","ops":[{"path":["lastUse","command"],"set":"gh pr merge 5244 --squash"},{"path":["lastUse","hosts"],"append":["api.github.com","github.com","uploads.github.com"]},{"path":["lastUse","howText"],"set":"gh pr merge 5244 --squash · 代理"},{"path":["lastUse","mode"],"set":"proxy"}]}]]
  put_changes(asked, "used", messages)
}
