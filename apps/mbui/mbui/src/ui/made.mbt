// What is made once (docs/retained.md, the way there's 2): a node made by what it is filled with (`fill`, a call of
// Ctx::box or Ctx::text that makes that one node and nothing in it), what it holds made the same way, each followed by
// a watch of its own (mbui/signals' Watch). Each frame what is made is put among the frame's nodes where its holder is
// built (Ctx::made), each node as it was made where nothing its fill read changed, filled anew in its place where
// something did; what it holds that comes and goes (made_each, made_show) is made as it comes and let go as it goes,
// what stays kept. What a press on it does is said once (Made::on_press) and done as the press is let go, not read
// as the frame is built. What the frame is told of a node (its marks, its focus, what is read out, its looks, its
// words: the way there's 1) is the node's, so a node put back as it was says it as it did.
//
// A frame built whole (the Tester's check, a pass built again) fills every node anew: what was kept and what is
// filled anew must come out the same, as rows kept as their nodes are held to (kept_nodes.mbt).

///|
/// A node made once (made_box, made_text): what fills it, what it holds, the node as last filled, the watch of what
/// its fill read, what a press on it does.
pub struct Made {
  priv fill : (Ctx) -> Unit
  priv kids : MadeKids
  priv mut node : Node?
  priv watch : @signals.Watch
  priv mut on_press : (() -> Unit)?
  /// the list's row or the part kept as its nodes it was last put in, if it was (kept_nodes.mbt): told with it
  priv held : Ref[RowNodes?]
  /// what it is where it is built the old way (made_island): its name, what it is built from besides what it reads
  priv island : (String, () -> String, Bool)?
  /// built the old way each time it is put, kept as nothing (made_old)
  priv old : Bool
}

///|
/// What a node made holds: the same always, or what a run of `make` makes (made_each, made_show), made anew as what
/// that read changes.
priv enum MadeKids {
  Kept(Array[Made])
  Made(MadeChanging)
}

///|
priv struct MadeChanging {
  make : () -> Array[Made]
  watch : @signals.Watch
  mut now : Array[Made]
}

///|
/// A watch of what a made node's fill, or what makes what it holds, read: told, the frame is built again for it (as
/// for a list's row kept as its nodes: kept_nodes.mbt), between frames one owed; and the row or part kept as its nodes
/// it is in (`held`), built again with it, as though it read it itself.
fn made_watch(held : Ref[RowNodes?]) -> @signals.Watch {
  @signals.watch(fn() {
    match held.val {
      Some(rn) => rn.watch.touch()
      None => ()
    }
    nodes_run.told = true
    if !frame_running.val {
      h_frame_owed()
    }
  })
}

///|
/// A node made by `fill` (a call of Ctx::box with a body that makes nothing, or of Ctx::text: what it reads followed,
/// filled anew in its place as any of it changes), holding `kids`.
pub fn made_box(fill : (Ctx) -> Unit, kids? : Array[Made] = []) -> Made {
  let held = Ref(None)
  { fill, kids: Kept(kids), node: None, watch: made_watch(held), on_press: None, held, island: None, old: false }
}

///|
/// What `body` builds the old way (Ctx::box and the rest, each frame it is built), in a box of its own filling what
/// holds it, kept as its nodes by a watch of its own (Ctx::kept_as_nodes): built again only as what it read changes or
/// what it is built from besides (`key`, worked out where it is put) does. Made once where it is (`name`), whatever
/// else of the frame is built anew: what is made once holds it, and what it reads it reads itself, never what was
/// handed it as it was made (docs/retained.md, the way there's 3: the old view as an island). `read_out`: what reads
/// the widgets reads it.
pub fn made_island(name : String, key : () -> String, body : (Ctx) -> Unit, read_out? : Bool = true) -> Made {
  let held = Ref(None)
  {
    fill: body,
    kids: Kept([]),
    node: None,
    watch: made_watch(held),
    on_press: None,
    held,
    island: Some((name, key, read_out)),
    old: false,
  }
}

///|
/// What `body` builds the old way (Ctx::box and the rest), built each time it is put, kept as nothing: the frame's
/// watch follows what it reads, as it follows the rest of the frame built the old way (docs/retained.md, the way
/// there's 3: the old view in what is made once, its islands kept as they are where it is the frame's).
pub fn made_old(body : (Ctx) -> Unit) -> Made {
  let held = Ref(None)
  {
    fill: body,
    kids: Kept([]),
    node: None,
    watch: made_watch(held),
    on_press: None,
    held,
    island: None,
    old: true,
  }
}

