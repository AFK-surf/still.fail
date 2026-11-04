// A page's list laid out from its anchor (retained.md rule 11): the rows it holds made, measured and placed in its own
// layout (View::layout_box), from the anchor out till the window and `ahead` more is filled, laid out from its end (a
// chat's). Where it is is the anchor alone (anchor_list.mbt); the column's scroll (View::scrolls) is the hand's, a
// fling's and the bar's: what it moved by since the last layout is what the anchor moves by, and how far it is
// scrolled is where the anchor is counted to be among them all (the heights measured, by key, and `est` for the rest),
// for the bar and for how far it can go, said again as the anchor is laid out.

///|
/// A value compared by its identity: the rows given are the same as long as their array is.
priv struct Same[T] {
  v : T
}

///|
impl[T] Eq for Same[T] with equal(a, b) {
  physical_equal(a.v, b.v)
}

///|
/// What a layout of an anchored list reads, pulled before layout: the rows, where its column is scrolled to, the room
/// under its last row, whether it is put at a row (by how often it was), and the rooms' moment.
priv struct AnchoredIn[K] {
  keys : Same[Array[K]]
  /// For an indexed source: its shape revision and length, captured before layout.
  indexed : (Int, Int)?
  x : Double
  foot : Double
  put : (K, Double)?
  put_n : Int
  kept : Array[K]
  rooms : Same[(K, Double) -> ListRoom]
  /// of the rows the list ends with (the last `tail`), those new to it that `fresh` says are, and of those whether each
  /// is read from its top; what covers its top
  fresh : Array[(K, Bool)]
  cover : Double
  tucked : K?
  /// the row last asked to be brought into sight, and how often one was
  reveal : (K?, Int)
}

///|
impl[K : Eq] Eq for AnchoredIn[K] with equal(a, b) {
  // (the rows the same where their array is, or where it was made again holding the same: what pulls them makes it
  // anew each time it is read)
  (physical_equal(a.keys.v, b.keys.v) || a.keys.v == b.keys.v) &&
  a.indexed == b.indexed &&
  a.x == b.x &&
  a.foot == b.foot &&
  a.put_n == b.put_n &&
  a.kept == b.kept &&
  a.rooms == b.rooms &&
  a.fresh == b.fresh &&
  a.cover == b.cover &&
  a.tucked == b.tucked &&
  a.reveal == b.reveal
}

///|
/// How many of the rows it ends with are looked at for one come new among them.
let anchored_tail = 8

///|
/// A keyed list that can be read by position without assembling all of its keys. Snapshot follows changes to the
/// set or order and returns its revision and length. Key and find read that snapshot without signals; find may use
/// near as a hint. Removed_since returns keys removed after a revision, or None if that history is no longer
/// available; contains checks the current set. The source keeps changes until the list is released.
pub(all) struct AnchoredSource[K] {
  snapshot : () -> (Int, Int)
  key : (Int) -> K
  find : (K, Int) -> Int?
  removed_since : (Int) -> Array[K]?
  contains : (K) -> Bool
}

