// A column that scrolls (View::scrolls) holding blocks by their keys, each made only while it shows (retained.md's
// lists; as an old view's list builds only the rows in view, ui's Ctx::list): laid out in the column's own layout from
// where it is scrolled to, as a list from its anchor is (View::scrolls_anchored, retained.md rule 11), each block made
// and measured as that layout comes to it, in that same layout, till what shows is filled; one never laid out counted
// as `est` (its height kept by its key as wide as the column was as it was laid out). A block a scroll goes past is
// made too, only to be measured, and let go in the same layout (so it stops where many smaller scrolls would): what a
// block's make does is make its nodes and read what they show, never start what lasts (retained.md: what a layout
// makes is a cache of the picture); what a page keeps for a block it starts as the block is told seen. Nothing a block
// measures is told back to lay the column out again. As what
// is over what shows changes height (a block laid out again taller than it was counted, one come or gone over it), what
// shows stays where it is: the column is where its anchor is. ui's ListRows::in_node alone is laid out the way before
// it still, its blocks' heights told back (View::scrolls_window_rooms).

///|
/// A block's room in a windowed list, apart from its natural measured height: its height now and where its content
/// lies inside it. A changing room may cut its content softly and scale/fade it, without changing what is measured.
pub(all) struct ListRoom {
  height : Double
  offset : Double
  clip : Bool
  soft : Bool
  scale : Double
  alpha : Double
  presses : Bool
} derive(Eq)

///|
/// A block shown at its natural height, without a transition of its room.
pub fn list_room(height : Double) -> ListRoom {
  { height, offset: 0.0, clip: false, soft: false, scale: 1.0, alpha: 1.0, presses: true }
}

///|
let windowed_room : Lent[() -> ListRoom] = Lent::new()

///|
/// The room allocated to the enclosing windowed block in this frame. Something carried into that block can use
/// its opening displacement directly, rather than easing a second time toward its already moving content.
pub fn View::list_room(self : View) -> ListRoom? {
  self.lent(windowed_room).map(fn(f) { f() })
}

///|
/// A page's list (`s`: Scroll::list) scrolling up and down in it (View::scrolls, `slop` and `bar` as there) holding the
/// blocks `keys` names, in their order, one under another from its top, nothing else: each made by `make` in a node of
/// its own as it comes to show (its room, from the column's top to its foot, met by any of it), let go as it no more
/// does, as tall in the column meanwhile as it was last laid out (`est` where it never was); one a scroll goes past made
/// too, only to be measured, and let go in the same layout. So `make` makes a block's nodes and reads what they show,
/// and starts nothing outside them (a draft, a call to the core, anything said): what is kept for a block is started
/// as `seen` tells it came in sight, told once the frame is painted: in sight as it was laid out (at an input's moment
/// or a frame's), or gone across as it went on by itself (a fling, a wheel's notches easing in), whether the frames
/// between were many or one; never one gone past as it was moved at once (a wheel's turn, a drag's move, its bar,
/// put) nor as it was first laid out where it was scrolled to. How tall each that does not show was is forgotten as the
/// column is laid out at another width or all words are measured anew.
/// `from_end` (a chat's, an old view's list's `from_end` and `stick_end`): shorter than the column, its blocks at its
/// foot; first shown at its end; at its end, kept there as what it holds grows or what shows is laid out taller,
/// no longer once it is scrolled from there, again once it is back. `follows` says, followed, whether it is kept at its
/// end so. `shown` is told the keys of the blocks in sight, in order, as they change (what is read, how far from its
/// end). `put`, said, puts it at once where that block's top is that far under its top (it follows its end no more),
/// and is said none again. A block come at its end while it follows that `fresh` says is new to it is glided after, not
/// there at once; one come that is taller than what shows under `cover` (what lies over its top: a bar) is glided to
/// only as far as its top under that, read from its top (Follow.kt), and it follows its end no more. `read_from_top`
/// may say false for a block whose end should stay in view even when tall, such as the reader's own message.
/// `rooms`: the blocks' rooms as they are now (read before the column is laid out: a block's room by its key and the
/// height it measured in that layout), where heights themselves follow a shared motion; the list follows those rooms
/// directly, without another glide over their motion. `kept_keys`: blocks needed outside the visible window too, such
/// as a send's landing while the list glides towards it, laid out in their own slots, still cut by the list, not among
/// those `shown` reports in sight. `bar_clear`: the scroll bar's ends kept clear; `foot_room`: room under the last
/// block, laid out even while the last block is off screen. Where its host sets a page's list's rows on its pixels
/// (Tree::set_rows_grid), each block's room is as tall as whole pixels.
pub fn[K : Hash + Eq] View::scrolls_window(
  self : View,
  s : Scroll,
  keys : () -> Array[K],
  make : (View, K) -> Unit,
  est? : Double = 80.0,
  slop? : Double,
  bar? : ScrollBar,
  from_end? : Bool = false,
  follows? : @signals.Signal[Bool] = @signals.signal(true, same=fn(a, b) { a == b }),
  shown? : @signals.Signal[Array[K]],
  put? : @signals.Signal[(K, Double)?],
  fresh? : (K) -> Bool = fn(_) { false },
  read_from_top? : (K) -> Bool = fn(_) { true },
  cover? : () -> Double = fn() { 0.0 },
  rooms? : () -> (K, Double) -> ListRoom,
  kept_keys? : () -> Array[K],
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
  seen? : (Array[K]) -> Unit,
) -> View {
  // (only what shows: nothing made ahead of it; each never laid out counted as `est`, not as the mean of those laid out)
  self.scrolls_anchored_impl(
    s, keys, make, est~, from_end~, ahead=0.0, slop?=slop, bar?=bar, follows~, shown?=shown, put?=put, rooms?=rooms,
    fresh~, read_from_top~, cover~, kept_keys?=kept_keys, bar_clear~, foot_room~, fixed_estimate=true, on_grid=true,
    seen?=seen,
  )
}