///|
/// A node made by `fill`, holding what `kids` makes (made_each, made_show), made anew as what it read changes.
pub fn made_holding(fill : (Ctx) -> Unit, kids : () -> Array[Made]) -> Made {
  let held = Ref(None)
  {
    fill,
    kids: Made({ make: kids, watch: made_watch(held), now: [] }),
    node: None,
    watch: made_watch(held),
    on_press: None,
    held,
    island: None,
    old: false,
  }
}

///|
/// Pressed (a tap, a click, Enter or Space where it takes the focus) and let go on it: `f`, as it is let go, outside
/// any build. Its fill gives it an id.
pub fn Made::on_press(self : Made, f : () -> Unit) -> Made {
  self.on_press = Some(f)
  self
}

///|
/// What `items` holds, a node each made by `row` from its item as a signal of its own: made as its key (`key`) comes,
/// kept while it stays (its item set anew there: what reads it filled anew), let go as it goes; in `items`' order.
pub fn[T, K : Hash + Eq] made_each(
  items : () -> Array[T],
  key : (T) -> K,
  row : (@signals.Signal[T]) -> Made,
) -> () -> Array[Made] {
  let kept : Map[K, (@signals.Signal[T], Made)] = {}
  fn() {
    let now = items()
    let seen : Map[K, Bool] = {}
    let out = []
    @signals.untracked(fn() {
      for item in now {
        let k = key(item)
        seen[k] = true
        match kept.get(k) {
          Some((s, m)) => {
            s.set(item)
            out.push(m)
          }
          None => {
            let s = @signals.signal(item)
            let m = row(s)
            kept[k] = (s, m)
            out.push(m)
          }
        }
      }
    })
    let gone = []
    kept.each(fn(k, v) { if !seen.contains(k) { gone.push((k, v.1)) } })
    for g in gone {
      kept.remove(g.0)
      g.1.let_go()
    }
    out
  }
}

///|
/// What `then` makes while `when` holds (made once as it comes to hold, let go as it stops), else nothing.
pub fn made_show(when : () -> Bool, then : () -> Made) -> () -> Array[Made] {
  let shown : Ref[Made?] = Ref(None)
  fn() {
    if when() {
      match shown.val {
        Some(m) => [m]
        None => {
          let m = @signals.untracked(then)
          shown.val = Some(m)
          [m]
        }
      }
    } else {
      match shown.val {
        Some(m) => {
          m.let_go()
          shown.val = None
        }
        None => ()
      }
      []
    }
  }
}

///|
/// What `make` makes of which of its cases `which` says holds (Solid's Switch): made once as that case comes, let go as
/// another does, kept while it stays.
pub fn[K : Eq] made_pick(which : () -> K, make : (K) -> Made) -> () -> Array[Made] {
  let shown : Ref[(K, Made)?] = Ref(None)
  fn() {
    let k = which()
    match shown.val {
      Some((was, m)) if was == k => [m]
      was => {
        match was {
          Some((_, m)) => m.let_go()
          None => ()
        }
        let m = @signals.untracked(fn() { make(k) })
        shown.val = Some((k, m))
        [m]
      }
    }
  }
}

///|
/// Let go: it and what it holds follow nothing more.
fn Made::let_go(self : Made) -> Unit {
  self.watch.stop()
  match self.node {
    Some(n) if n.id != 0 && self.on_press is Some(_) => made_presses.remove(n.id)
    _ => ()
  }
  self.node = None
  match self.kids {
    Kept(ks) =>
      for k in ks {
        k.let_go()
      }
    Made(ch) => {
      ch.watch.stop()
      for k in ch.now {
        k.let_go()
      }
    }
  }
}

///|
/// What is made, by key (Ctx::made), and the nodes put among the frame's by the last build, by their slots: taken out
/// as each build begins (made_detach) for the build to make its own in their places.
// kept across runs: let go as a run begins (made_forget)
let made_roots : Map[Int, Made] = {}

///|
// kept across runs: written as each build puts what is made among the frame's nodes
let made_placed : Array[(Int, Node)] = []

