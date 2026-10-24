// A device not yet confirmed in the workspace's safe mode (its lock): whether it waits, and the lock's calls. The page
// it shows while it waits is sfpages' lock_wait.mbt.

///|
/// Whether this device waits to be confirmed in the workspace's lock (the lock's `me.waiting`).
pub fn lock_waiting(core : Core, ws : String) -> Bool {
  let lock = (core.topic)("lock", { "workspace": str(ws) }).value
  flag(field(lock, "me"), "waiting")
}

///|
/// `lock.<name>` on this workspace, let go on by itself and said how it ended (AppState.lockCall).
pub fn lock_call(
  core : Core,
  ws : String,
  name : String,
  what : String,
  params : Array[(String, String)],
  done? : String = "",
) -> Unit {
  let p : Array[(String, Json)] = [("workspace", str(ws))]
  for kv in params {
    p.push((kv.0, str(kv.1)))
  }
  act(core, what, "lock." + name, obj(p), done~)
}
