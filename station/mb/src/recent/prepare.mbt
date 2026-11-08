// A requested scope's recent chats prepared one bounded piece at a time (station/src/store/chat-list-prepare.ts
// `RecentChatPreparation`), here for the MoonBit builder: the station-wide order (no workspace), a named workspace,
// or home (the workspace that is also the viewer's home: its default part and their overlap too).

///|
/// A piece of work of a scope: whether it has some, and one batch of it.
priv struct Lane {
  pending : () -> Bool raise
  step : () -> Int raise
}

///|
pub struct Preparation {
  priv db : @sql.Db
  priv limit : Int
  priv turns : Map[String, Int]
  priv mut global_installed : Bool
  priv mut scope_installed : Bool
  priv mut home_installed : Bool
  priv tracked : Map[String, Bool]
}

///|
pub fn Preparation::new(db : @sql.Db, limit~ : Int = 64) -> Preparation raise {
  guard limit >= 1 else {
    fail("recent chat preparation batch must be positive")
  }
  {
    db,
    limit,
    turns: Map([]),
    global_installed: false,
    scope_installed: false,
    home_installed: false,
    tracked: Map([]),
  }
}

///|
/// One batch of the scope (`ws` none: the station's order; `home`: the viewer's home); whether it is ready then. A
/// scope's lanes take turns, each scope its own, so a busy scope cannot keep another's home work waiting.
pub fn Preparation::step(
  self : Preparation,
  ws : String?,
  home : String?,
) -> Bool raise {
  let db = self.db
  let limit = self.limit
  guard ws is Some(ws) else {
    if !self.global_installed {
      install_global(db)
      self.global_installed = true
    }
    if global_ready(db) {
      return true
    }
    return global_step(db, limit)
  }
  if !self.scope_installed {
    install_scope(db)
    self.scope_installed = true
  }
  if !self.tracked.contains(ws) {
    track(db, 1, ws)
    self.tracked[ws] = true
  }
  let is_home = home == Some(ws)
  if is_home && !self.home_installed {
    install_home(db)
    install_overlap(db)
    self.home_installed = true
  }
  let ready = () => {
    if is_home {
      home_ready(db, ws)
    } else {
      workspace_ready(db, ws)
    }
  }
  if ready() {
    return true
  }
  let w = [text(ws)]
  let scope = one(
    db, "SELECT scan_done, scan_session, complete FROM recent_scope_tracked WHERE kind = 1 AND ws = ?",
    w,
  )
  let scanned = int(scope, "scan_done") == 1 &&
    get(scope, "scan_session") is Null
  let any = (sql : String) => exists(db, sql, [])
  let scoped = (sql : String) => exists(db, sql, w)
  let lanes : Array[Lane] = [
    { pending: () => !scanned, step: () => scan_workspace(db, ws, limit), },
    {
      pending: () => scanned && int(scope, "complete") != 1,
      step: () => {
        ignore(
          db.run(
            "UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = ? AND scan_done = 1 AND scan_session IS NULL",
            w,
          ),
        )
        0
      },
    },
    {
      pending: () => {
        scanned &&
        scoped(
          "SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? LIMIT 1",
        )
      },
      step: () => settle_workspace_session(db, ws, limit),
    },
    {
      pending: () => {
        scanned &&
        scoped("SELECT 1 FROM recent_scope_member_dirty WHERE ws = ? LIMIT 1")
      },
      step: () => settle_workspace_members(db, ws, limit),
    },
    {
      pending: () => {
        scoped("SELECT 1 FROM recent_scope_order_dirty WHERE ws = ? LIMIT 1")
      },
      step: () => settle_workspace_order(db, ws, limit),
    },
    {
      pending: () => any("SELECT 1 FROM recent_scope_visibility_dirty LIMIT 1"),
      step: () => settle_visibility(db, limit),
    },
    {
      pending: () => any("SELECT 1 FROM recent_scope_order_dispatch LIMIT 1"),
      step: () => dispatch_order(db, limit),
    },
  ]
  if is_home {
    lanes.push({
      pending: () => {
        any("SELECT 1 FROM recent_home_meta WHERE id = 1 AND scan_done = 0")
      },
      step: () => {
        scan_into(
          db, "recent_home_meta", "threads", "id", "recent_home_dirty", limit,
        )
      },
    })
    lanes.push({
      pending: () => {
        any(
          "SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' LIMIT 1",
        )
      },
      step: () => settle_home_session(db, limit),
    })
    lanes.push({
      pending: () => any("SELECT 1 FROM recent_home_dirty LIMIT 1"),
      step: () => settle_home_chats(db, limit),
    })
    lanes.push({
      pending: () => any("SELECT 1 FROM recent_home_order_dirty LIMIT 1"),
      step: () => settle_home_order(db, limit),
    })
    lanes.push({
      pending: () => {
        any(
          "SELECT 1 FROM recent_home_overlap_meta WHERE id = 1 AND scan_done = 0",
        )
      },
      step: () => {
        scan_into(
          db, "recent_home_overlap_meta", "recent_home_rows", "thread", "recent_home_overlap_dirty",
          limit,
        )
      },
    })
    lanes.push({
      pending: () => any("SELECT 1 FROM recent_home_overlap_dirty LIMIT 1"),
      step: () => settle_overlap(db, limit),
    })
  }
  let key = (if is_home { "h:" } else { "w:" }) + ws
  let turn = self.turns.get(key).unwrap_or(0)
  for n in 0..<lanes.length() {
    let at = (turn + n) % lanes.length()
    let lane = lanes[at]
    if !(lane.pending)() {
      continue
    }
    self.turns[key] = (at + 1) % lanes.length()
    ignore((lane.step)())
    return false
  }
  // (another connection can have completed the work after the readiness check)
  if ready() {
    return true
  }
  fail("recent chat preparation has no runnable work")
}
