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
  words : Int
  x : Double
  /// for a list that tells what came in sight (`seen`), while it goes on by itself (Scroll::goes_on): the logic's
  /// moment, what it tells is of (never a frame's drawn ahead of it: Tree::drawn_at is for a look), and how far it is
  /// scrolled then (Scroll::at's, its bar's count aside); at rest or telling none, -1 and `x`
  glide_at : Double
  logic_x : Double
  foot : Double
  put : (K, Double)?
  put_n : Int
  kept : Array[K]
  rooms : Same[(K, Double, Double) -> ListRoom]
  /// of the rows the list ends with (the last `tail`), those new to it that `fresh` says are, and of those whether each
  /// is read from its top; what covers its top
  fresh : Array[(K, Bool)]
  cover : Double
  /// what covers its foot (a composer over the rows under it): nothing is laid out by it; what is in sight is told by it
  foot_cover : Double
  tucked : K?
  /// the row last asked to be brought into sight, and how often one was
  reveal : (K?, Int)
  /// a node of a row to be kept in sight, what part of it and how far clear of what covers its top and its foot
  keep : (NodeId, (Double, Double)?, Double)?
  /// the row last asked to have a part of it it reports brought to the window's middle (`put_passage`): which, the
  /// name it reports the part by, how far down the window it may be before it is, and how often one was
  passage : (K, String, Double)?
  passage_n : Int
  /// said to follow its end again while short of it, not there yet (Scroll::to_end_told)
  to_end : Bool
  /// how many device pixels a point its rows are set on where they are (Tree::set_rows_grid; 0: anywhere)
  grid : Double
}

///|
impl[K : Eq] Eq for AnchoredIn[K] with equal(a, b) {
  // (the rows the same where their array is, or where it was made again holding the same: what pulls them makes it
  // anew each time it is read)
  (physical_equal(a.keys.v, b.keys.v) || a.keys.v == b.keys.v) &&
  a.indexed == b.indexed &&
  a.words == b.words &&
  a.x == b.x &&
  a.glide_at == b.glide_at &&
  a.logic_x == b.logic_x &&
  a.foot == b.foot &&
  a.put_n == b.put_n &&
  a.kept == b.kept &&
  a.rooms == b.rooms &&
  a.fresh == b.fresh &&
  a.cover == b.cover &&
  a.foot_cover == b.foot_cover &&
  a.tucked == b.tucked &&
  a.reveal == b.reveal &&
  a.keep == b.keep &&
  a.passage_n == b.passage_n &&
  a.to_end == b.to_end &&
  a.grid == b.grid
}

///|
/// How many of the rows it ends with are looked at for one come new among them.
let anchored_tail = 8

///|
/// How many rows under the first laid out a list asked to its end glides over (scrolls_anchored's end asked): further
/// off it is taken there at once.
let anchored_ask_rows = 64

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
/// its end; `shown` is told the keys in sight; `put` puts a row's top that far under the window's top; `put_passage` (a row, a name, a share) puts the part of the
/// row it reports by that name (Layout::report_span) in the window's middle where its middle is further down than that
/// share of the window, as it is laid out, held there as a put row is; `room` is a
/// row's room as its measured height changes (and the width the list is laid out at, in the same layout), `moving` says when rooms move; `kept_keys` rows made and laid out
/// though not in sight (a send's landing); `foot_room` room under the last row. `foot_cover` what covers its foot (a composer over
/// it): nothing laid out by it, told in `sighted` (what of the window is in sight). Both given by what holds it as it
/// measures it (Layout::measure's `foot`), those in place of these. An indexed source supplies its
/// keys by position instead of `keys`. `sighted` is told, once each frame is painted, the rows that came in sight or
/// within `ahead` of it, or were gone past on the way, since it was last laid out, and how wide the list is
/// laid out (what a row's pictures are decoded for: the same width the rows are drawn at): the same rows whether the frames
/// between were many or one (what asks for a row's pictures asks by it, never by the row being made); nothing once it
/// is let go before the frame is painted. `keep` a node in
/// one of its rows kept in sight (a card's field with the focus, the keyboard up), that part of it, that far clear of
/// what covers its top (`cover`) and its foot (`foot_cover`, or what is given it): in each layout, moved as little as
/// brings it between them, its top first where it does not fit; nothing moved where it is between them (as they
/// shrink); let go as it says none, as the node goes, and as the hand scrolls it, till it says another.
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
  rooms? : () -> (K, Double, Double) -> ListRoom,
  put_passage? : @signals.Signal[(K, String, Double)?],
  fresh? : (K) -> Bool = fn(_) { false },
  read_from_top? : (K) -> Bool = fn(_) { true },
  cover? : () -> Double = fn() { 0.0 },
  tucked? : () -> K? = fn() { None },
  kept_keys? : () -> Array[K],
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
  foot_cover? : () -> Double = fn() { 0.0 },
  indexed? : AnchoredSource[K],
  sighted? : (Sighted[K]) -> Unit,
  keep? : () -> (NodeId, (Double, Double)?, Double)? = fn() { None },
) -> View {
  self.scrolls_anchored_impl(
    s, keys, make, est~, from_end~, ahead~, slop?=slop, bar?=bar, follows~, shown?=shown,
    put?=put, put_passage?=put_passage, rooms?=rooms, fresh~, read_from_top~, cover~, tucked~, kept_keys?=kept_keys,
    bar_clear~, foot_room~, foot_cover~, indexed?=indexed, sighted?=sighted, keep~,
  )
}