///|
/// What a press on each node made does, by its id, as it was last put among the frame's (Made::on_press), till it is
/// let go: one kept in a list's row put back unbuilt with it does as it did.
// kept across runs: written as what is made is put among the frame's nodes, let go with it
let made_presses : Map[Int, () -> Unit] = {}

///|
/// A run begins: nothing made is kept.
fn made_forget() -> Unit {
  for _, m in made_roots {
    m.let_go()
  }
  made_roots.clear()
  made_placed.clear()
  made_presses.clear()
  keys_taken.clear()
}

///|
/// As each pass of a frame's build begins: the nodes made the last put among the frame's taken out, a spare in each of
/// their places, for this build to make its own there.
fn Ctx::made_detach(self : Ctx) -> Unit {
  for p in made_placed {
    let (slot, n) = p
    if slot < self.nodes.length() && physical_equal(self.nodes[slot], n) {
      self.nodes[slot] = match spare_nodes.pop() {
        Some(sp) => sp
        None => Node::new()
      }
    }
  }
  made_placed.clear()
}

///|
/// What `make` makes, made once (by `key` in the scope it is said in), put here among the frame's nodes each frame it
/// is built: each node as it was made where nothing its fill read changed, filled anew where something did.
pub fn Ctx::made(self : Ctx, key : String, make : () -> Made) -> Unit {
  let id = self.id(key)
  let m = match made_roots.get(id) {
    Some(m) => m
    None => {
      let m = @signals.untracked(make)
      made_roots[id] = m
      m
    }
  }
  self.made_put(m)
}

///|
/// Node `m` put here among the frame's, then what it holds in it.
fn Ctx::made_put(self : Ctx, m : Made) -> Unit {
  if m.old {
    (m.fill)(self)
    return
  }
  match m.island {
    Some((name, key, read_out)) => {
      let k = @signals.untracked(key)
      self.part_nodes(self.id(name), k, fn() { (m.fill)(self) }, read_out, own=true, named=name)
      return
    }
    None => ()
  }
  let slot = self.count
  // (in a list's row or a part kept as its nodes: its nodes are the row's, kept with it, never put back by it too (one
  // node in two places), filled as the row is built; what makes it changed builds the row again: made_watch)
  m.held.val = nodes_run.building
  let in_row = nodes_run.building is Some(_)
  // (a frame built whole fills every node anew: what is kept held to what filling it makes)
  let whole = nodes_run.whole
  match m.node {
    Some(n) if !m.watch.is_stale() && !whole && !in_row => self.made_put_back(n, slot)
    _ => {
      m.watch.read(fn() { (m.fill)(self) })
      if self.count != slot + 1 {
        abort("a made node's fill makes one node, nothing in it: \{self.count - slot} made")
      }
      m.node = Some(self.nodes[slot])
    }
  }
  let n = self.nodes[slot]
  if !in_row {
    made_placed.push((slot, n))
  }
  match m.on_press {
    Some(f) if n.id != 0 => made_presses[n.id] = f
    _ => ()
  }
  let kids = match m.kids {
    Kept(ks) => ks
    Made(ch) => {
      if ch.watch.is_stale() || whole {
        ch.now = ch.watch.read(ch.make)
      }
      ch.now
    }
  }
  self.with_parent(slot, fn() {
    for k in kids {
      self.made_put(k)
    }
  })
}

///|
/// Node `n`, made and kept, put in `slot` (the next of the frame's) under what is being built, as alloc_part would
/// put one made there; what the frame is told of it said again (docs/retained.md, the way there's 1: what its node
/// does not hold).
fn Ctx::made_put_back(self : Ctx, n : Node, slot : Int) -> Unit {
  while self.nodes.length() <= slot {
    self.nodes.push(
      match spare_nodes.pop() {
        Some(sp) => sp
        None => Node::new()
      },
    )
  }
  spare_nodes.push(self.nodes[slot])
  self.nodes[slot] = n
  self.count = slot + 1
  n.slot = slot
  n.parent = self.cur
  n.first = -1
  n.last = -1
  n.next = -1
  // (who it is, as the build would make it here (Ctx::node_known): made in this pass, what it holds counted from none,
  // and counted among what holds it, so that what is made in and after it is who it was)
  n.kids = 0
  n.made_pass = known_pass.val
  known_nodes.set(n.ident, n)
  if n.keyless && self.cur >= 0 {
    let p = self.nodes[self.cur]
    p.kids = p.kids + 1
  }
  if self.cur >= 0 {
    let p = self.nodes[self.cur]
    if p.last >= 0 {
      self.nodes[p.last].next = slot
    } else {
      p.first = slot
    }
    p.last = slot
  }
  if n.id != 0 {
    self.id_built(slot)
  }
  self.moves_said_again(slot, slot + 1)
  self.ticks_said_again(slot, slot + 1)
}