///|
/// Blocks `keys` names, each made by `make` in a row of its own as it comes in the window or `ahead` past it, laid out
/// from the column's end (at its foot while they are fewer than fill it; shown at its end; kept there as rows come
/// while it is there), as View::scrolls_window's from its end says, by its anchor. `follows` says whether it is at
/// its end; `shown` is told the keys in sight; `put` puts a row's top that far under the window's top; `room` is a
/// row's room as its measured height changes, `moving` says when rooms move; `kept_keys` rows made and laid out
/// though not in sight (a send's landing); `foot_room` room under the last row. An indexed source supplies its
/// keys by position instead of `keys`.
pub fn[K : Hash + Eq] View::scrolls_anchored(
  self : View,
  s : Scroll,
  keys : () -> Array[K],
  make : (View, K) -> Unit,
  est? : Double = 80.0,
  from_end? : Bool = true,
  ahead? : Double = 160.0,
  slop? : Double,
  bar? : ScrollBar,
  follows? : @signals.Signal[Bool] = @signals.signal(true, same=fn(a, b) { a == b }),
  shown? : @signals.Signal[Array[K]],
  put? : @signals.Signal[(K, Double)?],
  rooms? : () -> (K, Double) -> ListRoom,
  fresh? : (K) -> Bool = fn(_) { false },
  read_from_top? : (K) -> Bool = fn(_) { true },
  cover? : () -> Double = fn() { 0.0 },
  tucked? : () -> K? = fn() { None },
  kept_keys? : () -> Array[K],
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
  indexed? : AnchoredSource[K],
) -> View {
  guard self.live() is Some(_) else { return self }
  let put_at = put.unwrap_or(@signals.signal(None))
  // (where it is: the row whose foot is nearest under the window's foot and how far under; none at its end)
  let anchor : Ref[ListAnchor[K]?] = Ref(None)
  // (how far it was scrolled as last laid out: what it moved by since is what the anchor moves by)
  let seen_x : Ref[Double?] = Ref(None)
  // (each row's height as last measured, by its key: for how tall all of it is counted, the bar's, and nothing else)
  let heights : Map[K, Double] = Map([])
  let known_sum = Ref(0.0)
  let mean = fn() { if heights.length() > 0 { known_sum.val / heights.length().to_double() } else { est } }
  let count = Ref(0)
  let laid : Ref[ListLaid[K]?] = Ref(None)
  // (the rows it ended with as last laid out)
  let was_tail : Ref[Array[K]] = Ref([])
  let tuck_done = Ref(false)
  let window_h = Ref(0.0)
  // (what each row is known by, whatever node it is made in, by its key: View::row_known_as)
  let row_ids : Map[K, NodeId] = Map([])
  let slots : Map[K, View] = Map([])
  // (which row each of its rows' nodes is, by the node: what one in it to be brought into sight is found by)
  let slot_keys : Map[Int, K] = Map([])
  // (the row asked to be brought into sight at the cause that asked, and how many times; how many its layout did)
  let reveal_said : @signals.Signal[(K?, Int)] = @signals.signal((None, 0))
  let revealed = Ref(0)
  // (the node in it to be brought into sight, and what part of it)
  let reveal_of : Ref[(NodeId, (Double, Double)?)?] = Ref(None)
  // (each key's name among its layout's children, as long as it is in it)
  let names : Map[K, String] = Map([])
  let named = Ref(0)
  let name_of = fn(k : K) -> String {
    match names.get(k) {
      Some(s) => s
      None => {
        named.val += 1
        let s = "r\{named.val}"
        names[k] = s
        s
      }
    }
  }
  let naturals : Map[K, Double] = Map([])
  // (each row's room as last laid out, and how often it was: what draws it reads)
  let rooms_laid : Map[K, ListRoom] = Map([])
  let laid_n : @signals.Signal[Int] = @signals.signal(0)
  let natural_room = fn(_k : K, h : Double) { list_room(h) }
  // Keep the captured room function until one of its own inputs changes. Clearing a completed placement request
  // must not make an otherwise identical room look new while the layout result is being published.
  let current_rooms = @signals.computed(fn(_) {
    match rooms {
      Some(f) => f()
      None => natural_room
    }
  })
  // (the hand scrolling it toward its start: no more at its end, from the hand's cause, before what it brings in is
  // measured)
  s.on_hand = fn(d) {
    if from_end && d < 0.0 && @signals.untracked(fn() { follows.get() }) {
      follows.set(false)
    }
  }
  self.owns(fn() { s.on_hand = fn(_) { } }) |> ignore
  // (how many times it was put at a row, and the rooms' moment: what is laid out again as they change)
  // (how many times it was put at a row: one said none again, as its layout has done it, is not another)
  let put_n = @signals.computed(fn(was : Int?) {
    let n = was.unwrap_or(0)
    if put_at.get() is Some(_) { n + 1 } else { n }
  })
  // A requested place takes the list away from following its end before layout. If the requested row turns out to
  // be at the end, the finished layout says so again below.
  self.reacts(fn() { put_at.get() }, fn(p) {
    if from_end && p is Some(_) && @signals.untracked(fn() { follows.get() }) {
      follows.set(false)
    }
  })
  // A layout may be measured more than once before it is committed. Keep the request through those probes, then do
  // not replay the cached input as later frames lay the list out for another reason.
  let put_laid = Ref(0)
  // (where the hand has it: what its layout reads is how far it moved since it was last laid out, never changed by the
  // list as it is laid out; how far that is from where it is counted to be among all it holds, as last laid out, what
  // its bar and what reads where it is add to it, and where the hand has it is put by as the hand comes to it again:
  // its ends, their give and a fling's end all as it is counted, from that event)
  let bar_off = Ref(0.0)
  s.bar_off = fn() { bar_off.val }
  s.reads_free = true
  s.rebase = fn() {
    let d = bar_off.val
    if d != 0.0 {
      bar_off.val = 0.0
      seen_x.val = seen_x.val.map(fn(x) { x + d })
      if s.as_list {
        s.grew_above(d)
      } else {
        @signals.untracked(fn() { s.x.set(s.x.get() + d) })
      }
    }
  }
  // (one of its rows' nodes to be brought into sight: that row, laid out in sight as it is laid out next)
  s.reveal = fn(id, part) {
    let mut i = id.at
    while i >= 0 {
      match slot_keys.get(i) {
        Some(k) => {
          let (_, n) = @signals.untracked(fn() { reveal_said.get() })
          reveal_of.val = Some((id, part))
          reveal_said.set((Some(k), n + 1))
          return
        }
        None => ()
      }
      i = self.tree.nodes[i].parent
      if i == self.at {
        return
      }
    }
  }
  self.owns(fn() { s.bar_off = fn() { 0.0 }; s.rebase = fn() { }; s.reveal = fn(_, _) { }; s.reads_free = false }) |> ignore
  // (how tall all it holds is counted, as its layout last counted it: what its bar reads once it is laid out, no signal
  // read then)
  let foot_laid = Ref(0.0)
  let extent = fn() { count.val.to_double() * mean() + foot_laid.val }
  // (told once laid out as how tall all it holds is counted comes out otherwise: what follows how far it can go
  // reads it, not its layout)
  let extent_said : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { (a - b).abs() < 0.5 })
  s.extent_told = fn() { extent_said.get() |> ignore }
  self.owns(fn() { s.extent_told = fn() { } }) |> ignore
  let out = self.scrolls(s, slop?=slop, bar?=bar, content_extent=extent, bar_clear~, fn(held) {
    held.height_share(Is(1.0)) |> ignore
    held.layout_box(
      By(fn() {
        {
          keys: { v: if indexed is Some(_) { [] } else { keys() } },
          indexed: indexed.map(fn(s) { (s.snapshot)() }),
          x: s.drawn(self.tree),
          foot: foot_room(),
          put: put_at.get(),
          put_n: put_n.get(),
          kept: match kept_keys {
            Some(f) => f()
            None => []
          },
          rooms: { v: current_rooms.get() },
          fresh: {
            let ks = if indexed is Some(_) { [] } else { keys() }
            let n = match indexed { Some(s) => (s.snapshot)().1; None => ks.length() }
            let out = []
            for i in dmax_i(0, n - anchored_tail)..<n {
              let k = match indexed { Some(s) => (s.key)(i); None => ks[i] }
              if fresh(k) {
                out.push((k, read_from_top(k)))
              }
            }
            out
          },
          cover: cover(),
          tucked: tucked(),
          reveal: reveal_said.get(),
        }
      }),
      fn(l, c) {
        let all = c.keys.v
        let n = c.indexed.map(fn(s) { s.1 }).unwrap_or(all.length())
        count.val = n
        foot_laid.val = c.foot
        let h = l.height - c.foot
        window_h.val = h
        // (the row a key is, looked for from where it was, out both ways)
        let find = fn(k : K, near : Int) -> Int? {
          match indexed {
            Some(source) => return (source.find)(k, near)
            None => ()
          }
          let near = if near < 0 { 0 } else if near >= n { n - 1 } else { near }
          let mut d = 0
          while near - d >= 0 || near + d < n {
            if near + d < n && all[near + d] == k {
              return Some(near + d)
            }
            if d > 0 && near - d >= 0 && all[near - d] == k {
              return Some(near - d)
            }
            d = d + 1
          }
          None
        }
        let key_at = fn(i : Int) {
          match indexed { Some(source) => (source.key)(i); None => all[i] }
        }
        // (a row's node, made the first time it is asked for, the same one while it is asked for each layout)
        let slot_of = fn(k : K) -> View {
          l.child(name_of(k), fn(slot) {
            let id = match row_ids.get(k) {
              Some(id) => id
              None => {
                let id = self.tree.row_name()
                row_ids[k] = id
                id
              }
            }
            slot.row_known_as(id)
            slots[k] = slot
            slot_keys[slot.at] = k
            let at = slot.at
            slot.owns(fn() {
              slots.remove(k)
              slot_keys.remove(at)
            })
            |> ignore
            let room_now = fn() {
              laid_n.get() |> ignore
              rooms_laid.get(k).unwrap_or(list_room(naturals.get(k).unwrap_or(0.0)))
            }
            slot.lends(windowed_room, room_now) |> ignore
            slot.shrink(Is(0.0)) |> ignore
            if rooms is Some(_) {
              slot
              .clips(By(fn() { room_now().clip }))
              .cuts_softly(By(fn() { room_now().soft }))
              .presses(By(fn() { room_now().presses }))
              .hides(By(fn() { !room_now().presses }))
              |> ignore
            }
            slot.box(fn(v) {
              v.shrink(Is(0.0)) |> ignore
              if rooms is Some(_) {
                v
                .offset(By(fn() { (0.0, room_now().offset) }))
                .scale(By(fn() { room_now().scale }), about=Drawn)
                .alpha(By(fn() { room_now().alpha }))
                |> ignore
              }
              make(v, k)
            })
            |> ignore
          })
        }
        // (a row measured: as tall as it is, its room's height where its room moves)
        let measure = fn(i : Int) -> Double {
          let k = key_at(i)
          let slot = slot_of(k)
          self.tree.nodes[slot.at].row_index = Some(i)
          let natural = l.measure(slot, l.width).1
          naturals[k] = natural
          match heights.get(k) {
            Some(was) => known_sum.val = known_sum.val - was + natural
            None => known_sum.val = known_sum.val + natural
          }
          heights[k] = natural
          let r = (c.rooms.v)(k, natural)
          rooms_laid[k] = r
          if (r.height - natural).abs() > 0.001 {
            l.measure(slot, l.width, height=r.height) |> ignore
          }
          r.height
        }
        // (put at a row, its top that far under the window's top)
        let putting = c.put_n > put_laid.val && c.put is Some(_)
        match c.put {
          Some((k, off)) if putting =>
            match find(k, anchor.val.map(fn(a) { a.near }).unwrap_or(n - 1)) {
              Some(i) =>
                anchor.val = Some({ key: k, under: if from_end { off + measure(i) - h } else { -off }, near: i })
              None => ()
            }
          _ => ()
        }
        let by = match seen_x.val {
          Some(x) => if from_end { x - c.x } else { c.x - x }
          // (from its start, first laid out: as far down as it was scrolled, as its rows are counted)
          None => if from_end { 0.0 } else { c.x }
        }
        // (a row kept out of sight over its top (the chats' search), its foot under what covers the top, as it is first
        // laid out unscrolled; room kept under its last row for that however few there are)
        let mut slack = 0.0
        match (from_end, c.tucked) {
          (false, Some(k)) =>
            match find(k, 0) {
              Some(i) => {
                let own = measure(i)
                let mut over = 0.0
                for j in 0..<i {
                  over = over + measure(j)
                }
                // (all that is over its foot out of sight, however few rows there are under it)
                slack = dmax(0.0, over + own - c.cover)
                if !tuck_done.val && c.x <= 0.5 && seen_x.val is None {
                  anchor.val = Some({ key: k, under: own - c.cover, near: i })
                }
                tuck_done.val = true
              }
              None => ()
            }
          _ => ()
        }
        seen_x.val = Some(c.x)
        // (one new to it come among the rows it ends with while it is at its end, that `fresh` says is: what showed kept
        // where it was, glided after once it is laid out; one taller than what shows under its cover glided to only as
        // far as its top under that, no more at its end)
        let mut glide : (K, Bool)? = None
        match (if from_end { laid.val } else { None }, anchor.val) {
          (Some(was), None) if was_tail.val.length() > 0 =>
            for f in c.fresh {
              if !was_tail.val.contains(f.0) {
                // (the row over it as it was laid out: kept where its foot was)
                match find(f.0, n - 1) {
                  Some(i) if i > 0 => {
                    let over = key_at(i - 1)
                    for q in 0..<was.keys.length() {
                      if was.keys[q] == over {
                        anchor.val = Some({ key: over, under: was.tops[q] + was.heights[q] - h, near: i - 1 })
                        glide = Some(f)
                        break
                      }
                    }
                  }
                  _ => ()
                }
                break
              }
            }
          _ => ()
        }
        let tail_start = dmax_i(0, n - anchored_tail)
        was_tail.val = Array::makei(n - tail_start, fn(i) { key_at(tail_start + i) })
        let key_of = fn(i : Int) { key_at(i) }
        let known = fn(i : Int) { heights.get(key_at(i)) }
        let lay = fn(from : ListAnchor[K]?, by : Double) {
          if from_end {
            list_laid_from_end(n, key_of, find, measure, from, h, by~, ahead~, known~)
          } else {
            list_laid_from_top(n, key_of, find, measure, from, h, by~, ahead~, known~, slack~)
          }
        }
        let from = anchor.val
        let mut r = lay(from, by)
        // (a row asked to be brought into sight since it was last laid out: where it is laid out now, measured as it is,
        // moved as little as brings the part asked of it in (as shows has a column do), laid out again so; one not
        // laid out now in sight or near it: its top at the window's top, or its foot at its foot)
        match c.reveal {
          (Some(k), asked) if asked > revealed.val => {
            revealed.val = asked
            // (the part asked of it within its row, where its row is laid out now: its top and its foot from the row's)
            let part_in = fn(row_h : Double) -> (Double, Double) {
              match reveal_of.val {
                Some((id, within)) if self.tree.alive_id(id) => {
                  let mut off = 0.0
                  let mut j = id.at
                  let slot_at = slots.get(k).map(fn(v) { v.at }).unwrap_or(-1)
                  while j >= 0 && j != slot_at {
                    off = off + self.tree.nodes[j].flex.top
                    j = self.tree.nodes[j].parent
                  }
                  let (a, b) = within.unwrap_or((0.0, self.tree.nodes[id.at].flex.height))
                  if j == slot_at { (off + a, off + b) } else { (0.0, row_h) }
                }
                _ => (0.0, row_h)
              }
            }
            let mut q = -1
            for j in 0..<r.keys.length() {
              if r.keys[j] == k {
                q = j
              }
            }
            if q >= 0 {
              let row_top = r.tops[q]
              let (pa, pb) = part_in(r.heights[q])
              let (top, foot) = (row_top + pa, row_top + pb)
              let down = if top < 0.0 { -top } else if foot > h { -dmin(top, foot - h) } else { 0.0 }
              if down != 0.0 {
                r = lay(from, by + (if from_end { down } else { -down }))
              }
            } else {
              // (not laid out among those in sight now: its row measured as it is, put where the part asked of it comes
              // in, its top at the window's top from over it, its foot at the window's foot from under it, its top first
              // where it is taller than the window)
              match find(k, r.first) {
                Some(i) => {
                  let hk = measure(i)
                  let (pa, pb) = part_in(hk)
                  let row_top = if i < r.first || pb - pa > h { -pa } else { h - pb }
                  let under = if from_end { row_top + hk - h } else { -row_top }
                  r = lay(Some({ key: k, under, near: i }), 0.0)
                }
                None => ()
              }
            }
          }
          _ => ()
        }
        anchor.val = r.anchor
        // (how far it is counted to be scrolled among all it holds, the bar's, as laid out now)
        let at_end = from_end && r.at_end
        let most = dmax(0.0, n.to_double() * mean() - h)
        let counted = if at_end || (!from_end && r.at_start) {
          most
        } else if r.first == 0 {
          -r.tops.get(0).unwrap_or(0.0)
        } else {
          dmin(most, r.first.to_double() * mean() - r.tops.get(0).unwrap_or(0.0))
        }
        bar_off.val = counted - c.x
        // (placed where they are in the window: the column holds them moved by how far it is scrolled)
        for q in 0..<r.keys.length() {
          l.place(slot_of(r.keys[q]), 0.0, r.tops[q] + c.x)
        }
        // (and those kept out of sight, as far off as they are counted to be)
        match Some(c.kept) {
          Some(kept) =>
            for k in kept {
              match find(k, r.first) {
                Some(i) if i < r.first || i > r.last => {
                  let slot = slot_of(k)
                  let hk = measure(i)
                  let top = if i < r.first {
                    r.tops.get(0).unwrap_or(0.0) - (r.first - i).to_double() * mean()
                  } else {
                    r.tops.last().unwrap_or(h) + r.heights.last().unwrap_or(0.0) + (i - r.last - 1).to_double() * mean()
                  }
                  ignore(hk)
                  l.place(slot, 0.0, top + c.x)
                }
                _ => ()
              }
            }
          None => ()
        }
        laid.val = Some(r)
        // (where the one come is, its top in the window: what it is glided to)
        let came_top = match glide {
          Some((k, _)) =>
            match find(k, n - 1) {
              Some(i) => {
                let mut top = None
                for q in 0..<r.keys.length() {
                  if r.keys[q] == k {
                    top = Some(r.tops[q])
                  }
                }
                match top {
                  Some(t) => Some(t)
                  // (under what was laid out: as far under the last laid out as the rows between are tall)
                  None => Some(r.tops.last().unwrap_or(h) + r.heights.last().unwrap_or(0.0) + (i - r.last - 1).to_double() * mean())
                }
              }
              None => None
            }
          None => None
        }
        // (told once all of it is laid out, to what reads it there and after: what is in sight, whether it is at its
        // end, how far it is counted to be scrolled (what holds its rows moved by as much as they were placed for: what
        // its layout reads not moved), and a glide to what came, from this moment; nothing its layout reads changed)
        self.tree.once_laid_out(fn() { laid_n.set(@signals.untracked(fn() { laid_n.get() }) + 1) })
        let extent_now = extent()
        self.tree.once_laid_out(fn() { extent_said.set(extent_now) })
        self.tree.once_laid_out(fn() {
          let in_sight = []
          for q in 0..<r.keys.length() {
            if r.tops[q] + r.heights[q] > 0.0 && r.tops[q] < h {
              in_sight.push(r.keys[q])
            }
          }
          match shown {
            Some(sh) => if @signals.untracked(fn() { sh.get() }) != in_sight { sh.set(in_sight) }
            None => ()
          }
          if putting {
            put_laid.val = c.put_n
            // Do not clear a newer request that arrived before this result was published.
            if @signals.untracked(fn() { put_n.get() }) == c.put_n {
              put_at.set(None)
            }
          }
          if at_end && !@signals.untracked(fn() { follows.get() }) {
            follows.set(true)
          }
          match (glide, came_top) {
            (Some((_, from_top)), Some(top)) => {
              // (as far as the hand has it to go: by how far its top is under its cover, or to its end as counted)
              let to_top = top - c.cover
              let to_end = most - counted
              if from_top && to_top < to_end - 0.5 {
                s.glide_where(c.x + to_top, kept=false)
                follows.set(false)
              } else {
                s.glide_where(c.x + to_end, kept=false)
              }
            }
            _ => ()
          }
        })
      },
    )
    |> ignore
  })
  // (its rows in sight by their places, it put at one, how far past the first in sight's top it is, and where one is:
  // what a test reads and asks, Tree::list_rows)
  let key_now = fn(i : Int) -> K? {
    @signals.untracked(fn() {
      match indexed {
        Some(source) =>
          if i >= 0 && i < (source.snapshot)().1 { Some((source.key)(i)) } else { None }
        None => keys().get(i)
      }
    })
  }
  s.rows = Some((
    fn() {
      match laid.val {
        Some(r) => {
          let h = window_h.val
          let mut a = -1
          let mut b = -1
          for q in 0..<r.keys.length() {
            if r.tops[q] + r.heights[q] > 0.0 && r.tops[q] < h {
              if a < 0 {
                a = r.first + q
              }
              b = r.first + q
            }
          }
          (a, b)
        }
        None => (-1, -1)
      }
    },
    fn(i) {
      match key_now(i) {
        Some(k) => put_at.set(Some((k, 0.0)))
        None => ()
      }
    },
    fn() {
      match laid.val {
        Some(r) => {
          for q in 0..<r.keys.length() {
            if r.tops[q] + r.heights[q] > 0.0 {
              return -r.tops[q]
            }
          }
          0.0
        }
        None => 0.0
      }
    },
    fn(i) {
      key_now(i).bind(fn(k) { slots.get(k).map(fn(v) { v.rect() }) })
    },
  ))
  self.owns(fn() { s.rows = None }) |> ignore
  let forget = fn(k : K) {
    row_ids.remove(k)
    names.remove(k)
    match heights.get(k) {
      Some(h) => {
        known_sum.val = known_sum.val - h
        heights.remove(k)
      }
      None => ()
    }
    naturals.remove(k)
    rooms_laid.remove(k)
  }
  let forget_missing = fn(contains : (K) -> Bool) {
    for k in row_ids.keys().collect() {
      if !contains(k) { forget(k) }
    }
    for k in names.keys().collect() {
      if !contains(k) { forget(k) }
    }
    for k in heights.keys().collect() {
      if !contains(k) { forget(k) }
    }
  }
  match indexed {
    Some(source) => {
      let seen = Ref(@signals.untracked(fn() { (source.snapshot)().0 }))
      self.reacts(fn() { (source.snapshot)().0 }, fn(revision) {
        if revision != seen.val {
          match (source.removed_since)(seen.val) {
            Some(gone) => for k in gone { if !(source.contains)(k) { forget(k) } }
            None => forget_missing(source.contains)
          }
          seen.val = revision
        }
      })
    }
    None => self.reacts(keys, fn(now) {
      let here : Set[K] = Set::new()
      for k in now { here.add(k) }
      forget_missing(fn(k) { here.contains(k) })
    })
  }
  out
}

///|
fn dmax_i(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}
