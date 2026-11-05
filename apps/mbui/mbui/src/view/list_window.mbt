// A column that scrolls (View::scrolls) holding blocks by their keys, each made only while it shows (retained.md's
// lists; as an old view's list builds only the rows in view, ui's Ctx::list), laid out by the list itself once all else
// is laid out, in the same pass (Tree::lays_blocks): each block a root of its own (View::block), as wide as the column,
// as tall as it comes to, put where the blocks over it end. How tall each is counted is kept by its place in a sum
// tree (Heights): as laid out where it was made, by its key, as wide as the column was then; `est` where it never was.
// Which show is had from where the column is scrolled to by halving the sums, a block measured anew changing its own
// count alone; the blocks that come into sight made and laid out there and then, as many as fill what shows, none
// waiting for the next pass to be measured (2026-11-05: a block laid out told its height back, the list laid out again
// for each, one more block a pass, its 3000 tops summed again each time). As what is over what shows changes height (a
// block laid out taller than it was counted, one come or gone over it), the column is moved with it: what shows stays
// where it is.

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
/// A block of a windowed list made now (View::scrolls_window): its slot (a root of its own, laid out by the list, as
/// tall as its room), what it holds (made by the list's `make`, as tall as it comes to), its place among the list's
/// blocks as last laid out, how tall its slot was put, where it was put down the column, and the compute that laid it
/// out last that it is not placed by yet (-1: none).
priv struct Block {
  slot : View
  content : View
  mut i : Int
  mut slot_h : Double
  mut y : Double
  mut unplaced : Int
}

