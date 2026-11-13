// A group's rows by their keys (a workspace's people, a station's connects): what comes into it opens its room where it
// is, what goes from it closes where it was, in the middle of its room, cut at both ends with faded edges, grown as far as it is open and
// faded in from half open, as a chat's rows come and go (mbui's ListRows, mbui's view/list_motion.mbt; 2026-10-31
// the user: 「有一些是凭空出现的，有一些是凭空消失的」). The first time a group is drawn its rows are as they are.

///|
/// A group's rows as last drawn, each by its key (what draws it kept while it goes).
priv struct GroupRows {
  mut order : Array[(String, () -> Unit)]
}

///|
/// Each group's rows as last drawn, by the group's key.
// kept across runs: put back by group_rows_reset, as a run begins (run_begin)
let group_rows_of : Map[String, GroupRows] = Map([])

///|
/// What every group's rows were forgets (a run anew).
pub fn group_rows_reset() -> Unit {
  group_rows_of.clear()
}

///|
/// Group `key`'s rows, each by its key and what draws it (in a group's body: @sf.group): a row new to it comes where it
/// is, one gone goes where it was, its room opening and closing on a row's way (@ui.row_size_ms), what is in it in the
/// middle of its room. As they are the first time, and the first time again once it was not drawn (its page left, its
/// panel gone, another level of it shown), what changed meanwhile not one of its rows' coming or going.
pub fn group_rows(c : @ui.Ctx, key : String, rows : Array[(String, () -> Unit)]) -> Unit {
  ignore(c.on_unbuilt(c.id("\u{1}group-rows\u{1}" + key), fn() { group_rows_of.remove(key) }))
  let first = !group_rows_of.contains(key)
  let st = match group_rows_of.get(key) {
    Some(s) => s
    None => {
      let s = { order: [] }
      group_rows_of[key] = s
      s
    }
  }
  let here : Map[String, Bool] = Map([])
  for r in rows {
    here[r.0] = true
  }
  let was : Map[String, Bool] = Map([])
  for r in st.order {
    was[r.0] = true
  }
  // the rows now, with those gone among them where they were (after the row they came after), while they close
  let all : Array[(String, () -> Unit)] = rows.copy()
  let mut prev = ""
  for r in st.order {
    if !here.contains(r.0) {
      let at = match all.search_by(fn(a) { a.0 == prev }) {
        Some(i) => i + 1
        None => 0
      }
      all.insert(at, r)
    }
    prev = r.0
  }
  let kept : Array[(String, () -> Unit)] = []
  for r in all {
    let (k, draw) = r
    let shown = here.contains(k)
    let name = "group-rows/" + key + "/" + k
    let a = @motion.anim(c, name, if shown { 1.0 } else { 0.0 }, global=true)
    if shown && !was.contains(k) {
      a.snap(c, if first { 1.0 } else { 0.0 })
    }
    // (a share of its room: a Move as long as the room is tall, as what is under a post goes)
    a.follow(c, if shown { 1.0 } else { 0.0 }, @motion.moved().per_unit(@motion.reveal_height(c, name)))
    let share = a.get(c)
    if !shown && share <= 0.0 {
      continue
    }
    kept.push(r)
    @motion.reveal(c, name, share, middle=true, fn() {
      // (as big as its room is open, faded in from half: reveal's middle)
      let i = c.box(style=full_width, draw)
      @motion.leaving(c, i, shown)
    })
  }
  st.order = kept
}