///|
/// A press on target `id` (a tap, a click, Enter or Space where it takes the focus), let go on it, does `f`: then, as it
/// is let go, outside any build, not read as the next frame is built (docs/retained.md, the model's 5: acting is a
/// callback). Said as `id`'s box is built (what it does is what the last build said), it takes presses (the pointer's
/// hand over it). What a frame read of the press (Ctx::clicked) it reads as before.
pub fn Ctx::on_press(self : Ctx, id : Int, f : () -> Unit) -> Unit {
  if id == 0 {
    return
  }
  self.takes_presses(id)
  made_presses[id] = f
}

///|
/// What the part over a field said the field's keys do (Ctx::on_key), and the build that last said it (or put the part
/// back unbuilt with it).
priv struct KeysTaken {
  take : (Int, Int) -> Bool
  mut build : Int
}

///|
/// The keys taken over each field (by the field's id, its owner): one part's at a time, the last build's to say it.
// kept across runs: said as each build builds what takes them, let go as a build does not; a run's start clears it
let keys_taken : Map[Int, KeysTaken] = {}

///|
/// The keys of field `owner` (the id that has the focus as they come: its editor's) that the part being built over it
/// takes (a menu of what to put in it: ↑ ↓ to choose, Enter to put the one chosen in): `take` given each key (its code
/// and what is held with it) as it comes, outside any build, before the window's tree's Tab, the field and the frame
/// see it, only while `owner` has the focus where it takes input then (Ctx::focus_allowed: its island taking input;
/// Ctx::keys_reach: no layer over it the keys go to), never a key catcher's (its keys all its own); saying whether it
/// took it (taken, nothing else sees it). `take` asks, as the key comes, whether what it was built for still holds
/// (the menu still open over the words it was built for): not, it takes nothing, and the key goes on as any key does. Said each build it is built (kept unbuilt with its part, as it was); a build that does not
/// say it has let it go.
pub fn Ctx::on_key(self : Ctx, owner : Int, take : (Int, Int) -> Bool) -> Unit {
  if owner == 0 {
    return
  }
  let w = { take, build: self.build_no }
  keys_taken[owner] = w
  built_used(fn() { w.build = g().build_no })
}

///|
/// A key come (`code`, `mods`) to `focus` (the focus where it takes input, 0 none): given to what the last build said
/// takes that field's keys, if it does.
fn keys_taken_now(focus : Int, code : Int, mods : Int) -> Bool {
  // (the focus where the keys go: no layer over it that takes them, modal or with the focus in it, Ctx::keys_reach; a
  // key catcher's are all its own, as they are before anything else: catcher_key)
  if focus == 0 || g().dev.catchers.contains(focus) || !g().keys_reach(focus) {
    return false
  }
  match keys_taken.get(focus) {
    Some(w) if w.build >= builds_made.val => {
      @signals.start_batch()
      let took = @signals.untracked(fn() { (w.take)(code, mods) })
      @signals.end_batch()
      took
    }
    Some(_) => {
      keys_taken.remove(focus)
      false
    }
    None => false
  }
}

///|
/// A frame built: what takes the keys of a field it no longer said so of let go (its part not built nor kept).
fn keys_taken_built() -> Unit {
  let last = builds_made.val
  let gone : Array[Int] = []
  keys_taken.each(fn(k, w) { if w.build < last { gone.push(k) } })
  for k in gone {
    keys_taken.remove(k)
  }
}

///|
/// Target `id` let go of a press (a click, a tap, a key): what a node made said a press on it does, done now, outside
/// any build (Made::on_press).
fn made_pressed(id : Int) -> Unit {
  match made_presses.get(id) {
    Some(f) => {
      @signals.start_batch()
      @signals.untracked(f)
      @signals.end_batch()
    }
    None => ()
  }
}
