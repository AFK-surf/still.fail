// A page of the recent chats as chat_list reads it (station/src/read/recent-chat.ts `recentChatPage`): the station's,
// a workspace's, or the home workspace's (its default part and its own, joined), each from its prepared index, none
// while it is being prepared.

///|
let global_page : String = "SELECT thread FROM recent_chat_rows INDEXED BY recent_chat_order ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?"

///|
let workspace_page : String = "SELECT thread FROM recent_scope_rows INDEXED BY recent_scope_order WHERE ws = ?\n  ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?"

///|
let home_order_page : String = "SELECT thread, at, said_at, created_at FROM recent_home_rows INDEXED BY recent_home_order\n  ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?"

///|
let home_workspace_order_page : String = "SELECT thread, at, said_at, created_at FROM recent_scope_rows INDEXED BY recent_scope_order\n  WHERE ws = ? ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?"

///|
fn threads_of(rows : Array[Map[String, Json]]) -> Array[Json] {
  rows.map(r => get(r, "thread"))
}

///|
fn total_of(row : Map[String, Json]?) -> Double {
  match row {
    Some(r) =>
      match get(r, "total") {
        Number(n, ..) => n
        _ => 0.0
      }
    None => 0.0
  }
}

///|
fn number(row : Map[String, Json], name : String) -> Double {
  match get(row, name) {
    Number(n, ..) => n
    _ => 0.0
  }
}

///|
/// chat-list-home-overlap.ts `before`: whether `a` comes before `b` in the order (ties to the left).
fn before(a : Map[String, Json], b : Map[String, Json]) -> Bool {
  for name in ["at", "said_at", "created_at"] {
    let (x, y) = (number(a, name), number(b, name))
    if x != y {
      return x > y
    }
  }
  number(a, "thread") >= number(b, "thread")
}

///|
/// recent-chat.ts `recentChatPage`: the chats' ids, latest first, at most `limit`, and how many there are; none while
/// the index it reads is being prepared.
pub fn page(db : @sql.Db, ws : String?, home : String?, limit : Int) -> (Array[Json], Double)? raise {
  if limit == 0 {
    return Some(([], 0.0))
  }
  match ws {
    None =>
      snapshot(db, "recent_chat_page", () => {
        if !installed(db, "global") {
          return None
        }
        let meta = one(db, "SELECT total, complete FROM recent_chat_meta WHERE id = 1", [])
        if int(meta, "complete") != 1 || exists(db, "SELECT 1 FROM recent_chat_dirty LIMIT 1", []) {
          return None
        }
        Some((threads_of(db.all(global_page, [num(limit)])), total_of(Some(meta))))
      })
    Some(w) if Some(w) == home =>
      snapshot(db, "recent_home_union", () => {
        if !installed(db, "overlap") {
          return None
        }
        if int(one(db, "SELECT scan_done FROM recent_home_overlap_meta WHERE id = 1", []), "scan_done") != 1 ||
          exists(db, "SELECT 1 FROM recent_home_overlap_dirty LIMIT 1", []) {
          return None
        }
        if !default_home_ready(db) || !workspace_total_ready(db, w) {
          return None
        }
        let defaults = total_of(first(db, "SELECT total FROM recent_home_meta WHERE id = 1", []))
        let workspace = total_of(first(db, "SELECT total FROM recent_scope_tracked WHERE kind = 1 AND ws = ?", [text(w)]))
        let overlap = total_of(first(db, "SELECT total FROM recent_home_overlap_totals WHERE ws = ?", [text(w)]))
        let left = db.all(home_order_page, [num(limit)])
        let right = db.all(home_workspace_order_page, [text(w), num(limit)])
        let ids : Array[Json] = []
        let seen : Array[Json] = []
        let mut i = 0
        let mut j = 0
        while ids.length() < limit && (i < left.length() || j < right.length()) {
          let item = if j >= right.length() || (i < left.length() && before(left[i], right[j])) {
            i += 1
            left[i - 1]
          } else {
            j += 1
            right[j - 1]
          }
          let thread = get(item, "thread")
          if seen.contains(thread) {
            continue
          }
          seen.push(thread)
          ids.push(thread)
        }
        Some((ids, defaults + workspace - overlap))
      })
    Some(w) =>
      snapshot(db, "recent_scope_page", () => {
        if !workspace_total_ready(db, w) {
          return None
        }
        let total = total_of(first(db, "SELECT total FROM recent_scope_tracked WHERE kind = 1 AND ws = ?", [text(w)]))
        Some((threads_of(db.all(workspace_page, [text(w), num(limit)])), total))
      })
  }
}
