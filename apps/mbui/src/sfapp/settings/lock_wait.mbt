// A device not yet confirmed in the workspace's safe mode (its lock): whether it waits, and the lock's calls. The page
// it shows while it waits is sfpages' lock_wait.mbt.

///|
/// Whether this device waits to be let in to the workspace's lock: to be confirmed (the lock's `me.waiting`), or, a web
/// page nobody can approve there, for its person's first app to approve it (`me.needsAppText`): either way the
/// workspace's place is the waiting page (sfpages' lock_wait.mbt), which says which.
pub fn lock_waiting(core : Core, ws : String) -> Bool {
  let me = field((core.topic)("lock", { "workspace": str(ws) }).get().value, "me")
  flag(me, "waiting") || text(me, "needsAppText") != ""
}

///|
/// What a web page nobody can approve in the workspace's lock says, the core's words (the lock's `me.needsAppText`):
/// "" where it is not one.
pub fn lock_needs_app(core : Core, ws : String) -> String {
  text(field((core.topic)("lock", { "workspace": str(ws) }).get().value, "me"), "needsAppText")
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