///|
/// The same list laid out the way before it, its blocks' heights told back as each is laid out and the column laid out
/// again by them, where its blocks' rooms follow a shared motion read as each is worked out (`room`, as ui's
/// ListRows::in_node gives it; `moving`, the keys whose rooms move): ListRows::in_node's lists alone, no page's, till
/// those rooms are read before the layout as View::scrolls_window's `rooms` are. As it was:
/// A page's list (`s`: Scroll::list, what it holds above moved with it as it grows: Scroll::grew_above) scrolling up and
/// down in it (View::scrolls, `slop` and `bar` as there) holding the
/// blocks `keys` names, in their order, one under another from its top, nothing else: each made by `make` in a node of
/// its own as it comes to show (its room, from the column's top to its foot, met by any of it), let go as it no more
/// does, as tall in the column meanwhile as it was last laid out (`est` where it never was). How tall each that does
/// not show was is forgotten as the column is laid out at another width or all words are measured anew (what shows is
/// laid out again as it is, its height told anew).
/// `from_end` (a chat's, an old view's list's `from_end` and `stick_end`): shorter than the column, its blocks at its
/// foot; first shown at its end; at its end, kept there as what it holds grows or what shows is laid out taller (at
/// once, nothing glided after: an old view's list's `glide_on_growth` off), no longer once it is scrolled from there,
/// again once it is back. `follows` says, followed, whether it is kept at its end so. `shown` is told the keys of the
/// blocks in sight, in order, as they change (what is read, how far from its end). `put`, said, puts it at once where
/// that block's top is that far under its top, as the blocks over it are counted (it follows its end no more), and
/// is said none again. A block come at its end while it follows that `fresh` says is new to it (said while it
/// shows, not caught up on) is glided after, not there at once; one come that is taller than what shows under `cover`
/// (what lies over its top: a bar) is glided to only as far as its top under that, read from its top (Follow.kt), and
/// it follows its end no more. `read_from_top` may say false for a block whose end should stay in view even when
/// tall, such as the reader's own message. Shorter than the column, what was at its foot goes up as blocks come at its end (and
/// as their heights are told) while it follows, glided from where it was drawn; not as the column is laid out shorter.
/// `room`: a block's room as its measured height changes, where heights themselves follow a shared motion. The
/// list follows those rooms directly, without another glide over their motion; natural heights remain cached.
/// `kept`: a block needed outside the visible window too, such as a send's landing while the list glides towards it.
/// It is laid out in its own slot, still cut by the list, and does not change which rows `shown` reports in sight.
/// `bar_clear`: the scroll bar's ends kept clear; `foot_room`: room under the last block, laid out even while the last block is off screen.
pub fn[K : Hash + Eq] View::scrolls_window_rooms(
  self : View,
  s : Scroll,
  keys : () -> Array[K],
  make : (View, K) -> Unit,
  est? : Double = 80.0,
  slop? : Double,
  bar? : ScrollBar,
  from_end? : Bool = false,
  follows? : @signals.Signal[Bool] = @signals.signal(true, same=fn(a, b) { a == b }),
  shown? : @signals.Signal[Array[K]],
  put? : @signals.Signal[(K, Double)?],
  fresh? : (K) -> Bool = fn(_) { false },
  read_from_top? : (K) -> Bool = fn(_) { true },
  cover? : () -> Double = fn() { 0.0 },
  room? : (K, Double) -> ListRoom,
  kept? : (K) -> Bool,
  moving? : () -> Array[K],
  kept_keys? : () -> Array[K],
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
) -> View {
  guard self.live() is Some(_) else { return self }
  let put_at = put.unwrap_or(@signals.signal(None))
  let measuring_anchor = Ref(false)
  let release_put : Ref[() -> Unit] = Ref(fn() { })
  // Stop following in the input's cause, before measuring what that input reveals. The new heights may offset
  // the scroll by more than the hand moved it, so that direction cannot be recovered from layout coordinates.
  s.on_hand = fn(d) {
    measuring_anchor.val = false
    (release_put.val)()
    if from_end && d < 0.0 { follows.set(false) }
  }
  self.owns(fn() { s.on_hand = fn(_) { } }) |> ignore
  // (how tall each was laid out while it showed, by its key, told as each is laid out (`told` counting each change of
  // it); forgotten as the column is laid out at another width, or as all words are measured anew (the system's size of
  // words, how the theme shapes them: Tree::words_again))
  let heights : Map[K, Double] = Map([])
  let told : @signals.Signal[Int] = @signals.signal(0)
  let tell = fn() { told.set(@signals.untracked(fn() { told.get() }) + 1) }
  // (the blocks whose heights were told since `laid` was last worked out, and whether any were forgotten: what is laid
  // out again of them alone, the rest as they were)
  let told_keys : Map[K, Bool] = Map([])
  let forgot = Ref(false)
  // (those that show now: laid out again as they are, each told anew where it comes out otherwise; the rest forgotten)
  let showing : Map[K, Bool] = Map([])
  let slots : Map[K, View] = Map([])
  // (what each block's row is known by, whatever slot it is made in: View::row_known_as; forgotten as its key goes, a
  // block of the same key come again another row, nothing picked in the one before found in it)
  let row_ids : Map[K, NodeId] = Map([])
  self.reacts(keys, fn(now) {
    let here : Map[K, Bool] = {}
    for k in now {
      here[k] = true
    }
    for k in row_ids.keys().collect() {
      if !here.contains(k) {
        row_ids.remove(k)
      }
    }
  })
  self.reacts(fn() { (self.laid_size_told().map(fn(z) { z.0 }), self.words_redone()) }, fn(_) {
    let gone = heights.keys().filter(fn(k) { !showing.contains(k) }).collect()
    if gone.length() > 0 {
      for k in gone {
        heights.remove(k)
      }
      forgot.val = true
      tell()
    }
  })
  // (each block's top in the column and its height, in order: as tall as it was laid out, else est)
  // (worked out anew for every block only as the blocks themselves change, as heights are forgotten, as the host's
  // pixels change; else for those whose heights were told and those on their way (`moving`, where a room is said:
  // what was and what is), the rest as they were, the tops summed again: a long chat's three thousand rooms each asked
  // for again as one row was measured or moved, 2026-11-04)
  let laid_keys : Ref[Array[K]?] = Ref(None)
  let laid_index : Ref[Map[K, Int]] = Ref(Map([]))
  let laid_moving : Ref[Array[K]] = Ref([])
  let laid_grid = Ref(-1.0)
  // (how many times `laid` was worked out: what follows it as it changes, nothing compared of it)
  let laid_made = Ref(0)
  // (how many of them were never laid out, as `laid` was last worked out)
  let laid_unknown = Ref(0)
  let block = fn(k : K) -> (K, Double, Double, Bool, ListRoom) {
    let (h, known) = match heights.get(k) {
      Some(h) => (h, true)
      None => (est, false)
    }
    // (as tall as it is laid out in the column: on its host's pixels where it sets a page's list's rows on them,
    // Tree::rows_slot)
    let r = match room {
      Some(f) => f(k, h)
      None => list_room(h)
    }
    (k, 0.0, self.tree.rows_slot(dmax(0.0, r.height)), known, r)
  }
  let laid = @signals.computed(fn(was : Array[(K, Double, Double, Bool, ListRoom)]?) {
    told.get() |> ignore
    let all_keys = keys()
    let now_moving = match moving {
      Some(f) => f()
      None => []
    }
    let grid = self.tree.rows_grid_said.get()
    let anew = forgot.val || grid != laid_grid.val || (room is Some(_) && moving is None) ||
      (match laid_keys.val {
        Some(a) => !physical_equal(a, all_keys)
        None => true
      }) ||
      (match was {
        Some(w) => w.length() != all_keys.length()
        None => true
      })
    forgot.val = false
    laid_grid.val = grid
    let out = if anew {
      let index : Map[K, Int] = Map([])
      let out = all_keys.mapi(fn(i, k) {
        index[k] = i
        block(k)
      })
      laid_keys.val = Some(all_keys)
      laid_index.val = index
      out
    } else {
      let out = was.unwrap().copy()
      let again = fn(k : K) {
        match laid_index.val.get(k) {
          Some(i) => out[i] = block(k)
          None => ()
        }
      }
      for k, _ in told_keys {
        again(k)
      }
      for k in laid_moving.val {
        again(k)
      }
      for k in now_moving {
        again(k)
      }
      out
    }
    told_keys.clear()
    laid_moving.val = now_moving
    let mut top = 0.0
    for i in 0..<out.length() {
      let (k, _, h, known, r) = out[i]
      out[i] = (k, top, h, known, r)
      top = top + h
    }
    laid_made.val = laid_made.val + 1
    laid_unknown.val = out.iter().filter(fn(b) { !b.3 }).count()
    out
  })
  // (the first block whose foot is at `x` or under it, by halving: the blocks in order down the column, none shorter
  // than nothing; how many there are where there is none)
  let first_from = fn(all : Array[(K, Double, Double, Bool, ListRoom)], x : Double) -> Int {
    let mut lo = 0
    let mut hi = all.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if all[mid].1 + all[mid].2 < x {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    lo
  }
  // (where it is scrolled to, as what it holds is drawn now)
  let at = fn() { s.drawn(self.tree) }
  // (those that show: their room met by the column's, as tall as it shows, from the first down to one not laid out yet;
  // none before it is first laid out)
  let window = @signals.computed(fn(_) {
    guard self.laid_size_told() is Some((_, vh)) else { return [] }
    let x = at()
    let out = []
    let all = laid.get()
    for i in first_from(all, x)..<all.length() {
      let b = all[i]
      if b.1 >= x + vh && !(room is Some(_) && b.2 == 0.0 && b.1 == x + vh) {
        break
      }
      if b.1 + b.2 > x || (room is Some(_) && b.2 == 0.0 && b.1 >= x) {
        out.push(b.0)
        // (one never laid out shows as it is laid out, those under it only once it is: where they start is known then,
        // nothing made that turns out to be past the foot, as an old view's list lays a row and then the next)
        if !b.3 {
          break
        }
      }
    }
    out
  })
  // (what the column holds: a slot for each block in sight or kept, in their order, and between them, over the first and
  // under the last, a gap as tall as the blocks there are counted. Not a slot for every block: a long chat's three
  // thousand were gone through in drawing order and placed in every frame, at rest too (each_drawn_in_order,
  // laid_origin: a native sample's most), 3.2 ms a frame on wasm-gc against 0.4 for a short chat's, 2026-11-04; nor one
  // for each between a kept block far from those in sight and them)
  let made = @signals.computed(fn(_) {
    let all = laid.get()
    // (every block whose room meets the column's as it is counted (those that show among them, and those under one not
    // laid out yet: their slots kept as that one is laid out, not let go for a frame and made again), and those kept)
    let room_now = self.laid_size_told().map(fn(z) { z.1 })
    let x = at()
    let with_slot : Map[Int, Bool] = Map([])
    match room_now {
      Some(vh) =>
        for i in first_from(all, x)..<all.length() {
          let b = all[i]
          if b.1 > x + vh {
            break
          }
          if (b.1 < x + vh && b.1 + b.2 > x) || (room is Some(_) && b.2 == 0.0 && b.1 >= x && b.1 <= x + vh) {
            with_slot[i] = true
          }
        }
      None => ()
    }
    match kept_keys {
      Some(f) =>
        for k in f() {
          match laid_index.val.get(k) {
            Some(i) if i < all.length() => with_slot[i] = true
            _ => ()
          }
        }
      // (asked of each block only where it is told what is kept so: none kept by a list told neither, and its blocks not
      // gone through as it scrolls, the home's thousands of chats every frame they are counted anew)
      None =>
        match kept {
          Some(kept) =>
            for i, b in all {
              if kept(b.0) {
                with_slot[i] = true
              }
            }
          None => ()
        }
    }
    let ix = with_slot.keys().collect()
    ix.sort()
    let out : Array[Made[K]] = []
    let mut last = -1
    for i in ix {
      if i > last + 1 {
        out.push(Gap(last, i))
      }
      out.push(Slot(all[i].0, i))
      last = i
    }
    if last + 1 < all.length() {
      out.push(Gap(last, all.length()))
    }
    out
  }, same=fn(a, b) { a == b })
  // (a gap's height: from the bottom of the block before it, or the column's top, to the top of the one after, or the end)
  let gap_height = fn(from : Int, to : Int) -> Double {
    let all = laid.get()
    let top = if from < 0 { 0.0 } else { all.get(from).map(fn(b) { b.1 + b.2 }).unwrap_or(0.0) }
    let end = match all.get(to) {
      Some(b) => b.1
      None => all.last().map(fn(b) { b.1 + b.2 }).unwrap_or(0.0)
    }
    dmax(0.0, end - top)
  }
  // (its blocks in sight by their places, it put at one, and how far past the first in sight's top it is: what a test
  // reads and asks, Tree::list_rows)
  s.rows = Some((
    fn() {
      let all = keys()
      let w = window.get()
      laid.get() |> ignore
      let at_key = fn(k : K) {
        match laid_index.val.get(k) {
          Some(i) if i < all.length() && all[i] == k => i
          _ => all.search(k).unwrap_or(-1)
        }
      }
      match (w.get(0), w.last()) {
        (Some(a), Some(b)) => (at_key(a), at_key(b))
        _ => (-1, -1)
      }
    },
    fn(i) {
      match laid.get().get(i) {
        Some(b) => {
          // A requested row owns the new position through its first full measurement, just as a saved position
          // does. Keeping the previous reading anchor here would move the request away as the row grows.
          put_at.set(Some((b.0, 0.0)))
        }
        None => ()
      }
    },
    fn() {
      let x = at()
      let all = laid.get()
      let mut i = first_from(all, x)
      while i < all.length() && all[i].1 + all[i].2 <= x {
        i = i + 1
      }
      if i < all.length() { x - all[i].1 } else { 0.0 }
    },
    fn(i) {
      keys().get(i).bind(fn(k) {
        if showing.contains(k) { slots.get(k).map(fn(v) { v.rect() }) } else { None }
      })
    },
  ))
  self.owns(fn() { s.rows = None }) |> ignore
  match shown {
    Some(sh) => self.reacts(fn() { window.get() }, fn(w) { sh.set(w) })
    None => ()
  }
  // (put at a block and held there: it follows no end meanwhile, whatever it is clamped to as it is laid out)
  let anchor : Ref[(K, Double)?] = Ref(None)
  let putting = Ref(false)
  let p = put_at
  // (held there as the blocks over it and it are laid out, counted as they come to be, till all that shows is laid
  // out as it is)
  let held : Ref[(K, Double, Double)?] = Ref(None)
  release_put.val = fn() { held.val = None; putting.val = false }
  let hold = fn(all : Array[(K, Double, Double, Bool, ListRoom)]) {
    match held.val {
      Some((k, offset, _)) =>
        match (match laid_index.val.get(k) {
          Some(j) if j < all.length() && all[j].0 == k => Some(j)
          _ => all.search_by(fn(b) { b.0 == k })
        }) {
          Some(i) => {
            // (the block itself in sight first, laid out as it is, where it is not yet: how far into it it is put
            // is of its own height)
            // A first measurement may include only a row's heading, with its hosted content still to be
            // measured. Keep part of that row in sight until the saved point fits inside it; otherwise the
            // row would be let go before its island can report the rest of its height.
            let past = if offset < 0.0 { dmin(-offset, dmax(0.0, all[i].2 - 0.5)) } else { -offset }
            let to = if all[i].3 { all[i].1 + past } else { all[i].1 }
            let to = if to < 0.0 { 0.0 } else { to }
            // The requested row remains the reading anchor while what is above it finishes measuring,
            // including a hosted view's later measurement. A provisional row above it cannot take over.
            anchor.val = Some((k, all[i].1))
            measuring_anchor.val = true
            s.x.set(to)
            // (let go once what shows is all laid out as it is: the blocks over it as counted no more matter)
            let in_sight = @signals.untracked(fn() { window.get() })
            let known = in_sight.iter().all(fn(w) {
              match laid_index.val.get(w) {
                Some(j) if j < all.length() && all[j].0 == w => all[j].3
                _ => all.iter().any(fn(b) { b.0 == w && b.3 })
              }
            })
            // (and once it can go there: not while how far it can go, as counted so far, falls short of it, unless all of it
            // is laid out as it is)
            let reached = to <= @signals.untracked(fn() { s.most_now() }) + 0.5 || laid_unknown.val == 0
            let inside = offset >= 0.0 || -offset < all[i].2
            held.val = if all[i].3 && inside && known && reached && in_sight.length() > 0 { None } else { Some((k, offset, to)) }
            putting.val = held.val is Some(_)
          }
          None => ()
        }
      None => ()
    }
  }
  self.reacts(fn() { p.get() }, fn(now) {
    match now {
      Some((k, offset)) => {
        follows.set(false)
        putting.val = true
        held.val = Some((k, offset, @signals.untracked(fn() { s.x.get() })))
        hold(@signals.untracked(fn() { laid.get() }))
        p.set(None)
      }
      None => ()
    }
  })
  // (as the blocks are counted anew, and as how far it can go comes to be told: it may go there only then)
  // (`laid` followed by how many times it was worked out, not compared block by block: it is said again only as it is)
  self.reacts(fn() {
    laid.get() |> ignore
    (laid_made.val, s.most_now())
  }, fn(_) { hold(@signals.untracked(fn() { laid.get() })) })
  // (what shows held where it is as what is over it changes height: the first block that showed, its top as it was
  // then, the column moved by as far as that moved; as it is scrolled, the first that shows then)
  self.reacts(fn() {
    laid.get() |> ignore
    (laid_made.val, at())
  }, fn(now) {
    let all = @signals.untracked(fn() { laid.get() })
    let (_, x) = now
    let mut d = 0.0
    // (a block by its key, where it is among them: as `laid` was last worked out for these blocks)
    let index_of = fn(k : K) -> Int? {
      match laid_index.val.get(k) {
        Some(i) if i < all.length() && all[i].0 == k => Some(i)
        _ => all.search_by(fn(b) { b.0 == k })
      }
    }
    match anchor.val {
      Some((k, was)) =>
        match index_of(k) {
          Some(i) => d = all[i].1 - was
          None => ()
        }
      None => ()
    }
    if d != 0.0 {
      s.grew_above(d)
    }
    // When the hand brings unmeasured blocks in above words still in sight, those words keep their place while
    // the estimates are replaced. An estimated first block cannot yet take over as the anchor: its measurement
    // could push all the words that were being read out of the window in this same layout.
    let vh = self.laid_size_told().map(fn(z) { z.1 }).unwrap_or(0.0)
    // (those in sight, from the first whose foot is past the column's top down to the first whose top is past its
    // foot: found by halving, not looked for among them all)
    let lo = first_from(all, x + d)
    let mut hi = lo
    while hi < all.length() && all[hi].1 < x + d + vh {
      hi = hi + 1
    }
    let known_in_sight = fn(b : (K, Double, Double, Bool, ListRoom)) {
      b.3 && b.1 < x + d + vh && b.1 + b.2 > x + d
    }
    let mut measuring = false
    let mut first_known : (K, Double)? = None
    for i in lo..<hi {
      let b = all[i]
      if !b.3 && b.1 < x + d + vh && b.1 + b.2 > x + d {
        measuring = true
      }
      if first_known is None && known_in_sight(b) {
        first_known = Some((b.0, b.1))
      }
    }
    let held = match anchor.val.bind(fn(a) {
      index_of(a.0).bind(fn(i) { if known_in_sight(all[i]) { Some(all[i]) } else { None } })
    }) {
      Some(b) => Some((b.0, b.1))
      // The previous anchor can be an estimate from before the list followed its end, or no longer visible.
      // Other measured words still in sight belong to the same reading window. Hold those before giving an
      // unmeasured row the anchor: its first height can otherwise move every already visible row away.
      None => first_known
    }
    // A row's first measurement can still lack its island or a newly made child. Keep the already shown anchor
    // through those measurements too, until the hand moves again or that anchor leaves the window.
    measuring_anchor.val = (measuring || measuring_anchor.val) && held is Some(_) &&
      (!from_end || !@signals.untracked(fn() { follows.get() }))
    anchor.val = if measuring_anchor.val {
      held
    } else {
      let mut i = lo
      while i < all.length() && all[i].1 + all[i].2 <= x + d {
        i = i + 1
      }
      if i < all.length() { Some((all[i].0, all[i].1)) } else { None }
    }
  })
  // The anchor and the scroll range use the same heights. Reading the holder's previous layout here would clamp
  // a compensated anchor to the old end, then mistake that clamp for the reader returning to the end.
  let extent = fn() { laid.get().last().map(fn(b) { b.1 + b.2 }).unwrap_or(0.0) + foot_room() }
  let out = self.scrolls(s, slop?=slop, bar?=bar, content_extent=extent, bar_clear~, fn(held) {
    // (shorter than the column: at its foot)
    if from_end {
      held
      .min_height(By(fn() { self.laid_size_told().map(fn(z) { z.1 }) }))
      .lies_along(Is(End))
      |> ignore
    }
    held.padding(By(fn() { (0.0, 0.0, 0.0, foot_room()) })) |> ignore
    held.each(fn() { made.get() }, made_key, fn(slot, item) {
      let k = match @signals.untracked(fn() { item.get() }) {
        Slot(k, _) => k
        Gap(_, _) => {
          // (not a row of what it holds: nothing is made in it, nothing in it is picked)
          self.tree.nodes[slot.at].each_row = false
          slot.height(By(fn() {
            match item.get() {
              Gap(from, to) => Some(gap_height(from, to))
              Slot(_, _) => Some(0.0)
            }
          }))
          .shrink(Is(0.0))
          |> ignore
          return
        }
      }
      slots[k] = slot
      slot.owns(fn() { slots.remove(k) }) |> ignore
      // (the same row by its key however often its slot is made anew: what is picked in it found in it again)
      let id = match row_ids.get(k) {
        Some(id) => id
        None => {
          let id = self.tree.row_name()
          row_ids[k] = id
          id
        }
      }
      slot.row_known_as(id)
      let shows = fn() { window.get().contains(k) || (match kept { Some(f) => f(k); None => false }) }
      // (its block in `laid`, where the column holds it now: its place there said with its slot, nothing looked for)
      let laid_now = fn() {
        match item.get() {
          Slot(_, i) => laid.get().get(i)
          Gap(_, _) => None
        }
      }
      let room_now = fn() { laid_now().map(fn(b) { b.4 }).unwrap_or(list_room(0.0)) }
      slot.lends(windowed_room, room_now) |> ignore
      // (as tall as it is counted, showing or not: as what it holds was told laid out, est before; never as tall as
      // what it holds is while that is still to be laid out, the column's end gone up and back in one frame)
      slot
      .height(By(fn() { laid_now().map(fn(b) { b.2 }) }))
      .shrink(Is(0.0))
      |> ignore
      if room is Some(_) {
        slot.clips(By(fn() { room_now().clip }))
        .cuts_softly(By(fn() { room_now().soft }))
        .presses(By(fn() { room_now().presses }))
        .hides(By(fn() { !room_now().presses })) |> ignore
      }
      slot.show(shows, fn(v) {
        // (as tall as what it holds, whatever its slot is counted as till that is told)
        v.shrink(Is(0.0)) |> ignore
        if room is Some(_) {
          v.offset(By(fn() { (0.0, room_now().offset) }))
          .scale(By(fn() { room_now().scale }), about=Drawn)
          .alpha(By(fn() { room_now().alpha })) |> ignore
        }
        showing[k] = true
        v.owns(fn() { showing.remove(k) }) |> ignore
        // (how tall it is told as it is laid out, kept by its key)
        v.reacts(fn() { v.laid_size_told() }, fn(z) {
          match z {
            Some((_, h)) if heights.get(k) != Some(h) => {
              heights[k] = h
              told_keys[k] = true
              tell()
            }
            _ => ()
          }
        })
        make(v, k)
      })
    })
  })
  // (after it scrolls: how far it can go is told from then, View::scrolls' room)
  // (kept at its end while it follows: as how far it can go changes, there at once; scrolled from there by any other
  // cause (the hand, the wheel, a fling, a glide), it follows no more, and again once that brings it back there)
  if from_end {
    let last_most = Ref(-1.0)
    let last_x = Ref(0.0)
    // (how many blocks it held: more come at its end while it follows, glided after, not there at once)
    let last_count = Ref(-1)
    let last_key : Ref[K?] = Ref(None)
    // (the blocks it held, by key: those new to it among them told apart; the first new to it that `fresh` says is,
    // till its top is counted)
    let last_keys : Ref[Map[K, Bool]?] = Ref(None)
    // (the array they were told in: the same one again, the same blocks)
    let last_keys_of : Ref[Array[K]?] = Ref(None)
    let newest : Ref[K?] = Ref(None)
    // (shorter than the column, how far its first block's top is under the column's: the room over them at its foot)
    let lead = fn() {
      let total = laid.get().last().map(fn(b) { b.1 + b.2 }).unwrap_or(0.0)
      match self.laid_size_told() {
        Some((_, vh)) => if vh > total { vh - total } else { 0.0 }
        None => 0.0
      }
    }
    let last_lead = Ref(-1.0)
    let last_vh = Ref(-1.0)
    // (blocks come at its end, their heights not told yet: what they come to as told is theirs)
    let awaiting : Map[K, Bool] = Map([])
    self.reacts(fn() { (s.most_now(), s.drawn(self.tree), lead()) }, fn(now) {
      let (most, x, lead_now) = now
      let now_keys = @signals.untracked(keys)
      let all = @signals.untracked(fn() { laid.get() })
      // (what came now, and those of what came before whose heights are told now: the room at its foot falling for
      // them alone, not for the column laid out shorter (the window, a keyboard) nor for anything else)
      // (the same blocks as last time it was told: nothing come, nothing looked for among them all; it is told as the
      // column scrolls, every frame of a glide)
      let same_keys = match last_keys_of.val {
        Some(a) => physical_equal(a, now_keys)
        None => false
      }
      let came_now = match last_keys.val {
        Some(was) if !same_keys => now_keys.filter(fn(k) { !was.contains(k) })
        _ => []
      }
      let ours = came_now.length() > 0
      if ours {
        for k in came_now {
          awaiting[k] = true
        }
      }
      let mut told_now = false
      if !awaiting.is_empty() {
        for b in all {
          if b.3 && awaiting.contains(b.0) {
            awaiting.remove(b.0)
            told_now = true
          }
        }
        for k in awaiting.keys().collect() {
          if !now_keys.contains(k) {
            awaiting.remove(k)
          }
        }
      }
      let vh = self.laid_size_told().map(fn(z) { z.1 }).unwrap_or(-1.0)
      let same_room = last_vh.val < 0.0 || (vh - last_vh.val).abs() < 0.5
      last_vh.val = vh
      // (what was at its foot moves by the change in that room. A new block measured smaller than its estimate
      // gives room back: undo that part of the displacement too, on the same arrival, before anything is drawn.)
      let fell = if room is None && (ours || told_now) &&
        same_room &&
        last_lead.val >= 0.0 &&
        (last_lead.val - lead_now).abs() > 0.5 {
        last_lead.val - lead_now
      } else {
        0.0
      }
      last_lead.val = lead_now
      let grew = most != last_most.val || fell != 0.0
      // (moved up from where it was: scrolled from its end, whatever else changed with it; not while it glides by
      // itself (a glide is stopped by the hand), as where a glide is drawn is read at more than one moment of a frame)
      // (not where it is only kept within how far it can go now, that come to be less)
      let up = s.glides_till() is None && x < (if most < last_x.val { most } else { last_x.val }) - 0.5
      // (come at its end: more of them, the last another; not those come over them, a page before)
      let count = now_keys.length()
      let came = last_count.val >= 0 &&
        count > last_count.val &&
        now_keys.last() != last_key.val &&
        now_keys.last().map(fresh).unwrap_or(false)
      // (the first block new to it that `fresh` says is: where its top is, once it is counted)
      if !same_keys {
        match last_keys.val {
          Some(was) =>
            match now_keys.iter().find_first(fn(k) { !was.contains(k) && fresh(k) }) {
              Some(k) => newest.val = Some(k)
              None => ()
            }
          None => ()
        }
        last_keys.val = Some(Map::from_array(now_keys.map(fn(k) { (k, true) })))
        last_keys_of.val = Some(now_keys)
      }
      let newest_top = match newest.val {
        Some(k) if !read_from_top(k) => {
          newest.val = None
          None
        }
        Some(k) =>
          match @signals.untracked(fn() { laid.get() }).iter().find_first(fn(b) { b.0 == k }) {
            Some(b) if b.3 => {
              // A retained row has been measured before its room has opened. Keep the arrival's target until
              // enough of that room exists to put a tall answer's top under the cover.
              if room is None || heights.get(k).unwrap_or(b.2) <= vh - cover() {
                newest.val = None
              }
              Some(b.1)
            }
            Some(_) => None
            // (gone before it was counted)
            None => {
              newest.val = None
              None
            }
          }
        None => None
      }
      last_count.val = count
      last_key.val = now_keys.last()
      last_most.val = most
      last_x.val = x
      if up {
        if @signals.untracked(fn() { follows.get() }) {
          follows.set(false)
        }
      } else if grew && @signals.untracked(fn() { follows.get() }) {
        // (one come taller than what shows: as far as its top under what covers its top, no further)
        let to = match newest_top {
          // (its top where it is drawn: under the room over the blocks at its foot, where they are shorter than it)
          Some(top) => { let t = top + lead_now - cover(); if t < most { t } else { most } }
          None => most
        }
        // (come at its end while it was shorter than the column: from where what was at its foot was drawn, under its
        // top as far as that went up, on the same way)
        let glide = fn(to : Double) {
          if fell != 0.0 {
            s.glide_under(fell, to)
          } else {
            s.glide_to(to)
          }
        }
        if to < most - 0.5 {
          newest.val = None
          glide(to)
          follows.set(false)
        } else if (room is None && (came || newest.val is Some(_) || s.glides_till() is Some(_))) || s.sent_to() is Some(_) {
          // (blocks come at its end, one new to it not counted yet, or come while it glides after them: glided after, to
          // where its end is now. A requested glide follows changing rooms too: setting x alone leaves its old target;
          // a wheel's distance still belongs to the hand.)
          glide(most)
        } else if x != most {
          s.x.set(most)
          last_x.val = most
        }
      } else if !putting.val && most > 0.0 && s.glides_till() is None {
        // (not while it is put somewhere and held there, nor before it can go anywhere)
        let at_end = x >= most - 0.5
        if at_end != @signals.untracked(fn() { follows.get() }) {
          follows.set(at_end)
        }
      }
    })
  }
  out
}

///|
/// What a windowed list's column holds (View::scrolls_window): a block's slot, or the gap between those with slots (the
/// block before it and the one after by their places, -1 and how many there are at its ends).
priv enum Made[K] {
  Slot(K, Int)
  Gap(Int, Int)
} derive(Eq)

///|
/// A slot by its block's key; a gap by the block before it, as long as that is so.
priv enum MadeKey[K] {
  SlotOf(K)
  GapAfter(Int)
} derive(Eq, Hash)

///|
fn[K] made_key(m : Made[K]) -> MadeKey[K] {
  match m {
    Slot(k, _) => SlotOf(k)
    Gap(from, _) => GapAfter(from)
  }
}