///|
/// A page's list (`s`: Scroll::list, what it holds above moved with it as it grows: Scroll::grew_above) scrolling up and
/// down in it (View::scrolls, `slop` and `bar` as there) holding the
/// blocks `keys` names, in their order, one under another from its top, nothing else: each made by `make` in a node of
/// its own as it comes to show (its room, from the column's top to its foot, met by any of it), let go as it no more
/// does, as tall in the column meanwhile as it was last laid out (`est` where it never was). How tall each that does
/// not show was is forgotten as the column is laid out at another width or all words are measured anew (what shows is
/// laid out again as it is, its height counted anew).
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
/// list follows those rooms directly, without another glide over their motion; natural heights remain kept.
/// `kept`: a block needed outside the visible window too, such as a send's landing while the list glides towards it.
/// It is laid out in its own slot, still cut by the list, and does not change which rows `shown` reports in sight.
/// `bar_clear`: the scroll bar's ends kept clear; `foot_room`: room under the last block, laid out even while the last block is off screen.
/// `reach_to`: a block it goes far enough to put that far under its top however few blocks follow it (what is tucked
/// over them out of view, kept so with a few): the room at its foot as much more as that takes, as they are counted.
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
  room? : (K, Double) -> ListRoom,
  kept? : (K) -> Bool = fn(_) { false },
  moving? : () -> Array[K],
  kept_keys? : () -> Array[K],
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
  reach_to? : () -> (K, Double)? = fn() { None },
) -> View {
  guard self.live() is Some(_) else { return self }
  let tree = self.tree
  let put_at = put.unwrap_or(@signals.signal(None))
  // (put at a block and held there, its key and how far under the column's top its top is: it follows no end
  // meanwhile, till all that shows is laid out as it is; let go as the hand moves it)
  let held_at : Ref[(K, Double)?] = Ref(None)
  // Stop following in the input's cause, before laying out what that input reveals: what comes into sight may move
  // the column by more than the hand moved it, so which way it went cannot be had of where things are laid out.
  s.on_hand = fn(d) {
    held_at.val = None
    if from_end && d < 0.0 {
      follows.set(false)
    }
  }
  self.owns(fn() { s.on_hand = fn(_) { } }) |> ignore
  // (how tall each was laid out, by its key, as wide as the column was then: forgotten as it is laid out at another
  // width, on other pixels, or as all words are measured anew, those made then laid out again as they are)
  let natural : Map[K, Double] = Map([])
  // (the blocks made now, by their keys)
  let blocks : Map[K, Block] = Map([])
  // (what each block's row is known by, whatever slot it is made in: View::row_known_as; forgotten as its key goes, a
  // block of the same key come again another row, nothing picked in the one before found in it)
  let row_ids : Map[K, NodeId] = Map([])
  // (how tall each block is counted, by its place: its slot's height, as its room makes it of how tall it was laid out
  // (`est` where it never was); the keys it was counted for and each one's place among them)
  let index : Ref[Heights] = Ref(Heights::new(0, est))
  let index_keys : Ref[Array[K]?] = Ref(None)
  let place_of : Ref[Map[K, Int]] = Ref(Map([]))
  // (as it was last laid out: how wide its blocks, on which pixels, with which measure of words; how tall what shows)
  let laid_w = Ref(-1.0)
  let laid_grid = Ref(-1.0)
  let laid_words = Ref(-1)
  let laid_vh = Ref(-1.0)
  // (how tall what holds them was last said to be: as far as they reach, View::scrolls_window's holder)
  let laid_reach = Ref(-1.0)
  let laid_once = Ref(false)
  let last_moving : Ref[Array[K]] = Ref([])
  // (those in sight as last laid out, in order; the first in sight and where its top was counted then: what shows
  // held where it is as what is over it changes height)
  let in_sight : Ref[Array[K]] = Ref([])
  let anchor : Ref[(K, Double)?] = Ref(None)
  // (the keys kept made outside what shows, worked out again only as they or what says them change)
  let kept_now = @signals.computed(fn(_) {
    match kept_keys {
      Some(f) => f()
      None => keys().filter(kept)
    }
  })
  // (a block's slot as tall as its room of `h`, on its host's pixels where it sets a page's list's rows on them:
  // Tree::rows_slot; and the room)
  let slot_of = fn(k : K, h : Double) -> (Double, ListRoom) {
    let r = match room {
      Some(f) => f(k, h)
      None => list_room(h)
    }
    (tree.rows_slot(dmax(0.0, r.height)), r)
  }
  // (each block counted anew as the keys are another array: its place, its slot's height; the made ones' places)
  let count_all = fn(all : Array[K]) {
    let at : Map[K, Int] = Map([])
    let hs = all.mapi(fn(i, k) {
      at[k] = i
      slot_of(k, natural.get(k).unwrap_or(est)).0
    })
    index.val = Heights::of(hs)
    place_of.val = at
    index_keys.val = Some(all)
    for k, b in blocks {
      b.i = at.get(k).unwrap_or(-1)
      tree.nodes[b.slot.at].block_place = b.i
    }
    // (rows known by names for keys gone: forgotten)
    for k in row_ids.keys().collect() {
      if !at.contains(k) {
        row_ids.remove(k)
      }
    }
  }
  // (where it is put: the column's top down to where it is laid out, the room over the blocks at its foot while they
  // are shorter than what shows)
  let lead_of = fn(vh : Double) -> Double {
    if from_end {
      dmax(0.0, vh - foot_room() - index.val.total())
    } else {
      0.0
    }
  }
  // what it holds: the blocks, nothing else, and the room at its foot, as much more as going as far as `reach_to` says
  // takes; how far it can go counted by them as they are counted now (read plainly as the column is placed and as an
  // event comes: Scroll's room)
  let extent_now = fn() {
    let all = index.val.total() + foot_room()
    match reach_to() {
      Some((k, off)) =>
        match (place_of.val.get(k), self.live()) {
          (Some(i), Some(n)) => dmax(all, index.val.top(i) - off + n.flex.height)
          _ => all
        }
      None => all
    }
  }
  let holder : Ref[View?] = Ref(None)
  // (a block's slot made where it goes among those made, in their order: View::block)
  let made_before = fn(i : Int) -> Int {
    let mut n = 0
    for _, b in blocks {
      if b.i >= 0 && b.i < i {
        n = n + 1
      }
    }
    n
  }
  // (block `k`'s room as it is counted now, its slot's own)
  let room_of = fn(k : K) -> ListRoom {
    match room {
      Some(f) => f(k, natural.get(k).unwrap_or(est))
      None => list_room(natural.get(k).unwrap_or(est))
    }
  }
  // (block `b`'s slot `h` tall: to be laid out again so where it was not)
  let slot_to = fn(b : Block, h : Double) {
    if h != b.slot_h {
      b.slot_h = h
      tree.nodes[b.slot.at].flex.style.set_height(Pt(h))
      tree.nodes[b.slot.at].flex.dirty = true
    }
  }
  // (block `b` laid out at the column's width: how tall what it holds comes to, kept by its key; its slot as tall as
  // its room of that, laid out again where that is another; counted so. Whether its count changed.)
  let lay_block = fn(k : K, b : Block, w : Double) -> Bool {
    // (placed by the first compute that lays it out, all of it laid out by that or after it: Tree::walk)
    if b.unplaced < 0 {
      b.unplaced = @flex.computes() + 1
    }
    b.slot.block_laid(w) |> ignore
    let nat = tree.nodes[b.content.at].flex.height
    natural[k] = nat
    let (slot_h, _) = slot_of(k, nat)
    if slot_h != b.slot_h {
      slot_to(b, slot_h)
      b.slot.block_laid(w) |> ignore
    }
    if b.i >= 0 && b.i < index.val.length() && index.val.get(b.i) != slot_h {
      index.val.set(b.i, slot_h)
      true
    } else {
      false
    }
  }
  // (block `k`, the `i`th, made: its slot, what it holds made by `make` in it, laid out)
  let made_block = fn(k : K, i : Int, w : Double) -> Unit {
    guard holder.val is Some(h) else { return }
    let id = match row_ids.get(k) {
      Some(id) => id
      None => {
        let id = tree.row_name()
        row_ids[k] = id
        id
      }
    }
    let content : Ref[View?] = Ref(None)
    let slot = h.block(made_before(i), fn(slot) {
      // (the same row by its key however often its slot is made anew: what is picked in it found in it again)
      slot.row_known_as(id)
      slot.lends(windowed_room, fn() { room_of(k) }) |> ignore
      slot.shrink(Is(0.0)) |> ignore
      if room is Some(_) {
        slot.clips(By(fn() { room_of(k).clip }))
        .cuts_softly(By(fn() { room_of(k).soft }))
        .presses(By(fn() { room_of(k).presses }))
        .hides(By(fn() { !room_of(k).presses }))
        |> ignore
      }
      content.val = Some(
        slot.box(fn(v) {
          // (as tall as what it holds, whatever its slot is: its room)
          v.shrink(Is(0.0)) |> ignore
          if room is Some(_) {
            v.offset(By(fn() { (0.0, room_of(k).offset) }))
            .scale(By(fn() { room_of(k).scale }), about=Drawn)
            .alpha(By(fn() { room_of(k).alpha }))
            |> ignore
          }
          make(v, k)
        }),
      )
    })
    guard content.val is Some(c) else { return }
    let b : Block = { slot, content: c, i, slot_h: -1.0, y: -1.0, unplaced: -1 }
    tree.nodes[slot.at].block_place = i
    blocks[k] = b
    lay_block(k, b, w) |> ignore
  }
  // (the blocks whose room meets what shows, `x` down to `x + vh`, as they are counted now, in order: one as tall as
  // nothing at its top with them (what it holds to come to its height as that is laid out: View::by_room), and at its
  // foot where rooms open and close)
  let sight_of = fn(all : Array[K], xa : Double, vh : Double) -> Array[K] {
    let out : Array[K] = []
    let hs = index.val
    let xb = xa + vh
    let mut i = hs.reaching(xa)
    let mut top = hs.top(i)
    while i < all.length() {
      let h = hs.get(i)
      if top >= xb && !(room is Some(_) && h == 0.0 && top == xb) {
        break
      }
      if top + h > xa || (h == 0.0 && top >= xa) {
        out.push(all[i])
      }
      top = top + h
      i = i + 1
    }
    out
  }
  // (from its end, as it follows it: what came at its end, what was there, how far it could go and where it was)
  let last_most = Ref(-1.0)
  let last_x = Ref(0.0)
  let last_count = Ref(-1)
  let last_key : Ref[K?] = Ref(None)
  let last_keys : Ref[Map[K, Bool]?] = Ref(None)
  let last_keys_of : Ref[Array[K]?] = Ref(None)
  let newest : Ref[K?] = Ref(None)
  let last_lead = Ref(-1.0)
  let last_vh = Ref(-1.0)
  let awaiting : Map[K, Bool] = Map([])
  // (kept at its end as it follows it, what it holds grown or come: glided after what came that is new to it, to the
  // top of one taller than what shows; at once else. Whether it was moved at once.)
  let follow = fn(all : Array[K], vh : Double) -> Bool {
    let most = dmax(0.0, extent_now() - vh)
    let x = s.drawn(tree)
    let lead_now = if vh > index.val.total() { vh - index.val.total() } else { 0.0 }
    // (the same blocks as last time it was told: nothing come, nothing looked for among them all)
    let same_keys = match last_keys_of.val {
      Some(a) => physical_equal(a, all)
      None => false
    }
    let came_now = match last_keys.val {
      Some(was) if !same_keys => all.filter(fn(k) { !was.contains(k) })
      _ => []
    }
    let ours = came_now.length() > 0
    for k in came_now {
      awaiting[k] = true
    }
    // (blocks come at its end, their heights not laid out then: what they come to as laid out is theirs)
    let mut told_now = false
    for k in awaiting.keys().collect() {
      if natural.contains(k) {
        awaiting.remove(k)
        told_now = true
      } else if !place_of.val.contains(k) {
        awaiting.remove(k)
      }
    }
    let same_room = last_vh.val < 0.0 || (vh - last_vh.val).abs() < 0.5
    last_vh.val = vh
    // (what was at its foot moves by the change in that room. A new block measured smaller than its estimate gives
    // room back: undo that part of the displacement too, on the same arrival, before anything is drawn.)
    let fell = if room is None &&
      (ours || told_now) &&
      same_room &&
      last_lead.val >= 0.0 &&
      (last_lead.val - lead_now).abs() > 0.5 {
      last_lead.val - lead_now
    } else {
      0.0
    }
    last_lead.val = lead_now
    let grew = most != last_most.val || fell != 0.0
    // (moved up from where it was: scrolled from its end, whatever else changed with it; not while it glides by itself)
    let up = s.glides_till() is None && x < (if most < last_x.val { most } else { last_x.val }) - 0.5
    let count = all.length()
    let came = last_count.val >= 0 &&
      count > last_count.val &&
      all.last() != last_key.val &&
      all.last().map(fresh).unwrap_or(false)
    if !same_keys {
      match last_keys.val {
        Some(was) =>
          match all.iter().find_first(fn(k) { !was.contains(k) && fresh(k) }) {
            Some(k) => newest.val = Some(k)
            None => ()
          }
        None => ()
      }
      last_keys.val = Some(Map::from_array(all.map(fn(k) { (k, true) })))
      last_keys_of.val = Some(all)
    }
    let newest_top = match newest.val {
      Some(k) if !read_from_top(k) => {
        newest.val = None
        None
      }
      Some(k) =>
        match place_of.val.get(k) {
          Some(i) if natural.contains(k) => {
            // A retained row has been measured before its room has opened. Keep the arrival's target until
            // enough of that room exists to put a tall answer's top under the cover.
            if room is None || natural.get(k).unwrap_or(index.val.get(i)) <= vh - cover() {
              newest.val = None
            }
            Some(index.val.top(i))
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
    last_key.val = all.last()
    last_most.val = most
    last_x.val = x
    let mut at_once = false
    if up {
      if follows.get() {
        follows.set(false)
      }
    } else if grew && follows.get() {
      // (one come taller than what shows: as far as its top under what covers its top, no further)
      let to = match newest_top {
        Some(top) => {
          let t = top + lead_now - cover()
          if t < most {
            t
          } else {
            most
          }
        }
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
        // where its end is now. A requested glide follows changing rooms too.)
        glide(most)
      } else if x != most {
        s.x.set(most)
        last_x.val = most
        at_once = true
      }
    } else if held_at.val is None && most > 0.0 && s.glides_till() is None {
      // (not while it is put somewhere and held there, nor before it can go anywhere)
      let at_end = x >= most - 0.5
      if at_end != follows.get() {
        follows.set(at_end)
      }
    }
    at_once
  }
  // (put at block `k`, that far under the column's top, as the blocks over it are counted now: held there till all
  // that shows is laid out as it is, and it can go there)
  let hold = fn(vh : Double) {
    guard held_at.val is Some((k, offset)) else { return }
    guard place_of.val.get(k) is Some(i) else {
      held_at.val = None
      return
    }
    let h = index.val.get(i)
    let known = natural.contains(k)
    // A first measurement may include only a row's heading, with its hosted content still to be measured. Keep part
    // of that row in sight until the saved point fits inside it.
    let past = if offset < 0.0 { dmin(-offset, dmax(0.0, h - 0.5)) } else { -offset }
    let top = index.val.top(i)
    let to = dmax(0.0, if known { top + past } else { top })
    anchor.val = Some((k, top))
    s.x.set(to)
    // (let go once it is laid out as it is and can go there: what shows all laid out as it is, by then)
    let most = dmax(0.0, extent_now() - vh)
    let inside = offset >= 0.0 || -offset < h
    if known && inside && to <= most + 0.5 {
      held_at.val = None
    }
  }
  // (what shows held where it is as what is over it changes height: the first block in sight as last laid out, its top
  // as counted then, the column moved by as far as that moved)
  let held_by_anchor = fn() {
    match anchor.val {
      Some((k, was)) =>
        match place_of.val.get(k) {
          Some(i) => {
            let now = index.val.top(i)
            if now != was {
              anchor.val = Some((k, now))
              s.grew_above(now - was)
              // (moved by itself, with what shows: where it was seen as it follows its end moved with it, no move of
              // the hand's up or down from there)
              last_x.val = last_x.val + (now - was)
            }
          }
          None => anchor.val = None
        }
      None => ()
    }
  }
  // (put where it is to be, not placed yet: laid out to be read alone, Tree::measured_now)
  let to_place = Ref(false)
  // (where the column was as it was last laid out, and whether it was moved from there since by anything but its list)
  let left_at = Ref(@double.neg_infinity)
  let moved = Ref(true)
  // (what it read changed since it was last laid out, or it was never laid out: laid out again with all else as a frame
  // lays it out)
  let told = Ref(true)
  // the blocks laid out, once all else is: what shows made and laid out, as many as fill it, those no more in sight let
  // go, each put where those over it end
  let lay_now = fn(place : Bool) -> Bool {
    // (laid out nowhere, or as wide as nothing: nothing of it can be laid out, its blocks as they were, and it is laid
    // out as it next can be, whatever changed meanwhile, its keys read then)
    guard holder.val is Some(h) && h.live() is Some(hn) && self.live() is Some(sn) && sn.placed && hn.flex.width > 0.0 else {
      told.val = true
      return false
    }
    let w = hn.flex.width
    let vh = sn.flex.height
    let all = keys()
    let grid = tree.rows_grid_said.get()
    let words = tree.words_redone.get()
    // (moved from where it was left as last laid out by anything but itself since: the hand, a glide, a fling)
    if s.drawn(tree) != left_at.val {
      moved.val = true
    }
    // (put, said: it follows no end and is held at that block from now)
    match put_at.get() {
      Some(p) => {
        follows.set(false)
        held_at.val = Some(p)
        put_at.set(None)
      }
      None => ()
    }
    // (laid out at another width, on other pixels, or all words measured anew: how tall each was forgotten, those made
    // laid out again as they are)
    let anew = (w - laid_w.val).abs() > 0.01 || grid != laid_grid.val || words != laid_words.val
    if anew {
      if laid_w.val >= 0.0 {
        for k in natural.keys().collect() {
          if !blocks.contains(k) {
            natural.remove(k)
          }
        }
      }
      laid_w.val = w
      laid_grid.val = grid
      laid_words.val = words
    }
    // (each counted anew as the keys are another array, or as rooms are said and which are on their way is not: any
    // may have changed)
    let recount = anew ||
      (room is Some(_) && moving is None) ||
      index.val.length() != all.length() ||
      (match index_keys.val {
        Some(a) => !physical_equal(a, all)
        None => true
      })
    if recount {
      // (made ones whose keys went: let go)
      let at : Map[K, Bool] = Map([])
      for k in all {
        at[k] = true
      }
      for k in blocks.keys().collect() {
        if !at.contains(k) {
          match blocks.get(k) {
            Some(b) => h.block_gone(b.slot)
            None => ()
          }
          blocks.remove(k)
        }
      }
      count_all(all)
      // (those made held in their order as the keys have them now: drawn and found in it)
      let order = blocks.values().collect()
      order.sort_by(fn(a, b) { a.i.compare(b.i) })
      let held = hn.kids.filter(fn(at) { !tree.nodes[at].own_root })
      for b in order {
        held.push(b.slot.at)
      }
      if !(held == hn.kids) {
        hn.kids.clear()
        hn.kids.append(held)
        tree.order_marked()
      }
      // (the made ones' slots as tall as they are counted now: laid out again so)
      for _, b in blocks {
        if b.i >= 0 {
          slot_to(b, index.val.get(b.i))
        }
      }
    }
    // (those on their way, and those that were: their rooms counted anew, the rest as they were)
    let now_moving = match moving {
      Some(f) => f()
      None => []
    }
    let recounted : Map[K, Bool] = Map([])
    let were_moving = last_moving.val.copy()
    were_moving.append(now_moving)
    for k in were_moving {
      if recounted.contains(k) {
        continue
      }
      recounted[k] = true
      match place_of.val.get(k) {
        Some(i) => {
          let (slot_h, _) = slot_of(k, natural.get(k).unwrap_or(est))
          match blocks.get(k) {
            Some(b) => slot_to(b, slot_h)
            None => ()
          }
          if index.val.get(i) != slot_h {
            index.val.set(i, slot_h)
          }
        }
        None => ()
      }
    }
    last_moving.val = now_moving
    // (those made whose contents changed, or that are to be laid out anew: laid out again, counted as they come to)
    @signals.untracked(fn() {
      for k, b in blocks {
        if anew || tree.nodes[b.slot.at].flex.dirty {
          lay_block(k, b, w) |> ignore
        }
      }
    })
    let kept_keys_now = kept_now.get()
    // (what came over what showed as it was last laid out, or what of that was laid out again: what showed moved with
    // it, where it is drawn)
    if held_at.val is None {
      held_by_anchor()
    }
    // (first laid out from its end: there before anything is made, nothing made at its top to be let go)
    if from_end && !laid_once.val && held_at.val is None && follows.get() {
      s.x.set(dmax(0.0, extent_now() - vh))
    }
    // what shows made and laid out, as many as fill it: each made counted as it comes to, what shows moved with what
    // over it as it is, again till what shows is all made
    let mut rounds = 0
    let mut sight : Array[K] = []
    while rounds < 512 {
      rounds = rounds + 1
      hold(vh)
      if held_at.val is None {
        held_by_anchor()
      }
      // (where it shows from, within how far it can go as it is counted now: where it is drawn from once it is put
      // there, Scroll's room)
      let most = dmax(0.0, extent_now() - vh)
      let x = s.drawn(tree)
      let xa = (if x > most { most } else if x < 0.0 { 0.0 } else { x }) - lead_of(vh)
      sight = sight_of(all, xa, vh)
      // (moved from where it was left as last laid out (the hand, a glide, put): the first in sight that was laid out
      // before, its top as counted now, held where it is drawn as what comes into sight over it is laid out other than
      // it was counted, the column moved with it, till it is moved so again (none in sight: nothing drawn there to
      // hold, the column where it was put))
      if held_at.val is None && moved.val {
        moved.val = false
        anchor.val = match sight.iter().find_first(fn(k) { blocks.contains(k) }) {
          Some(k) => place_of.val.get(k).map(fn(i) { (k, index.val.top(i)) })
          None => None
        }
      }
      let made = Ref(false)
      @signals.untracked(fn() {
        // (the first in sight not made: made and laid out, what shows looked at again as it comes to before the next
        // is made, none made for room another takes)
        match sight.iter().find_first(fn(k) { !blocks.contains(k) && place_of.val.contains(k) }) {
          Some(k) => {
            made_block(k, place_of.val.get(k).unwrap(), w)
            made.val = true
          }
          None => ()
        }
        if made.val {
          return
        }
        for k in kept_keys_now {
          if !blocks.contains(k) {
            match place_of.val.get(k) {
              Some(i) => {
                made_block(k, i, w)
                made.val = true
              }
              None => ()
            }
          }
        }
      })
      if made.val {
        continue
      }
      // (kept at its end as it follows it: moved there at once, what shows there made in turn)
      if from_end && follow(all, vh) {
        continue
      }
      break
    }
    laid_once.val = true
    // (what shows held where it is as what is over it changes height: the block it was held by while it is in sight,
    // else the first in sight, its top as counted now)
    if held_at.val is None {
      let kept_anchor = match anchor.val {
        Some((k, _)) => sight.contains(k) && blocks.contains(k)
        None => false
      }
      if !kept_anchor {
        anchor.val = match sight.iter().find_first(fn(k) { blocks.contains(k) }) {
          Some(k) => place_of.val.get(k).map(fn(i) { (k, index.val.top(i)) })
          None => None
        }
      }
    }
    // (where it was left: moved from there by anything but itself, anchored again)
    left_at.val = s.drawn(tree)
    // (those no more in sight nor kept: let go)
    let keep : Map[K, Bool] = Map([])
    for k in sight {
      keep[k] = true
    }
    for k in kept_keys_now {
      keep[k] = true
    }
    for k in blocks.keys().collect() {
      if !keep.contains(k) {
        match blocks.get(k) {
          Some(b) => h.block_gone(b.slot)
          None => ()
        }
        blocks.remove(k)
      }
    }
    // (as tall as what shows as last laid out)
    laid_vh.val = vh
    // (what holds them as tall as they reach, with the room at its foot; from its end, at least as tall as what shows,
    // they at its foot: laid out so, what asks how far what it holds goes finds it there, as for any that scrolls
    // (whether it scrolls, whether what it holds ends above its foot: Tree::scrolls_now, the corner rule))
    // (where it is, at rest, within how far it can go as it is laid out now: its own layout's, as Scroll::kept_in has it
    // for any that scrolls, what that moves laid out again in this same pass, nothing of it owed)
    let most_now = dmax(0.0, extent_now() - vh)
    @signals.untracked(fn() {
      if s.x.get() > most_now && s.glides_till() is None {
        s.x.set(most_now)
      }
    })
    let reach = if from_end { dmax(vh, extent_now()) } else { extent_now() }
    if reach != laid_reach.val {
      laid_reach.val = reach
      hn.flex.style.set_height(Pt(reach))
      tree.layout_marked_at(h.at)
    }
    // (those in sight told, as they change)
    if !(sight == in_sight.val) {
      in_sight.val = sight
      match shown {
        Some(sh) => sh.set(sight)
        None => ()
      }
    }
    // each put where those over it end, under the room at its foot while they are shorter than what shows
    let lead = lead_of(vh)
    let mut placed = false
    let mut owed = false
    for _, b in blocks {
      if b.i < 0 {
        continue
      }
      let y = lead + index.val.top(b.i)
      if y != b.y || b.unplaced >= 0 {
        b.slot.block_put(0.0, y, if place { b.unplaced } else { -1 }, place)
        // (where it was placed: put only to be read, it is placed there yet, by the next that places)
        if place {
          b.y = y
          b.unplaced = -1
          placed = true
        } else {
          owed = true
        }
      }
    }
    to_place.val = owed
    placed
  }
  // (what it read followed: as any of it changes, laid out again with all else as a frame lays it out)
  let watch = @signals.watch(fn() {
    told.val = true
    tree.lists_due = true
    tree.marked()
  })
  let laying = Ref(false)
  let lay = fn(place : Bool, marked : Bool) -> Bool {
    if laying.val {
      return false
    }
    // (nothing it read changed, none of its blocks marked, its column as wide and as tall as it was laid out in, all
    // of it placed where it is to be: nothing of it to lay out)
    let same_room = match (holder.val, self.live()) {
      (Some(h), Some(sn)) =>
        match h.live() {
          Some(hn) => hn.flex.width == laid_w.val && sn.flex.height == laid_vh.val
          None => false
        }
      _ => false
    }
    if !told.val && !marked && same_room && !(place && to_place.val) {
      return false
    }
    told.val = false
    laying.val = true
    @signals.start_batch()
    let placed = watch.read(fn() { lay_now(place) })
    laying.val = false
    @signals.end_batch()
    placed
  }
  self.owns(fn() { watch.stop() }) |> ignore
  // (its blocks in sight by their places, it put at one, and how far past the first in sight's top it is: what a test
  // reads and asks, Tree::list_rows)
  s.rows = Some((
    fn() {
      let w = in_sight.val
      match (w.get(0), w.last()) {
        (Some(a), Some(b)) => (place_of.val.get(a).unwrap_or(-1), place_of.val.get(b).unwrap_or(-1))
        _ => (-1, -1)
      }
    },
    fn(i) {
      match index_keys.val.bind(fn(a) { a.get(i) }) {
        // A requested row owns the new position through its first full measurement, just as a saved position does.
        Some(k) => put_at.set(Some((k, 0.0)))
        None => ()
      }
    },
    fn() {
      let vh = match self.live() {
        Some(n) => n.flex.height
        None => 0.0
      }
      let x = s.drawn(tree) - lead_of(vh)
      let hs = index.val
      let i = hs.at(x)
      if i < hs.length() {
        x - hs.top(i)
      } else {
        0.0
      }
    },
    fn(i) {
      match index_keys.val.bind(fn(a) { a.get(i) }) {
        Some(k) => blocks.get(k).map(fn(b) { b.slot.rect() })
        None => None
      }
    },
  ))
  self.owns(fn() { s.rows = None }) |> ignore
  let out = self.scrolls(s, slop?=slop, bar?=bar, content_extent=extent_now, bar_clear~, fn(held) {
    holder.val = Some(held)
    tree.lays_blocks(held, lay)
  })
  out
}