///|
/// View::scrolls_anchored, and a page's windowed list (View::scrolls_window) laid out the same way: `fixed_estimate`
/// counts each row it has not measured as `est` (not as the mean of those it has), `on_grid` lays each row's room on
/// its host's pixels where it sets a page's list's rows on them (Tree::set_rows_grid).
fn[K : Hash + Eq] View::scrolls_anchored_impl(
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
  rooms? : () -> (K, Double, Double) -> ListRoom,
  put_passage? : @signals.Signal[(K, String, Double)?],
  fresh? : (K) -> Bool = fn(_) { false },
  read_from_top? : (K) -> Bool = fn(_) { true },
  cover? : () -> Double = fn() { 0.0 },
  tucked? : () -> K? = fn() { None },
  kept_keys? : () -> Array[K],
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
  foot_cover? : () -> Double = fn() { 0.0 },
  indexed? : AnchoredSource[K],
  fixed_estimate? : Bool = false,
  on_grid? : Bool = false,
  sighted? : (Sighted[K]) -> Unit,
  seen? : (Array[K]) -> Unit,
  keep? : () -> (NodeId, (Double, Double)?, Double)? = fn() { None },
) -> View {
  guard self.live() is Some(_) else { return self }
  let put_at = put.unwrap_or(@signals.signal(None))
  let passage_at = put_passage.unwrap_or(@signals.signal(None))
  // (how many times a part of a row was asked to the window's middle, and how many of those its layout has done)
  let passage_n = @signals.computed(fn(was : Int?) {
    let n = was.unwrap_or(0)
    if passage_at.get() is Some(_) { n + 1 } else { n }
  })
  let passage_laid = Ref(0)
  // (where it is: the row whose foot is nearest under the window's foot and how far under; none at its end)
  let anchor : Ref[ListAnchor[K]?] = Ref(None)
  // (how far it was scrolled as last laid out: what it moved by since is what the anchor moves by)
  let seen_x : Ref[Double?] = Ref(None)
  // (each row's height as last measured, by its key: for how tall all of it is counted, the bar's, and nothing else)
  let heights : Map[K, Double] = Map([])
  // (the rows in sight or within `ahead` of it as last laid out: what is sighted anew is what is not among them)
  let sighted_last : Set[K] = Set::new()
  // (the width they were told at: laid out at another, all in sight told again with it)
  let sighted_width : Ref[Double] = Ref(-1.0)
  // (where those in sight were told to be: told again as they move, the frame painted where they are)
  let sighted_rows : Ref[Array[(K, Double, Double)]] = Ref([])
  let sighted_h : Ref[Double] = Ref(-1.0)
  let sighted_cover : Ref[(Double, Double)] = Ref((-1.0, -1.0))
  // (the rows in sight as last told, and how many times it had been moved at once as last laid out: what came in sight
  // anew is what is not among them)
  let seen_last : Set[K] = Set::new()
  let seen_moves : Ref[Int] = Ref(s.moved_at_once)
  // (where the window it last told of is: its top, as drawn, how far from the row the next layout is laid out from
  // (that row's top from its start, its foot from its end; the list's first or last at its start or its end; one gone,
  // the row that layout puts in its place), kept so layout after layout. What it went across by itself since is what
  // lies between that window and the one in sight now as the list is laid out now, as far from that row as it was: as
  // that row went (the hand's way, held at an end, followed where it moved among the rest), rows come, gone, moved or
  // grown since among them as they are now, however many layouts came between, whatever moment each was drawn at. None
  // once it was moved at once or laid out from another row)
  let told_from : Ref[(ListAnchor[K]?, Double)?] = Ref(None)
  // (and what it went across by itself up to a moment something is done at (come due, an input's, an event's), laid
  // out at it before what is done then may let it go or read what it told: the same whether frames came on the way or
  // none; where it has gone on by itself since the moment it last told of, at a moment past that: at rest, none. Asked
  // so, what it reads of that moment taken anew as it is laid out then, the clock where it was drawn or not)
  let seen_laid_at = Ref(-1.0)
  let due_said : @signals.Signal[Double] = @signals.signal(-1.0)
  if seen is Some(_) {
    self.laid_before_due(fn(at) {
      match s.glides_till() {
        Some(end) if at > seen_laid_at.val && end > seen_laid_at.val => {
          due_said.set(at)
          true
        }
        _ => false
      }
    })
  }
  let known_sum = Ref(0.0)
  let measured_width = Ref(-1.0)
  let measured_words = Ref(-1)
  // Fixed estimates keep the measured differences in a prefix tree, so a scroll does not walk the history.
  let fixed_sums : Ref[Array[Double]] = Ref([])
  let fixed_delta = Ref(0.0)
  let fixed_keys : Ref[Array[K]?] = Ref(None)
  let fixed_revision : Ref[Int?] = Ref(None)
  let fixed_add = fn(index : Int, delta : Double) {
    fixed_delta.val += delta
    let mut i = index + 1
    while i < fixed_sums.val.length() {
      fixed_sums.val[i] += delta
      i += i & -i
    }
  }
  let fixed_above = fn(index : Int) {
    let mut i = index
    let mut sum = 0.0
    while i > 0 {
      sum += fixed_sums.val[i]
      i -= i & -i
    }
    index.to_double() * est + sum
  }
  let current_keys = @signals.computed(fn(_) { if indexed is Some(_) { [] } else { keys() } })
  let mean = fn() { if !fixed_estimate && heights.length() > 0 { known_sum.val / heights.length().to_double() } else { est } }
  let count = Ref(0)
  let laid : Ref[ListLaid[K]?] = Ref(None)
  // A parent may measure the list more than once before publishing a layout.
  let laid_version = Ref(0)
  let keep_moved = Ref(false)
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
  // (the node kept in sight as it was last laid out; whether the hand has scrolled it since: let go till another is
  // kept)
  let kept_as : Ref[NodeId?] = Ref(None)
  let keep_handed = Ref(false)
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
  let short_glide = Ref(false)
  let short_due : Ref[() -> Unit] = Ref(fn() { })
  self.owns(fn() { (short_due.val)() }) |> ignore
  // (each row's room as last laid out; and as told once all of it is laid out, a row's own: what draws it reads, told
  // again only where it came out otherwise, never because it was laid out again)
  let rooms_laid : Map[K, ListRoom] = Map([])
  let rooms_told : Map[K, @signals.Signal[ListRoom]] = Map([])
  let room_told = fn(k : K) {
    match rooms_told.get(k) {
      Some(s) => s
      None => {
        let s = @signals.signal(
          rooms_laid.get(k).unwrap_or(list_room(naturals.get(k).unwrap_or(0.0))),
          same=fn(a, b) { a == b },
        )
        rooms_told[k] = s
        s
      }
    }
  }
  let natural_room = fn(_k : K, h : Double, _w : Double) { list_room(h) }
  // Keep the captured room function until one of its own inputs changes. Clearing a completed placement request
  // must not make an otherwise identical room look new while the layout result is being published.
  let current_rooms = @signals.computed(fn(_) {
    match rooms {
      Some(f) => f()
      None => natural_room
    }
  })
  // (the row come to be read from its top, held under the cover as its room opens; whether a layout held it)
  let reading : Ref[K?] = Ref(None)
  let read_held = Ref(false)
  // (the row it was put at and how far under the window's top its top was put: kept there as the rows round it are
  // measured or open, till the hand moves it, it is put again or asked to its end; from its end its anchor is the row
  // at its foot, which moves what is over it as it grows)
  let pinned : Ref[(K, Double)?] = Ref(None)
  // (and how tall that row was as it was last laid out where it was put: out of sight there, laid out from again only
  // as it is measured otherwise)
  let pinned_tall : Ref[Double] = Ref(0.0)
  // (the hand scrolling it toward its start: no more at its end, from the hand's cause, before what it brings in is
  // measured)
  s.on_hand = fn(d) {
    if d != 0.0 {
      short_glide.val = false
      (short_due.val)()
      short_due.val = fn() { }
      reading.val = None
      pinned.val = None
      keep_handed.val = true
      // (a part asked to the middle not yet laid out: the hand has it now)
      passage_laid.val = @signals.untracked(fn() { passage_n.get() })
    }
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
  // (said to follow its end again while short of it (words sent while reading above: View::scrolls_window's
  // to_end): taken there, on to where its end is as rows come, till it is there or the hand takes it away)
  let end_asked = Ref(false)
  // (where it was last sent asked so: what it goes to as it is laid out again, sent again only where its end moved)
  let end_glided : Ref[Double?] = Ref(None)
  let was_follows = Ref(@signals.untracked(fn() { follows.get() }))
  self.reacts(fn() { follows.get() }, fn(now) {
    end_asked.val = from_end && now && !was_follows.val
    s.to_end.set(end_asked.val)
    end_glided.val = None
    if end_asked.val {
      reading.val = None
      pinned.val = None
    }
    was_follows.val = now
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
  // (the row one of its nodes is in)
  let row_holding = fn(id : NodeId) -> K? {
    let mut i = id.at
    while i >= 0 {
      match slot_keys.get(i) {
        Some(k) => return Some(k)
        None => ()
      }
      i = self.tree.nodes[i].parent
      if i == self.at {
        return None
      }
    }
    None
  }
  s.reveal = fn(id, part) {
    match row_holding(id) {
      Some(k) => {
        let (_, n) = @signals.untracked(fn() { reveal_said.get() })
        reveal_of.val = Some((id, part))
        reveal_said.set((Some(k), n + 1))
      }
      None => ()
    }
  }
  self.owns(fn() { s.bar_off = fn() { 0.0 }; s.rebase = fn() { }; s.reveal = fn(_, _) { }; s.reads_free = false }) |> ignore
  // (how tall all it holds is counted, as its layout last counted it: what its bar reads once it is laid out, no signal
  // read then)
  let foot_laid = Ref(0.0)
  // (as tall as it is counted to be at least as last laid out: as far as it is counted to be scrolled, its window, what
  // is laid out under that and the rows under those counted: never shorter than what is laid out from where it is)
  let extent_floor = Ref(0.0)
  let extent = fn() {
    let total = if fixed_estimate {
      count.val.to_double() * est + fixed_delta.val
    } else {
      count.val.to_double() * mean()
    }
    dmax(total + foot_laid.val, extent_floor.val)
  }
  // (told once laid out as how tall all it holds is counted comes out otherwise: what follows how far it can go
  // reads it, not its layout)
  let extent_said : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { (a - b).abs() < 0.5 })
  s.extent_told = fn() { extent_said.get() |> ignore }
  self.owns(fn() { s.extent_told = fn() { } }) |> ignore
  let out = self.scrolls(s, slop?=slop, bar?=bar, content_extent=extent, bar_clear~, fn(held) {
    held.height_share(Is(1.0)) |> ignore
    held.layout_box(
      By(fn() {
        let x = s.drawn(self.tree)
        // (telling what came in sight as it goes on by itself: the logic's moment, taken anew as it is asked to be laid
        // out at one (View::laid_before_due), and where it is then)
        let gliding = seen is Some(_) && s.goes_on()
        let logic = if gliding {
          due_said.get() |> ignore
          self.tree.logic_at()
        } else {
          -1.0
        }
        {
          keys: { v: current_keys.get() },
          indexed: indexed.map(fn(s) { (s.snapshot)() }),
          words: if fixed_estimate { self.words_redone() } else { 0 },
          x,
          glide_at: logic,
          logic_x: if gliding { s.where_at(logic) } else { x },
          foot: foot_room(),
          put: put_at.get(),
          put_n: put_n.get(),
          passage: passage_at.get(),
          passage_n: passage_n.get(),
          kept: match kept_keys {
            Some(f) => f()
            None => []
          },
          rooms: { v: current_rooms.get() },
          fresh: {
            let ks = current_keys.get()
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
          foot_cover: foot_cover(),
          tucked: tucked(),
          reveal: reveal_said.get(),
          keep: keep(),
          to_end: s.to_end.get(),
          grid: if on_grid { self.tree.rows_grid_said.get() } else { 0.0 },
        }
      }),
      fn(l, c) {
        let all = c.keys.v
        let n = c.indexed.map(fn(s) { s.1 }).unwrap_or(all.length())
        let mut reset_fixed = false
        if fixed_estimate && (l.width != measured_width.val || c.words != measured_words.val) {
          let keep : Set[K] = Set::new()
          match laid.val { Some(was) => for k in was.keys { keep.add(k) }; None => () }
          for k in heights.keys().collect() {
            if !keep.contains(k) {
              known_sum.val -= heights[k]
              heights.remove(k)
            }
          }
          measured_width.val = l.width
          measured_words.val = c.words
          reset_fixed = true
        }
        count.val = n
        // (the room under its last row and what covers its foot, as what holds it gave them as it measured it
        // (Layout::measure's `foot`), in place of its own `foot_room` and `foot_cover`)
        let (foot, foot_covered) = match l.given_foot() {
          Some(f) => f
          None => (c.foot, c.foot_cover)
        }
        foot_laid.val = foot
        let h = l.height - foot
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
        let fixed_changed = match c.indexed {
          Some((revision, _)) => fixed_revision.val != Some(revision)
          None => !(fixed_keys.val is Some(was) && physical_equal(was, all))
        }
        if fixed_estimate && (reset_fixed || fixed_changed) {
          fixed_sums.val = Array::make(n + 1, 0.0)
          fixed_delta.val = 0.0
          // (each row measured counted as it was measured: none gone through while none is, as it is first laid out)
          if !heights.is_empty() {
            self.tree.work.keys_swept = self.tree.work.keys_swept + n
            for i in 0..<n {
              match heights.get(key_at(i)) {
                Some(h) => fixed_add(i, h - est)
                None => ()
              }
            }
          }
          fixed_keys.val = Some(all)
          fixed_revision.val = c.indexed.map(fn(s) { s.0 })
        }
        // A list counted from its top keeps the first row in place if rows are inserted before it.
        if fixed_estimate && !from_end && anchor.val is None && n > 0 {
          match laid.val {
            Some(was) if was.first == 0 && was.keys.length() > 0 && key_at(0) != was.keys[0] =>
              match find(was.keys[0], 0) {
                Some(i) => anchor.val = Some({ key: was.keys[0], under: -was.tops[0], near: i })
                None => ()
              }
            _ => ()
          }
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
            let room_now = fn() { room_told(k).get() }
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
        // (rows made in this layout only to be measured, gone past: let go once it has placed what shows)
        let made_to_measure : Array[K] = []
        // (a row measured: as tall as it is, its room's height where its room moves)
        let measure = fn(i : Int) -> Double {
          let k = key_at(i)
          if !slots.contains(k) {
            made_to_measure.push(k)
          }
          let slot = slot_of(k)
          self.tree.nodes[slot.at].row_index = Some(i)
          // (as tall as whole pixels where its host sets a page's list's rows on them (Tree::set_rows_grid): its row's
          // room so, what it holds as tall as it is laid out in it)
          let on_grid = fn(x : Double) { if c.grid > 0.0 { (x * c.grid - 0.000001).ceil() / c.grid } else { x } }
          let measured = l.measure(slot, l.width).1
          let natural = on_grid(measured)
          naturals[k] = natural
          if fixed_estimate {
            fixed_add(i, natural - heights.get(k).unwrap_or(est))
          }
          match heights.get(k) {
            Some(was) => known_sum.val = known_sum.val - was + natural
            None => known_sum.val = known_sum.val + natural
          }
          heights[k] = natural
          let r = (c.rooms.v)(k, natural, l.width)
          rooms_laid[k] = r
          let room_h = on_grid(r.height)
          if (room_h - measured).abs() > 0.001 {
            l.measure(slot, l.width, height=room_h) |> ignore
          }
          room_h
        }
        // (shown nowhere yet: no room to show anything in, as a page pushed on is before it is laid out where it goes.
        // Nothing of this one kept as how it was laid out, no put taken: laid out where it shows, it lays its rows out
        // from where it was, what it was asked to put then put; what it had made kept made meanwhile)
        if h <= 0.0 {
          match laid.val {
            Some(was) => for k in was.keys { slot_of(k) |> ignore }
            None => ()
          }
          return
        }
        // (put at a row, its top that far under the window's top)
        let putting = c.put_n > put_laid.val && c.put is Some(_)
        match c.put {
          Some((k, off)) if putting =>
            match find(k, anchor.val.map(fn(a) { a.near }).unwrap_or(n - 1)) {
              Some(i) => {
                let hk = if from_end { measure(i) } else { 0.0 }
                anchor.val = Some({ key: k, under: if from_end { off + hk - h } else { -off }, near: i })
                pinned.val = if from_end { Some((k, off)) } else { None }
                pinned_tall.val = hk
              }
              None => ()
            }
          _ => ()
        }
        // (first laid out: what it walks to where it was scrolled before it was made, gone past at once)
        let first_laid = seen_x.val is None
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
        let mut short_move = 0.0
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
                        reading.val = if f.1 { Some(f.0) } else { None }
                        if fixed_estimate && was.first == 0 && was.tops[0] > 0.0 {
                          short_glide.val = true
                          let mut j = i
                          while j < n && short_move < was.tops[0] {
                            short_move += measure(j)
                            j += 1
                          }
                          short_move = dmin(was.tops[0], short_move)
                        }
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
        // (the rows the last of these layouts went past on the way: in sight on the way, sighted)
        let went_past : Array[K] = []
        // (and where it set out from, how far and with what room past its start: another row than where it was (one
        // brought into sight from out of it, put, held under what covers its top), what shows then got to at once,
        // nothing gone across on the way; the same laid out to where the hand was at the logic's moment, where it is
        // then)
        let laid_from : Ref[ListAnchor[K]?] = Ref(None)
        let laid_by = Ref(0.0)
        let laid_slack = Ref(0.0)
        let lay = fn(from : ListAnchor[K]?, by : Double) {
          went_past.clear()
          laid_from.val = from
          laid_by.val = by
          laid_slack.val = if from_end { if short_glide.val { h } else { 0.0 } } else { slack }
          let past = fn(i : Int) { went_past.push(key_at(i)) }
          if from_end {
            list_laid_from_end(n, key_of, find, measure, from, h, by~, ahead~, known~, slack=laid_slack.val, went_past=past)
          } else {
            list_laid_from_top(n, key_of, find, measure, from, h, by~, ahead~, known~, slack=laid_slack.val, went_past=past)
          }
        }
        let from = anchor.val
        let mut r = lay(from, by)
        // (the part of node `id` in row `k` (all of it where `within` says none), where its row is laid out now: its top
        // and its foot from the row's; the row's own where it is not in it)
        let part_of = fn(k : K, id : NodeId, within : (Double, Double)?, row_h : Double) -> (Double, Double) {
          guard self.tree.alive_id(id) else { return (0.0, row_h) }
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
        // (a row asked to be brought into sight since it was last laid out: where it is laid out now, measured as it is,
        // moved as little as brings the part asked of it in (as shows has a column do), laid out again so; one not
        // laid out now in sight or near it: its top at the window's top, or its foot at its foot)
        match c.reveal {
          (Some(k), asked) if asked > revealed.val => {
            revealed.val = asked
            let part_in = fn(row_h : Double) -> (Double, Double) {
              match reveal_of.val {
                Some((id, within)) => part_of(k, id, within, row_h)
                None => (0.0, row_h)
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
        // (one come to be read from its top, at its end: kept there while its room opens till its top reaches what
        // covers the list's top, its top held under that from then (Follow.kt), the end followed no more)
        match reading.val {
          Some(k) if from_end =>
            for q in 0..<r.keys.length() {
              if r.keys[q] == k {
                if r.tops[q] < c.cover - 0.5 {
                  match find(k, r.first + q) {
                    Some(i) => {
                      r = lay(Some({ key: k, under: c.cover + r.heights[q] - h, near: i }), 0.0)
                      read_held.val = true
                    }
                    None => ()
                  }
                }
                break
              }
            }
          _ => ()
        }
        // (put at a row and nothing moved it since: its top where it was put, whatever came to be measured round it)
        match pinned.val {
          Some((k, off)) if glide is None && !read_held.val =>
            match r.keys.search(k) {
              Some(q) => {
                pinned_tall.val = r.heights[q]
                if (r.tops[q] - off).abs() > 0.01 {
                  match find(k, r.first + q) {
                    Some(i) => r = lay(Some({ key: k, under: off + r.heights[q] - h, near: i }), 0.0)
                    None => ()
                  }
                }
              }
              // (out of sight where it was put, kept made there (below), so that one that says how tall it is only after
              // it is first laid out (an old view's island) can say it: measured otherwise than it was laid out there,
              // laid out from it again; the rows between it and those in sight not gone through)
              None =>
                match find(k, r.first) {
                  Some(i) => {
                    let hk = measure(i)
                    if (hk - pinned_tall.val).abs() > 0.01 {
                      pinned_tall.val = hk
                      r = lay(Some({ key: k, under: off + hk - h, near: i }), 0.0)
                    }
                  }
                  None => ()
                }
            }
          _ => if glide is Some(_) || read_held.val { pinned.val = None }
        }
        // (a node kept in sight, in each layout: its part between what covers the window's top and its foot (from the
        // window's foot, the room under its rows or not), `room` clear of each, moved as little as brings it there, its
        // top first where it does not fit; what was put or held to be read let go as it is; none moved as the hand has
        // it)
        match c.keep {
          Some((id, within, room)) if self.tree.alive_id(id) => {
            if kept_as.val != Some(id) {
              kept_as.val = Some(id)
              keep_handed.val = false
            }
            if !keep_handed.val {
              match row_holding(id) {
                Some(k) =>
                  for q in 0..<r.keys.length() {
                    if r.keys[q] == k {
                      let (pa, pb) = part_of(k, id, within, r.heights[q])
                      let (top, foot) = (r.tops[q] + pa, r.tops[q] + pb)
                      let (lo, hi) = (c.cover + room, l.height - foot_covered - room)
                      let down = if top < lo { lo - top } else if foot > hi { -dmin(foot - hi, top - lo) } else { 0.0 }
                      if down != 0.0 {
                        match find(k, r.first + q) {
                          Some(i) => {
                            let top = r.tops[q] + down
                            r = lay(Some({ key: k, under: if from_end { top + r.heights[q] - h } else { -top }, near: i }), 0.0)
                            keep_moved.val = true
                            pinned.val = None
                            reading.val = None
                          }
                          // (a row laid out now is among its rows)
                          None => abort("scrolls_anchored: a row laid out not found among its rows")
                        }
                      }
                      break
                    }
                  }
                None => ()
              }
            }
          }
          _ => kept_as.val = None
        }
        // (a part of a row asked to the window's middle (`put_passage`): the row in sight first where it is not, its top at
        // the window's top; then where the part it reports by that name (Layout::report_span) is as it is laid out now:
        // its middle further down the window than `within` of it, the row put so that middle is the window's, kept there
        // as a put row is; else left where it is)
        let mut passage_put = false
        match c.passage {
          Some((k, name, within)) if c.passage_n > passage_laid.val => {
            let q_of = fn() {
              let mut q = -1
              for j in 0..<r.keys.length() {
                if r.keys[j] == k {
                  q = j
                }
              }
              q
            }
            if q_of() < 0 {
              match find(k, r.first) {
                Some(i) => r = lay(Some({ key: k, under: if from_end { measure(i) - h } else { 0.0 }, near: i }), 0.0)
                None => ()
              }
            }
            let q = q_of()
            if q >= 0 {
              passage_laid.val = c.passage_n
              passage_put = true
              match slots.get(k).bind(fn(row) { l.reported_span(row, name) }) {
                Some((y0, y1)) if r.tops[q] + (y0 + y1) / 2.0 > within * h =>
                  match find(k, r.first + q) {
                    Some(i) => {
                      let top = h / 2.0 - (y0 + y1) / 2.0
                      let hk = r.heights[q]
                      r = lay(Some({ key: k, under: if from_end { top + hk - h } else { -top }, near: i }), 0.0)
                      pinned.val = if from_end { Some((k, top)) } else { None }
                      pinned_tall.val = hk
                    }
                    None => ()
                  }
                _ => ()
              }
            }
          }
          _ => ()
        }
        anchor.val = r.anchor
        // (how far it is counted to be scrolled among all it holds, the bar's, as laid out now)
        let at_end = from_end && r.at_end
        if at_end && short_move == 0.0 { short_glide.val = false }
        // (not at its end: as far as it is counted to be scrolled, and what is under the window counted from what is laid
        // out (its last row's foot under the window, the rows under it as tall as one is counted to be), its extent no
        // shorter than that: else, the rows laid out taller than its count, how far it is counted to be scrolled is its
        // most, a drag toward its end held there while its end is not laid out (0.1.7336: 往下滑不了))
        extent_floor.val = 0.0
        if !at_end && r.first > 0 && r.keys.length() > 0 {
          let over = if fixed_estimate { fixed_above(r.first) } else { r.first.to_double() * mean() }
          let at = over - r.tops[0]
          let foot = r.tops[r.keys.length() - 1] + r.heights[r.keys.length() - 1]
          let under = dmax(0.0, foot - h) + (n - 1 - r.last).to_double() * mean()
          extent_floor.val = at + h + under + foot_laid.val
        }
        let most = dmax(0.0, extent() - foot_laid.val - h)
        let counted = if at_end || (!from_end && r.at_start) {
          most
        } else if r.first == 0 {
          -r.tops.get(0).unwrap_or(0.0)
        } else {
          let over = if fixed_estimate {
            fixed_above(r.first)
          } else { r.first.to_double() * mean() }
          dmin(most, over - r.tops.get(0).unwrap_or(0.0))
        }
        bar_off.val = counted - c.x
        // (placed where they are in the window: the column holds them moved by how far it is scrolled)
        for q in 0..<r.keys.length() {
          l.place(slot_of(r.keys[q]), 0.0, r.tops[q] + c.x)
        }
        // (the row it is put at kept too while it is put there, out of sight)
        let put_kept = match pinned.val {
          Some((k, _)) if !r.keys.contains(k) && !c.kept.contains(k) => Some(k)
          _ => None
        }
        // (and those kept out of sight, as far off as they are counted to be)
        match Some(match put_kept { Some(k) => [..c.kept, k]; None => c.kept }) {
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
        // (what came in sight or within `ahead` of it, or was gone past on the way, since the last layout: sighted, told
        // once the frame is painted, whether the frames between were many or one)
        match sighted {
          Some(tell) => {
            let now : Set[K] = Set::new()
            let fresh_in : Array[K] = []
            let widened = l.width != sighted_width.val
            sighted_width.val = l.width
            for k in went_past.iter().concat(r.keys.iter()) {
              if !now.contains(k) {
                now.add(k)
                if widened || !sighted_last.contains(k) {
                  fresh_in.push(k)
                }
              }
            }
            // (out of it now: what was in it, and what was only gone past on the way)
            let in_now : Set[K] = Set::new()
            for k in r.keys {
              in_now.add(k)
            }
            let left : Array[K] = []
            for k in sighted_last.iter().concat(went_past.iter()) {
              if !in_now.contains(k) && !left.contains(k) {
                left.push(k)
              }
            }
            sighted_last.clear()
            for k in r.keys {
              sighted_last.add(k)
            }
            let rows = Array::makei(r.keys.length(), fn(q) { (r.keys[q], r.tops[q], r.heights[q]) })
            let covered = (c.cover, foot_covered)
            let moved = rows != sighted_rows.val || h != sighted_h.val || covered != sighted_cover.val
            sighted_cover.val = covered
            sighted_rows.val = rows
            sighted_h.val = h
            if !fresh_in.is_empty() || !left.is_empty() || moved {
              let s : Sighted[K] = { came: fresh_in, left, width: l.width, rows, height: h, cover: covered }
              // (to the list still there: one let go before the frame is painted (laid out at an input's moment, the
              // frame after another input) tells nothing)
              self.tree.said_after_paint(fn() { if held.live() is Some(_) { tell(s) } })
            }
          }
          None => ()
        }
        // (what came in sight since it last told (laid out at an input's moment, an event's, one come due, or a frame's):
        // in sight now, or gone across on the way as it went on by itself (a fling, a wheel's notches easing in, a glide
        // to its end): each row between the window it last told of and the one in sight now, as the list is laid out
        // now, whether the layouts between were many or one; not what it went past as it was moved at once (a wheel's
        // turn, a drag's move, its bar, put, a row brought into sight from out of it, laid out from another row) or as
        // it was first laid out where it was scrolled to, made only to be measured. Of the logic's moment, never of a
        // frame's drawn ahead of it (what a press would stop it short of): where the list is laid out then, from where
        // this layout set out. Seen, told as this layout is done, whether a frame is painted before what comes next or
        // not (Tree::said_after_laid); of a moment before the one it last told of (a change said at a moment gone),
        // nothing told, what it told kept)
        match seen {
          Some(tell) if r.keys.length() > 0 => {
            let count = r.keys.length()
            let tall = fn(i : Int) {
              self.tree.work.seen_walked = self.tree.work.seen_walked + 1
              match known(i) {
                Some(v) => v
                None => {
                  self.tree.work.seen_measured = self.tree.work.seen_measured + 1
                  measure(i)
                }
              }
            }
            // (each row's top and how tall it is in this layout, as drawn: those laid out as laid out, those over and
            // under them from them on as tall as they were measured, each gone through once)
            let over : Array[(Double, Double)] = []
            let under : Array[(Double, Double)] = []
            let place = fn(i : Int) -> (Double, Double) {
              if i < r.first {
                while over.length() < r.first - i {
                  let j = r.first - 1 - over.length()
                  let foot = if over.is_empty() { r.tops[0] } else { over[over.length() - 1].0 }
                  let tall_j = tall(j)
                  over.push((foot - tall_j, tall_j))
                }
                over[r.first - 1 - i]
              } else if i > r.last {
                while under.length() < i - r.last {
                  let j = r.last + 1 + under.length()
                  let top = if under.is_empty() {
                    r.tops[count - 1] + r.heights[count - 1]
                  } else {
                    under[under.length() - 1].0 + under[under.length() - 1].1
                  }
                  under.push((top, tall(j)))
                }
                under[i - r.last - 1]
              } else {
                (r.tops[i - r.first], r.heights[i - r.first])
              }
            }
            // (where a row it is laid out from is in this layout: its top from its start, its foot from its end; one
            // gone, the row the layout put in its place, near where it was (list_laid_from_end's); the list's first or
            // last laid out from neither, at its start or its end)
            let held_at = fn(a : ListAnchor[K]?) -> Double {
              let i = match a {
                Some(a) =>
                  match find(a.key, a.near) {
                    Some(i) => i
                    None => if a.near < 0 { 0 } else if a.near >= n { n - 1 } else { a.near }
                  }
                None => if from_end { n - 1 } else { 0 }
              }
              let (top, tall_i) = place(i)
              if from_end {
                top + tall_i
              } else {
                top
              }
            }
            // (where the window it last told of is in this layout, as drawn: as far from the row this one is laid out
            // from as it was from that row then, so as that row went (the hand's way, held at an end, followed where
            // it moved among the rest, the one put in its place where it is gone); nowhere once it was moved at once,
            // first laid out, or laid out from another row or by another way)
            let at_once = first_laid ||
              laid_from.val != from ||
              laid_by.val != by ||
              s.moved_at_once != seen_moves.val
            seen_moves.val = s.moved_at_once
            let mut told_top = match told_from.val {
              Some((a, off)) if !at_once && a == from => Some(held_at(from) + off)
              _ => None
            }
            if c.glide_at < 0.0 || c.glide_at >= seen_laid_at.val {
              seen_laid_at.val = c.glide_at
              // (the window at the logic's moment, its top in this layout's terms, as drawn: the list laid out from
              // where this layout set out, as far as the hand had gone by then, held at its start or its end as this
              // layout is (a frame drawn ahead held there while the logic is short of it), the rows this layout has as
              // tall as it has them, those past them as tall as they were measured)
              let shift = c.x - c.logic_x
              let then_top = if shift == 0.0 {
                0.0
              } else {
                let laid_tall = fn(i : Int) -> Double? {
                  if i >= r.first && i <= r.last {
                    Some(r.heights[i - r.first])
                  } else {
                    None
                  }
                }
                let tall_then = fn(i : Int) {
                  match laid_tall(i) {
                    Some(v) => v
                    None => tall(i)
                  }
                }
                // (as this layout was laid out, by as far as the hand had gone at the logic's moment)
                let from = laid_from.val
                let by = if from_end { laid_by.val + shift } else { laid_by.val - shift }
                let slack = laid_slack.val
                let then = if from_end {
                  list_laid_from_end(n, key_of, find, tall_then, from, h, by~, known=laid_tall, slack~)
                } else {
                  list_laid_from_top(n, key_of, find, tall_then, from, h, by~, known=laid_tall, slack~)
                }
                place(then.first).0 - then.tops[0]
              }
              // (that window's top at the logic's moment, in its terms: what lies from there to it, and it, is what it
              // can have come to since)
              let told_at = told_top.map(fn(y) { y - then_top })
              let (lo, hi) = match told_at {
                Some(t) => (dmin(t, 0.0), dmax(t + h, h))
                None => (0.0, h)
              }
              // (those rows from the first down, each with its top and how tall it is then)
              let rows : Array[(K, Double, Double)] = []
              let ups : Array[(K, Double, Double)] = []
              let mut i = r.first - 1
              let mut edge = r.tops[0] - then_top
              while i >= 0 && edge > lo {
                let (top, tall_i) = place(i)
                if top - then_top < hi {
                  ups.push((key_at(i), top - then_top, tall_i))
                }
                edge = top - then_top
                i = i - 1
              }
              ups.rev_in_place()
              rows.append(ups)
              for q in 0..<count {
                let top = r.tops[q] - then_top
                if top + r.heights[q] > lo && top < hi {
                  rows.push((r.keys[q], top, r.heights[q]))
                }
              }
              let mut i = r.last + 1
              let mut top = r.tops[count - 1] + r.heights[count - 1] - then_top
              while i < n && top < hi {
                let (_, tall_i) = place(i)
                if top + tall_i > lo {
                  rows.push((key_at(i), top, tall_i))
                }
                top = top + tall_i
                i = i + 1
              }
              // (what came, each once: first what that window has now that it did not show then (rows come into it, or
              // moved into it, as it was changed, there as the list shows it now), from its top down; then what lies on
              // the way from it, in the order the window's leading edge went over it, down the column where it went
              // toward its end, up it where it went toward its start; not those it showed then and still has there, a
              // row moved out of it and come again counted anew)
              let came : Array[K] = []
              let told : Set[K] = Set::new()
              let in_told = fn(row : (K, Double, Double)) {
                match told_at {
                  Some(t) => row.1 + row.2 > t && row.1 < t + h
                  None => row.1 + row.2 > 0.0 && row.1 < h
                }
              }
              let came_in = fn(row : (K, Double, Double)) {
                let k = row.0
                if !told.contains(k) && !(seen_last.contains(k) && in_told(row)) {
                  told.add(k)
                  came.push(k)
                }
              }
              for row in rows {
                if in_told(row) {
                  came_in(row)
                }
              }
              match told_at {
                Some(t) if t > 0.0 =>
                  for j = rows.length() - 1; j >= 0; j = j - 1 {
                    if !in_told(rows[j]) {
                      came_in(rows[j])
                    }
                  }
                _ =>
                  for row in rows {
                    if !in_told(row) {
                      came_in(row)
                    }
                  }
              }
              seen_last.clear()
              for row in rows {
                if row.1 + row.2 > 0.0 && row.1 < h {
                  seen_last.add(row.0)
                }
              }
              told_top = Some(then_top)
              if !came.is_empty() {
                // (to the list still there: one let go before its turn (by a telling before it, laying out at once and
                // letting it go) tells nothing)
                self.tree.said_after_laid(fn() { if held.live() is Some(_) { tell(came) } })
              }
            }
            // (kept as far from the row the next layout is laid out from as it is now)
            told_from.val = told_top.map(fn(y) { (r.anchor, y - held_at(r.anchor)) })
          }
          // (nothing laid out: nothing in sight, the window it told of nowhere)
          Some(_) => {
            seen_last.clear()
            told_from.val = None
          }
          None => ()
        }
        // (a row a scroll only went past, measured for how far it went: not kept, a cache of the picture of what shows)
        for k in made_to_measure {
          if !r.keys.contains(k) && !c.kept.contains(k) && put_kept != Some(k) {
            l.let_go(name_of(k))
          }
        }
        laid.val = Some(r)
        laid_version.val += 1
        let version = laid_version.val
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
        // The distance from the laid-out tail to the window's foot is local geometry. Subtracting the list's
        // estimated scroll position from its estimated extent instead treats every visible row as an average
        // row; one tall measured row elsewhere can then make a short arrival look taller than the window.
        let mut tail_end = r.tops.last().unwrap_or(h) + r.heights.last().unwrap_or(0.0)
        if glide is Some(_) {
          for i in (r.last + 1)..<n {
            let k = key_at(i)
            let natural = heights.get(k).unwrap_or(mean())
            tail_end += (c.rooms.v)(k, natural, l.width).height
          }
        }
        let to_tail = dmax(0.0, tail_end - h)
        // (asked to its end: where its end will be once the rooms opening now are open, each row as tall as it is (or is
        // counted to be): one glide there, not one to where the end is this frame and another after)
        // (no more than so many rows under its first laid out: further, it is taken to its end at once, as to_end does)
        let to_end_open = if end_asked.val && n - r.first <= anchored_ask_rows {
          let mut foot = r.tops.get(0).unwrap_or(h)
          for i in r.first..<n {
            foot += heights.get(key_at(i)).unwrap_or(mean())
          }
          dmax(0.0, foot - h)
        } else {
          to_tail
        }
        // (told once all of it is laid out, to what reads it there and after: what is in sight, whether it is at its
        // end, how far it is counted to be scrolled (what holds its rows moved by as much as they were placed for: what
        // its layout reads not moved), and a glide to what came, from this moment; nothing its layout reads changed)
        self.tree.once_laid_out(fn() {
          for k, room in rooms_laid {
            match rooms_told.get(k) {
              Some(s) => s.set(room)
              None => ()
            }
          }
        })
        let extent_now = extent()
        self.tree.once_laid_out(fn() { extent_said.set(extent_now) })
        // (where its last row's foot is below where it shows to, laid out; as far as can be where it is not:
        // Scroll::end_below_told)
        let last_q = r.keys.length() - 1
        // (its last row laid out this time: how far its foot is below where it shows; not laid out, as far as can be,
        // however near rows measured before would put it)
        let below = if n > 0 && last_q >= 0 && r.last == n - 1 {
          r.tops[last_q] + r.heights[last_q] - h
        } else {
          @double.infinity
        }
        self.tree.once_laid_out(fn() { s.end_below.set(below) })
        // (and to what holds it, as it measures it in this same layout: Layout::reported(list, "end_below"))
        l.report("end_below", below)
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
          if passage_put && @signals.untracked(fn() { passage_n.get() }) == c.passage_n {
            passage_at.set(None)
          }
          if read_held.val {
            read_held.val = false
            if @signals.untracked(fn() { follows.get() }) {
              follows.set(false)
            }
          }
          if self.alive() && laid_version.val == version {
            if at_end && !@signals.untracked(fn() { follows.get() }) {
              follows.set(true)
            } else if from_end && keep_moved.val && !at_end && @signals.untracked(fn() { follows.get() }) {
              follows.set(false)
            }
            keep_moved.val = false
          }
          match (glide, came_top) {
            (Some((_, from_top)), Some(top)) if short_move > 0.0 => {
              let to_end = short_move + most
              let to_top = top - c.cover
              let by = if from_top && to_top < to_end - 0.5 { dmax(0.0, to_top) } else { to_end }
              if from_top && to_top < to_end - 0.5 { follows.set(false) }
              let at = self.cause_at()
              (short_due.val)()
              short_due.val = self.at_moment(at, fn() {
                short_due.val = fn() { }
                s.glide_where(c.x + by, kept=false)
              })
            }
            (Some((_, from_top)), Some(top)) => {
              // (as far as the hand has it to go: by how far its top is under its cover, or to its end as counted)
              let to_top = top - c.cover
              let to_end = to_tail
              if from_top && to_top < to_end - 0.5 {
                s.glide_where(c.x + to_top, kept=false)
                follows.set(false)
              } else {
                s.glide_where(c.x + to_end, kept=false)
              }
            }
            // (asked to its end and short of it, nothing taking it there: what was its end as it was sent there is no
            // more (a row come since, its room opened), so on to where its end is now)
            _ =>
              if at_end || !@signals.untracked(fn() { follows.get() }) {
                end_asked.val = false
                s.to_end.set(false)
              } else if end_asked.val && to_end_open > 0.5 {
                let to = c.x + to_end_open
                match end_glided.val {
                  // (glided there already and at rest short of it: as near as it comes, asked no more)
                  Some(was) if s.glides_till() is None && (was - to).abs() < 1.0 => {
                    end_asked.val = false
                    s.to_end.set(false)
                  }
                  // (on its way there: where its end is now only where that moved)
                  Some(was) if (was - to).abs() < 1.0 => ()
                  _ => {
                    end_glided.val = Some(to)
                    s.glide_where(to, kept=false)
                  }
                }
              }
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
    rooms_told.remove(k)
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
      // (none named, made or measured yet (its first keys): none to forget, none gone through)
      if row_ids.is_empty() && names.is_empty() && heights.is_empty() {
        return
      }
      self.tree.work.keys_swept = self.tree.work.keys_swept + now.length()
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

///|
/// What a list laid out from its anchor tells as a frame is painted of the rows in sight or within `ahead` of it
/// (View::scrolls_anchored's `sighted`): those that came in it since it was last laid out, or were gone past on the way
/// (all in it again when it is laid out at another width), those that left it (and those only gone past), the width its
/// rows are laid out at, and where each in it is: told as any of these changes, as the frame that laid them so is
/// painted. What holds a row's pictures keeps which are in it by these (came, then left) and asks by
/// them, and by the row's data as it changes, never by a row being made or where it was laid out.
pub(all) struct Sighted[K] {
  came : Array[K]
  left : Array[K]
  width : Double
  /// those in sight or within `ahead` of it as this frame laid them out, from the first: each one's key, its top under
  /// the list's window's top and its height (what reads how far one is read, the one at the top or the foot, where it
  /// is scrolled to, as it is drawn: read here, never followed)
  rows : Array[(K, Double, Double)]
  /// how tall the list's window is
  height : Double
  /// how much of its window is covered at its top and at its foot (`cover`, `foot_cover`): what of it is in sight
  cover : (Double, Double)
}
