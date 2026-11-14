// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `fleet` as `usage`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"fleet","scope":"ws"}
  let messages =
    #|[[{"path":["spent",0,"models",3,"tokens"],"set":129253184},{"path":["spent",0,"share"],"set":0.6774859113268551},{"path":["spent",0,"tokens"],"set":526261376},{"path":["spent",1,"share"],"set":0.3225140886731449},{"path":["week","stats",2,"value"],"set":"$7,965"}]]
  put_changes(asked, "usage", messages)
}
