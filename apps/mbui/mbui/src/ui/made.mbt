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
  { fill, kids: Kept(kids), node: None, watch: made_watch(held), on_press: None, held }
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
