// alien-signals' signals, computeds and effects (https://github.com/stackblitz/alien-signals 3.2.1, src/index.ts;
// MIT, Copyright (c) 2024-present Johnson Chu), ported line for line over system.mbt's graph. What differs is
// MoonBit's: a signal and a computed are their node with `get` and `set` rather than functions bound to it, what
// index.ts's node of their kind holds besides the graph's fields kept in their Signal and Computed and their update,
// an effect's fn and a watch's in the node's `own` (system.mbt); an effect's cleanup is said by which of `effect` and `effect_cleanup` makes it;
// nothing throws, so nothing is put back in a `finally`; and "the same value" is `same` (physical_equal without one:
// index.ts's `!==`, but for strings, which it compares by their words: say `same=fn(a, b) { a == b }` where that
// matters). Added for what keeps its own computeds: Computed::peek, Computed::dispose,
// Signal::watched, untracked; and for what holds what another computed builds after it ran: Computed::reading,
// Computed::lend; Computed::invalidate.

///|
/// A parent (an effect or a scope) whose deps include at least one effect of its own (HasChildEffect): what it runs
/// again or disposes of disposes of those first. Outside ReactiveFlags' range, never touched by system.mbt.
const HAS_CHILD_EFFECT : Int = 64

///|
// A computed lost its last reader while its getter was running. Its reads must remain linked until that getter ends.
const UNWATCH_AFTER_UPDATE : Int = 128

///|
// Explicit dispose applies even if another node still reads the computed.
const DISPOSE_AFTER_UPDATE : Int = 256

///|
// Additional reads made for a computed by Computed::reading, in call order.
let computed_extra_reads : Array[ReactiveNode?] = []

///|
fn computed_extra_reading(node : ReactiveNode) -> Bool {
  computed_extra_reads.iter().any(fn(entry) {
    match entry { Some(reading) => physical_equal(reading, node); None => false }
  })
}

///|
/// What the graph is doing: the cycle of reads (a link's version), how deep in effects' runs and in batches, the
/// effects notified and waiting to run, and the node reading (activeSub).
priv struct Run {
  mut cycle : Int
  mut run_depth : Int
  mut batch_depth : Int
  mut notify_index : Int
  mut queued_length : Int
  mut active_sub : ReactiveNode?
  /// what owns what is made now (an effect, a scope): what is reading where something is, else this (Solid's Owner
  /// apart from its Listener: `untracked` stops following reads, never owning)
  mut owner : ReactiveNode?
  queued : Array[ReactiveNode?]
  /// how deep in flushes, and what is to be done once the outermost is over (after_flush): not this library's
  /// algorithm, a hook beside it for what reads where a change left things once all it told is told
  mut flushing : Int
  afters : Array[(() -> Unit)?]
  /// doing what waits for a change told whole (after_flush): one at a time, in order, whatever they set meanwhile
  mut draining : Bool
}

///|
let run : Run = {
  cycle: 0,
  run_depth: 0,
  batch_depth: 0,
  notify_index: 0,
  queued_length: 0,
  active_sub: None,
  owner: None,
  queued: [],
  flushing: 0,
  afters: [],
  draining: false,
}

///|
/// A signal (SignalNode): its node and its state.
struct Signal[T](ReactiveNode, SignalState[T])

///|
/// A signal's own: its value and the one set (pendingValue), what is the same as what (physical_equal without one).
priv struct SignalState[T] {
  mut current : T
  mut pending : T
  same : ((T, T) -> Bool)?
}

///|
/// A computed (ComputedNode): its node and its state.
struct Computed[T](ReactiveNode, ComputedState[T])

///|
/// A computed's own: its getter, given the value it made last (none the first time), and that value.
priv struct ComputedState[T] {
  mut value : T?
  getter : (T?) -> T
  same : ((T, T) -> Bool)?
  /// A resource-bearing computed does not keep its dependencies after a one-off, untracked read.
  mut untracked_dispose : Bool
  /// What a graph reader follows alongside this computed; one-off reads do not acquire it.
  mut read_dependency : Computed[Unit]?
  /// An optional direct answer for an untracked read, without installing graph dependencies.
  mut untracked_read : (() -> T?)?
}

///|
/// Whether `a` is `b` as `same` says, physical_equal (index.ts's `===`) without one.
fn[T] same_as(same : ((T, T) -> Bool)?, a : T, b : T) -> Bool {
  match same {
    None => physical_equal(a, b)
    Some(f) => f(a, b)
  }
}

///|
/// A signal's update (updateSignal) for its node to call, over its state.
fn[T] signal_update(state : SignalState[T]) -> (ReactiveNode) -> Bool {
  fn(n) { update_signal(n, state) }
}

///|
/// A computed's update (updateComputed) for its node to call, over its state.
fn[T] computed_update(state : ComputedState[T]) -> (ReactiveNode) -> Bool {
  fn(n) { update_computed(n, state) }
}

// ── system.mbt's callbacks (createReactiveSystem's update, notify, unwatched) ─────────────────────────────

///|
fn update(node : ReactiveNode) -> Bool {
  match node.update {
    Some(u) => u(node)
    None => {
      node.flags = MUTABLE
      true
    }
  }
}

///|
fn notify(first : ReactiveNode) -> Unit {
  let mut effect = first
  let mut insert_index = run.queued_length
  let mut first_inserted = insert_index
  while true {
    // (queued[insertIndex++] = effect, the array grown as index.ts's is by its index)
    if insert_index < run.queued.length() {
      run.queued[insert_index] = Some(effect)
    } else {
      run.queued.push(Some(effect))
    }
    insert_index += 1
    // (a watch marked as it is notified, whatever batch it is in: what it holds told it may be stale before it is told
    // so as the batch ends: Watch::on_marked)
    if effect.kind is WatchNode {
      guard effect.own is WatchOwned(o) else { @halt.saying("a watch without its own") }
      o.marked_by = setting.val
      match o.marked {
        Some(f) if !o.resting => f()
        _ => ()
      }
    }
    effect.flags = effect.flags & WATCHING.lnot()
    match effect.subs {
      Some(l) => {
        effect = l.sub
        if (effect.flags & WATCHING) == 0 {
          break
        }
      }
      None => break
    }
  }
  run.queued_length = insert_index
  insert_index -= 1
  while first_inserted < insert_index {
    let left = run.queued[first_inserted]
    run.queued[first_inserted] = run.queued[insert_index]
    run.queued[insert_index] = left
    first_inserted += 1
    insert_index -= 1
  }
}

///|
fn unwatched(node : ReactiveNode) -> Unit {
  match node.kind {
    ComputedNode =>
      if (node.flags & RECURSED_CHECK) != 0 || computed_extra_reading(node) {
        node.flags = node.flags | UNWATCH_AFTER_UPDATE
      } else if node.deps is Some(_) {
        node.flags = MUTABLE | DIRTY
        dispose_all_deps_in_reverse(node)
      }
    // A resource can ask to be told when its signal loses its last reader.
    SignalNode =>
      match node.cleanup {
        Some(f) => untracked(f)
        None => ()
      }
    EffectNode => effect_oper(node)
    ScopeNode | TriggerNode | WatchNode => effect_scope_oper(node)
  }
}

///|
fn finish_computed_read(node : ReactiveNode) -> Unit {
  if (node.flags & (UNWATCH_AFTER_UPDATE | DISPOSE_AFTER_UPDATE)) == 0 { return }
  if (node.flags & RECURSED_CHECK) != 0 || computed_extra_reading(node) { return }
  let unwatched_during_read = (node.flags & UNWATCH_AFTER_UPDATE) != 0
  let disposed_during_read = (node.flags & DISPOSE_AFTER_UPDATE) != 0
  node.flags = node.flags & (UNWATCH_AFTER_UPDATE | DISPOSE_AFTER_UPDATE).lnot()
  if disposed_during_read || (unwatched_during_read && node.subs is None) {
    node.flags = MUTABLE | DIRTY
    dispose_all_deps_in_reverse(node)
  }
}

///|
/// Whether `dep` is neither a computed nor a signal (`!('getter' in dep) && !('currentValue' in dep)`).
fn effect_like(dep : ReactiveNode) -> Bool {
  match dep.kind {
    ComputedNode | SignalNode => false
    _ => true
  }
}

// ── index.ts ────────────────────────────────────────────────────────────────────────────────────────────────

///|
pub fn active_sub() -> ReactiveNode? {
  run.active_sub
}

///|
/// The node reading set; the one before.
pub fn set_active_sub(sub : ReactiveNode?) -> ReactiveNode? {
  let prev_sub = run.active_sub
  run.active_sub = sub
  prev_sub
}

///|
/// What owns what is made now where nothing is reading (an effect or a scope made in `untracked`): set; the one before.
pub fn set_owner(owner : ReactiveNode?) -> ReactiveNode? {
  let prev = run.owner
  run.owner = owner
  prev
}

///|
/// What is made now is owned by: what is reading, else the owner set (set_owner).
fn owner_now() -> ReactiveNode? {
  match run.active_sub {
    Some(s) => Some(s)
    None => run.owner
  }
}

///|
pub fn batch_depth() -> Int {
  run.batch_depth
}

///|
pub fn start_batch() -> Unit {
  run.batch_depth += 1
}

///|
pub fn end_batch() -> Unit {
  run.batch_depth -= 1
  if run.batch_depth == 0 {
    flush()
  }
}

///|
/// The batch ended, as `end_batch`; but where a flush is under way, what it set is left to that flush, run in its turn
/// after what was queued before it, not in a flush begun inside it. Not alien-signals': its endBatch flushes inside the
/// effect that ends the batch, so a flush of N effects each ending a batch ran them each inside the one before, N deep
/// (Tree::at_cause: a change marking 400 structures overflowed the stack, 2026-11-12).
pub fn end_batch_in_turn() -> Unit {
  run.batch_depth -= 1
  if run.batch_depth == 0 && run.flushing == 0 {
    flush()
  }
}

///|
/// A signal holding `initial`.
pub fn[T] signal(initial : T, same? : (T, T) -> Bool) -> Signal[T] {
  let state : SignalState[T] = { current: initial, pending: initial, same }
  Signal(
    ReactiveNode::new(
      MUTABLE,
      SignalNode,
      update=signal_update(state),
    ),
    state,
  )
}

///|
/// A computed: `getter` worked out (given what it made last) as it is read after what it read changed.
pub fn[T] computed(getter : (T?) -> T, same? : (T, T) -> Bool) -> Computed[T] {
  let state : ComputedState[T] = { value: None, getter, same, untracked_dispose: false, read_dependency: None, untracked_read: None }
  Computed(
    ReactiveNode::new(
      NONE,
      ComputedNode,
      update=computed_update(state),
    ),
    state,
  )
}

///|
/// A computed which releases its dependencies after a one-off read outside the graph. When read by another signal,
/// its dependencies stay until the last reader leaves, just as for any computed.
pub fn[T] computed_scoped(getter : (T?) -> T, same? : (T, T) -> Bool, untracked_read? : (() -> T?)? = None) -> Computed[T] {
  let c = computed(getter, same?)
  holds_up(c.0)
  c.1.untracked_dispose = true
  c.1.untracked_read = untracked_read
  c
}

///|
/// A value whose graph readers also follow a shared resource. A one-off read acquires no resource and leaves no links.
pub fn[T] computed_following(getter : (T?) -> T, dependency : Computed[Unit], same? : (T, T) -> Bool) -> Computed[T] {
  let c = computed_scoped(getter, same?)
  c.1.read_dependency = Some(dependency)
  c
}

///|
/// An effect: `fn` run now, and again as what it read changes; the function that stops it. `loc`: where it was made,
/// said only where it is made as a watch reads (effect_in_watch), kept nowhere.
#callsite(autofill(loc))
pub fn effect(f : () -> Unit, loc~ : SourceLoc) -> () -> Unit {
  effect_of(
    fn() {
      f()
      None
    },
    loc,
  )
}

///|
/// An effect whose run returns its cleanup, run before it runs again and as it is stopped.
#callsite(autofill(loc))
pub fn effect_cleanup(f : () -> (() -> Unit), loc~ : SourceLoc) -> () -> Unit {
  effect_of(fn() { Some(f()) }, loc)
}

///|
/// Told as an effect is made while a watch reads (Watch::read): it is that watch's whatever owner is set (owner_now
/// takes what is reading first), and is let go as the watch reads anew, what it follows followed no longer (kitdemo's
/// pick and op checks, made in an after_build as a frame's watch read: nothing took the host's word, 2026-11-12). ui
/// says it as a fault (frame_watch.mbt), told where it was made; None: nothing told.
pub let effect_in_watch : Ref[((SourceLoc) -> Unit)?] = Ref(None)

///|
fn effect_of(f : () -> (() -> Unit)?, loc : SourceLoc) -> () -> Unit {
  let e = ReactiveNode::new(WATCHING | RECURSED_CHECK, EffectNode, own=EffectOwn(f))
  let parent = owner_now()
  match parent {
    Some(p) if p.kind is WatchNode =>
      match effect_in_watch.val {
        Some(told) => told(loc)
        None => ()
      }
    _ => ()
  }
  let prev_sub = set_active_sub(Some(e))
  let prev_owner = set_owner(Some(e))
  match parent {
    Some(p) => {
      link(e, p, 0)
      p.flags = p.flags | HAS_CHILD_EFFECT
    }
    None => ()
  }
  run.run_depth += 1
  e.cleanup = f()
  run.run_depth -= 1
  run.active_sub = prev_sub
  run.owner = prev_owner
  e.flags = e.flags & RECURSED_CHECK.lnot()
  fn() { effect_oper(e) }
}

///|
/// A scope: what `fn` makes (effects) stopped together by the function returned.
pub fn effect_scope(f : () -> Unit) -> () -> Unit {
  let e = ReactiveNode::new(MUTABLE, ScopeNode)
  let parent = owner_now()
  let prev_sub = set_active_sub(Some(e))
  let prev_owner = set_owner(Some(e))
  match parent {
    Some(p) => {
      link(e, p, 0)
      p.flags = p.flags | HAS_CHILD_EFFECT
    }
    None => ()
  }
  f()
  run.active_sub = prev_sub
  run.owner = prev_owner
  fn() { effect_scope_oper(e) }
}

///|
/// What `fn` reads told it changed (what follows it worked out again), whether or not it did.
pub fn trigger(f : () -> Unit) -> Unit {
  let sub = ReactiveNode::new(WATCHING | RECURSED_CHECK, TriggerNode)
  let prev_sub = set_active_sub(Some(sub))
  run.batch_depth += 1
  f()
  run.active_sub = prev_sub
  sub.flags = NONE
  let mut link = sub.deps
  while true {
    match link {
      Some(l) => {
        let dep = l.dep
        link = unlink(l, sub)
        match dep.subs {
          Some(subs) => {
            propagate(subs, run.run_depth != 0)
            shallow_propagate(subs)
          }
          None => ()
        }
      }
      None => break
    }
  }
  run.batch_depth -= 1
  if run.batch_depth == 0 {
    flush()
  }
}

///|
fn[T] update_computed(c : ReactiveNode, state : ComputedState[T]) -> Bool {
  if (c.flags & HAS_CHILD_EFFECT) != 0 {
    let mut link = c.deps_tail
    while true {
      match link {
        Some(l) => {
          let prev = l.prev_dep
          if effect_like(l.dep) {
            unlink(l, c) |> ignore
          }
          link = prev
        }
        None => break
      }
    }
  }
  c.deps_tail = None
  let deferred = c.flags & (UNWATCH_AFTER_UPDATE | DISPOSE_AFTER_UPDATE)
  c.flags = MUTABLE | RECURSED_CHECK | deferred
  let prev_sub = set_active_sub(Some(c))
  run.cycle += 1
  let old_value = state.value
  let value = (state.getter)(old_value)
  state.value = Some(value)
  run.active_sub = prev_sub
  c.flags = c.flags & RECURSED_CHECK.lnot()
  purge_deps(c)
  finish_computed_read(c)
  match old_value {
    Some(old) => !same_as(state.same, old, value)
    None => true
  }
}

///|
fn[T] update_signal(s : ReactiveNode, state : SignalState[T]) -> Bool {
  s.flags = MUTABLE
  let was = state.current
  state.current = state.pending
  !same_as(state.same, was, state.current)
}

///|
fn run_effect(e : ReactiveNode) -> Unit {
  let flags = e.flags
  // (a watch told: what it read changed, it says so; what it read stays followed till it reads anew, Watch::read)
  if e.kind is WatchNode {
    guard e.own is WatchOwned(o) else { @halt.saying("a watch without its own") }
    // (at rest: stale, nothing it read asked whether it changed; it reads anew as it wakes, rest)
    if o.resting {
      e.flags = WATCHING
      o.stale = true
      o.marked_by = None
      return
    }
    let dirty = (flags & DIRTY) != 0 ||
      (
        (flags & PENDING) != 0 &&
        (match e.deps {
          Some(d) => check_dirty(d, e)
          None => false
        })
      )
    e.flags = WATCHING
    if dirty {
      // (told where no set is under way (a batch's end): the set that marked it said, as it would be had it been told
      // as it was set)
      let was = setting.val
      if was is None {
        setting.val = o.marked_by
      }
      o.told()
      setting.val = was
    }
    o.marked_by = None
    return
  }
  if (flags & DIRTY) != 0 || ((flags & PENDING) != 0 && check_dirty(e.deps.unwrap(), e)) {
    if (flags & HAS_CHILD_EFFECT) != 0 {
      let mut link = e.deps_tail
      while true {
        match link {
          Some(l) => {
            let prev = l.prev_dep
            if effect_like(l.dep) {
              unlink(l, e) |> ignore
            }
            link = prev
          }
          None => break
        }
      }
    }
    if e.cleanup is Some(_) {
      run_cleanup(e)
      if e.flags == 0 {
        return
      }
    }
    e.deps_tail = None
    e.flags = WATCHING | RECURSED_CHECK
    let prev_sub = set_active_sub(Some(e))
    let prev_owner = set_owner(Some(e))
    run.cycle += 1
    run.run_depth += 1
    if e.kind is EffectNode {
      guard e.own is EffectOwn(f) else { @halt.saying("an effect without its fn") }
      e.cleanup = f()
    }
    run.run_depth -= 1
    run.active_sub = prev_sub
    run.owner = prev_owner
    e.flags = e.flags & RECURSED_CHECK.lnot()
    purge_deps(e)
  } else if e.deps is Some(_) {
    e.flags = WATCHING | (flags & HAS_CHILD_EFFECT)
  }
}

///|
fn flush() -> Unit {
  run.flushing += 1
  while run.notify_index < run.queued_length {
    let effect = run.queued[run.notify_index].unwrap()
    run.queued[run.notify_index] = None
    run.notify_index += 1
    run_effect(effect)
  }
  run.notify_index = 0
  run.queued_length = 0
  run.flushing -= 1
  // (the change told whole, every effect it set going run: what waits for that, in order; what one of them sets
  // flushed in its turn, what waits on that after it)
  if run.flushing == 0 && run.batch_depth == 0 && !run.draining {
    run.draining = true
    // (taken by where the queue is up to, not removed from its head: removing the first shifted all the rest down
    // each time, a change that asked 10⁴s of them (a long page's buttons each going together) held the desktop app's
    // main thread 3.2 s, 0.1.7302, 2026-11-05)
    let mut a = 0
    while a < run.afters.length() {
      let f = run.afters[a].unwrap()
      // Clearing an array keeps its unused slots. Drop the callback as it runs
      // so a completed change does not keep what its callbacks captured.
      run.afters[a] = None
      a += 1
      f()
    }
    run.afters.clear()
    run.draining = false
  }
}

///|
/// `f` done once the change being told now is told whole (the outermost flush of the batch or the set under way over,
/// every effect it set going run); none under way, now. Not alien-signals': a hook beside it, for what must see where
/// one change left things and never half of it (where a window's tree stands as the next change comes).
pub fn after_flush(f : () -> Unit) -> Unit {
  if run.flushing > 0 || run.batch_depth > 0 || run.draining {
    run.afters.push(Some(f))
  } else {
    f()
  }
}

///|
/// The computed's value, worked out again first if what it read changed since (computedOper).
pub fn[T] Computed::get(self : Computed[T]) -> T {
  let node = self.0
  let state = self.1
  if run.active_sub is None {
    match state.untracked_read {
      Some(read) => match read() {
        Some(value) => return value
        None => ()
      }
      None => ()
    }
  }
  if run.active_sub is Some(_) {
    match state.read_dependency {
      Some(dependency) => dependency.get()
      None => ()
    }
  }
  let untracked = state.untracked_dispose && run.active_sub is None
  let flags = node.flags
  let stale = if (flags & DIRTY) != 0 {
    true
  } else if (flags & PENDING) != 0 {
    if check_dirty(node.deps.unwrap(), node) {
      true
    } else {
      node.flags = flags & PENDING.lnot()
      false
    }
  } else {
    false
  }
  if stale {
    if update_computed(node, state) {
      match node.subs {
        Some(subs) => shallow_propagate(subs)
        None => ()
      }
    }
  } else if flags == 0 {
    node.flags = MUTABLE | RECURSED_CHECK
    let prev_sub = set_active_sub(Some(node))
    state.value = Some((state.getter)(None))
    run.active_sub = prev_sub
    node.flags = node.flags & RECURSED_CHECK.lnot()
    finish_computed_read(node)
  }
  track(node)
  let value = state.value.unwrap()
  if untracked && node.subs is None {
    unwatched(node)
  }
  value
}

///|
/// The signal's value (signalOper read): what was set, once it is read after.
pub fn[T] Signal::get(self : Signal[T]) -> T {
  let node = self.0
  let state = self.1
  if (node.flags & DIRTY) != 0 {
    if update_signal(node, state) {
      match node.subs {
        Some(subs) => shallow_propagate(subs)
        None => ()
      }
    }
  }
  track(node)
  state.current
}

///|
/// The signal set (signalOper write): what follows it told, unless it is the same as what was set.
#callsite(autofill(loc))
pub fn[T] Signal::set(self : Signal[T], value : T, loc~ : SourceLoc) -> Unit {
  let state = self.1
  let changed = !same_as(state.same, state.pending, value)
  state.pending = value
  if changed {
    // (set as a watch reads: where, for it to say what changed what it read as it read, Watch::set_as_read)
    if watch_reading.depth > 0 && watch_reading.sets.length() < 4 {
      watch_reading.sets.push(loc.to_string())
    }
    // (where, for what it tells to say: Signal::set_at)
    set_at.val = Some(loc)
    sets_count.val += 1
    let node = self.0
    node.flags = MUTABLE | DIRTY
    match node.subs {
      Some(subs) => {
        let was = setting.val
        setting.val = Some(loc)
        propagate(subs, run.run_depth != 0)
        if run.batch_depth == 0 {
          flush()
        }
        setting.val = was
      }
      None => ()
    }
  }
}

///|
/// What is reading now reads `dep` (`link(dep, activeSub, cycle)`, as computedOper and signalOper say it). Link's two
/// first checks, one of which holds for nearly every read (`dep` read just before; read next where it was read last
/// time), are made here, on the fields as they are and before anything is called: a reference bound to a name and
/// passed on is counted, under reference counting, and these looks then cost a count each.
fn track(dep : ReactiveNode) -> Unit {
  match run.active_sub {
    Some(sub) => {
      if sub.deps_tail is Some(p) && physical_equal(p.dep, dep) {
        return
      }
      match sub.deps_tail {
        Some(p) =>
          if p.next_dep is Some(n) && physical_equal(n.dep, dep) {
            n.version = run.cycle
            sub.deps_tail = p.next_dep
            return
          }
        None =>
          if sub.deps is Some(n) && physical_equal(n.dep, dep) {
            n.version = run.cycle
            sub.deps_tail = sub.deps
            return
          }
      }
      link(dep, sub, run.cycle)
    }
    None => ()
  }
}

///|
fn run_cleanup(e : ReactiveNode) -> Unit {
  let cleanup = e.cleanup.unwrap()
  e.cleanup = None
  let prev_sub = run.active_sub
  run.active_sub = None
  cleanup()
  run.active_sub = prev_sub
}

///|
fn effect_oper(e : ReactiveNode) -> Unit {
  effect_scope_oper(e)
  if e.cleanup is Some(_) {
    run_cleanup(e)
  }
}

///|
fn effect_scope_oper(e : ReactiveNode) -> Unit {
  // (a watch stopped, by itself or by what owns it: it follows nothing from here, so it is stale, and gone: what kept
  // it by what it read keeps nothing by it, Watch::gone)
  if e.kind is WatchNode {
    guard e.own is WatchOwned(o) else { @halt.saying("a watch without its own") }
    o.stale = true
    o.gone = true
  }
  e.flags = NONE
  dispose_all_deps_in_reverse(e)
  match e.subs {
    Some(sub) => unlink(sub, sub.sub) |> ignore
    None => ()
  }
}

///|
/// All `sub` read let go, the last first: all of it, past how far a read under way has got (`deps_tail` is only that,
/// what it read before still after it: a watch let go as it reads anew), from where the list ends as each goes (what
/// one let go lets go in turn may take another of them with it).
fn dispose_all_deps_in_reverse(sub : ReactiveNode) -> Unit {
  let mut last = match sub.deps_tail {
    Some(t) => Some(t)
    None => sub.deps
  }
  while last is Some(l) && l.next_dep is Some(n) {
    last = Some(n)
  }
  sub.deps_tail = last
  while sub.deps_tail is Some(l) {
    unlink(l, sub) |> ignore
  }
}

///|
fn purge_deps(sub : ReactiveNode) -> Unit {
  let mut dep = match sub.deps_tail {
    Some(t) => t.next_dep
    None => sub.deps
  }
  while true {
    match dep {
      Some(d) => dep = unlink(d, sub)
      None => break
    }
  }
}

// ── not alien-signals': for what keeps computeds of its own, and lets them go ──────────────────────────────

///|
/// What the computed made last, not worked out again (none before it was first read).
pub fn[T] Computed::peek(self : Computed[T]) -> T? {
  let state = self.1
  state.value
}

///|
/// The computed let go of what it read (as unwatched does with a computed nothing reads any more): what it read no
/// longer holds it, and it is worked out anew if it is read again.
pub fn[T] Computed::dispose(self : Computed[T]) -> Unit {
  let node = self.0
  if (node.flags & RECURSED_CHECK) != 0 || computed_extra_reading(node) {
    node.flags = node.flags | DISPOSE_AFTER_UPDATE
  } else {
    unwatched(node)
  }
}

///|
/// Whether anything reads the signal (a computed, an effect).
pub fn[T] Signal::watched(self : Signal[T]) -> Bool {
  self.0.subs is Some(_)
}

///|
/// Tell a resource when the last graph reader of this signal leaves. The callback stays installed for later readers.
pub fn[T] Signal::on_unwatched(self : Signal[T], f : () -> Unit) -> Unit {
  self.0.cleanup = Some(f)
  holds_up(self.0)
}

///|
/// Whether anything reads the computed (a computed, an effect): what follows it keeps it.
pub fn[T] Computed::watched(self : Computed[T]) -> Bool {
  self.0.subs is Some(_)
}

///|
/// What `f` makes, nothing it reads followed by what is reading now.
pub fn[T] untracked(f : () -> T) -> T {
  let prev_sub = set_active_sub(None)
  let v = f()
  run.active_sub = prev_sub
  v
}

///|
/// The signal's value as `untracked(fn() { s.get() })` reads it, with no function made to read it in.
pub fn[T] Signal::untracked(self : Signal[T]) -> T {
  let prev_sub = set_active_sub(None)
  let v = self.get()
  run.active_sub = prev_sub
  v
}

///|
/// The computed's value as `untracked(fn() { c.get() })` reads it, with no function made to read it in.
pub fn[T] Computed::untracked(self : Computed[T]) -> T {
  let prev_sub = set_active_sub(None)
  let v = self.get()
  run.active_sub = prev_sub
  v
}

///|
/// The computed worked out again as it is next read, whatever it read (what reads it told, as a signal set tells it):
/// for one built again for what is no signal (a part kept, Ctx::kept_part: its key, the pointer over it).
pub fn[T] Computed::invalidate(self : Computed[T]) -> Unit {
  let node = self.0
  node.flags = node.flags | DIRTY
  match node.subs {
    Some(subs) => {
      propagate(subs, run.run_depth != 0)
      if run.batch_depth == 0 {
        flush()
      }
    }
    None => ()
  }
}

///|
/// What `f` makes, what it reads read by the computed as well, as though its run had read it after what it read: what
/// is built for it after it ran (a list's rows, laid out after the part they are in was built). Let go as the
/// computed's run reads anew, as what it read is.
pub fn[T, U] Computed::reading(self : Computed[T], f : () -> U) -> U {
  let depth = computed_extra_reads.length()
  computed_extra_reads.push(Some(self.0))
  let prev_sub = set_active_sub(Some(self.0))
  let v = f()
  run.active_sub = prev_sub
  computed_extra_reads[depth] = None
  computed_extra_reads.pop() |> ignore
  finish_computed_read(self.0)
  v
}

///|
/// What the computed read read by `to` as well, as though `to`'s run had read it after what it read (as
/// Computed::reading: a row's build, run by a computed of its own, read for the part it is in).
pub fn[T, U] Computed::lend(self : Computed[T], to : Computed[U]) -> Unit {
  let mut l = self.0.deps
  while true {
    match l {
      Some(d) => {
        link(d.dep, to.0, run.cycle)
        l = d.next_dep
      }
      None => break
    }
  }
}

// ── not alien-signals': what follows what a run read without running it again ──────────────────────────────

///|
/// A watch: what a run of `Watch::read` read, followed; as any of it changes (a signal set to another value, a
/// computed worked out to another), the watch is stale and `changed` is called, once, nothing of the run run again.
/// What reads anew (the next read) follows what that run reads. For what is worked out when asked, and asked only as
/// it is stale: a window's frame, built anew only where what its last build read changed.
/// What a watch's node holds: what it calls as it is told (as the batch it was marked in ends), and what as it is marked
/// (Watch::on_marked). One object, its states its fields (no cell of its own for each: a binding of a node's has one
/// watch, made and let go with the node, and each object more is an allocation and a free of every node).
priv struct WatchOwn {
  changed : () -> Unit
  mut marked : (() -> Unit)?
  /// stale (what its last read read changed, or it was never read); and stopped (Watch::stop, or by what owns it as
  /// that one stops: Watch::gone)
  mut stale : Bool
  mut gone : Bool
  /// the set that marked it, as it marked it (`setting`, None: a trigger, …): said as it is told (setting_at), where
  /// that is later (a batch's end) and no set is under way then
  mut marked_by : SourceLoc?
  /// where what it read was set again as its last read ran, the first few (Watch::set_as_read; none: nowhere)
  mut set_by : Array[String]?
  /// at rest (rest): following nothing, what it reads read untracked, till it is woken
  mut resting : Bool
}

///|
/// Told: once till it reads anew, what changes again meanwhile adding nothing to its being stale.
fn WatchOwn::told(self : WatchOwn) -> Unit {
  // (at rest, following what it read: stale, told as it wakes)
  if self.resting {
    self.stale = true
    return
  }
  if !self.stale {
    self.stale = true
    (self.changed)()
  }
}

///|
pub struct Watch {
  priv node : ReactiveNode
  priv own : WatchOwn
}

///|
/// How deep in watches' reads the run is, and where values were set in them (Signal::set's callers, the first few).
priv struct WatchReading {
  mut depth : Int
  sets : Array[String]
}

///|
// kept across runs: counts back to 0 as each read ends
let watch_reading : WatchReading = { depth: 0, sets: [] }

///|
/// A watch (Watch): stale until it is first read; `changed` called as what a read read first changes after it, once
/// till the next read.
pub fn watch(changed : () -> Unit) -> Watch {
  // (told, it runs nothing of what it read: what it read stays followed till it reads anew, run_effect)
  let own : WatchOwn = { changed, marked: None, stale: true, gone: false, marked_by: None, set_by: None, resting: false }
  let node = ReactiveNode::new(NONE, WatchNode, own=WatchOwned(own))
  // (made where an owner is set (set_owner: a scope that is not reading, an old view's): that owner's, let go with it;
  // not what is reading's, whose reading anew would let it go)
  match run.owner {
    Some(p) => {
      link(node, p, 0)
      p.flags = p.flags | HAS_CHILD_EFFECT
    }
    None => ()
  }
  { node, own }
}

///|
/// What `f` makes, all it reads followed by the watch in place of what the last read read; not stale after it unless
/// what it read changed as it ran (a value it read set later in it), and then `changed` is called at its end, or it
/// was touched as it ran (Watch::touch), which it keeps. What
/// was reading before it does not read what it reads. An effect `f` makes is the watch's, whatever owner is set, and
/// is let go as it reads anew (told: effect_in_watch).
pub fn[T] Watch::read(self : Watch, f : () -> T) -> T {
  // (at rest: read, nothing followed, till it wakes and reads anew)
  if self.own.resting {
    return untracked(f)
  }
  let e = self.node
  if watch_reading.depth == 0 {
    watch_reading.sets.clear()
  }
  watch_reading.depth += 1
  let own = self.own
  own.set_by = None
  e.deps_tail = None
  e.flags = WATCHING | RECURSED_CHECK
  // (fresh from here: made stale again as it reads (Watch::touch: what it holds told as it is built), it stays so)
  own.stale = false
  let prev_sub = set_active_sub(Some(e))
  run.cycle += 1
  let v = f()
  run.active_sub = prev_sub
  watch_reading.depth -= 1
  e.flags = e.flags & RECURSED_CHECK.lnot()
  purge_deps(e)
  // (let go as it read (what owned it let go meanwhile): what it read after that let go too, none of it kept as read)
  if own.gone {
    e.flags = NONE
    dispose_all_deps_in_reverse(e)
    own.stale = true
    return v
  }
  // (what it read set again as it ran, after it was read: told then as what reads it is, the run still going)
  if (e.flags & (DIRTY | PENDING)) != 0 {
    let dirty = (e.flags & DIRTY) != 0 ||
      (match e.deps {
        Some(d) => check_dirty(d, e)
        None => false
      })
    e.flags = WATCHING
    if dirty {
      own.set_by = Some(watch_reading.sets.copy())
      own.told()
    }
  }
  v
}

///|
/// Where values were set as the last read ran, where what it read changed as it ran (the first few; none where it did
/// not): what changed what it read as it read.
pub fn Watch::set_as_read(self : Watch) -> Array[String] {
  match self.own.set_by {
    Some(s) => s.copy()
    None => []
  }
}

///|
/// Whether what the read under way has read may have changed since it read it (a value it read set again as it
/// reads, or a computed it read told as what that read was): what it makes may be from before that. Asked of nothing,
/// no computed worked out again for it.
pub fn Watch::changed_as_read(self : Watch) -> Bool {
  (self.node.flags & (DIRTY | PENDING)) != 0
}

///|
/// Whether what the watch's last read read changed since (or it was never read).
pub fn Watch::is_stale(self : Watch) -> Bool {
  self.own.stale
}

///|
/// The watch stale, as though what it read changed (`changed` not called): read anew before it is relied on.
pub fn Watch::touch(self : Watch) -> Unit {
  self.own.stale = true
}

///|
/// Whether the watch was stopped (Watch::stop, or by what owned it as that stopped: a scope, an effect run again): it
/// follows nothing, and nothing that kept a thing by it may keep it so; a new one, owned where it is made again, may.
pub fn Watch::gone(self : Watch) -> Bool {
  self.own.gone
}

///|
/// Whether it is at rest (rest): what it read followed by none of it till it wakes.
pub fn Watch::resting(self : Watch) -> Bool {
  self.own.resting
}

///|
/// The watch let go of what it read: it follows nothing, and is stale.
pub fn Watch::stop(self : Watch) -> Unit {
  effect_scope_oper(self.node)
  self.own.stale = true
}

///|
/// What `owner` owns at rest (a scope's watches, and those of each scope it owns), each reading untracked as it is read
/// meanwhile and told nothing: one whose read holds something outside (ReactiveNode's `holds`: a core's topic) lets
/// go of what it read, so that is held for none of them; one that holds nothing keeps following what it read, only
/// stale as that changes (nothing of it worked out meanwhile: what it read is not asked whether it changed). What it
/// gives wakes them: each that let go, or is stale, told as though what it read changed, to read anew; the others
/// as they were. For what is put by to be made another's (a list's block kept for the next to come: mbui's
/// View::park).
pub fn rest(owner : ReactiveNode) -> () -> Unit {
  let rested : Array[WatchOwn] = []
  rest_in(owner, rested)
  fn() {
    for o in rested {
      if o.resting {
        o.resting = false
        if o.stale && !o.gone {
          o.stale = false
          o.told()
        }
      }
    }
  }
}

///|
fn rest_in(e : ReactiveNode, rested : Array[WatchOwn]) -> Unit {
  let mut l = e.deps
  while l is Some(link) {
    let d = link.dep
    l = link.next_dep
    match d.kind {
      WatchNode =>
        match d.own {
          WatchOwned(o) if !o.gone && !o.resting => {
            if d.holds {
              dispose_all_deps_in_reverse(d)
              o.stale = true
            }
            o.resting = true
            rested.push(o)
          }
          _ => ()
        }
      ScopeNode => rest_in(d, rested)
      _ => ()
    }
  }
}

///|
/// Where a signal was last set to another value (Signal::set's caller): what a watch told as it is set says what told
/// it (frame_watch.mbt's layout watch).
// kept across runs: written by each set
let set_at : Ref[SourceLoc?] = Ref(None)

///|
/// The set telling what follows it now (Signal::set, as it propagates and flushes): None while what is told comes of
/// anything else (a trigger, a computed found changed, a batch's end).
// kept across runs: set and put back within each set
let setting : Ref[SourceLoc?] = Ref(None)

///|
/// Where the signal being set now was set, while what follows it is told (a watch told as it is set: the place that
/// told it; told as a batch ends, the set in it that marked it); None when what is told comes of anything else, so it
/// is not the place of some earlier set.
pub fn setting_at() -> SourceLoc? {
  setting.val
}

///|
/// How many sets changed a value so far: what reads it before and after says whether any came between (ui's
/// Ctx::held, whether more came after what told a build).
// kept across runs: a count read only as a difference
let sets_count : Ref[Int] = Ref(0)

///|
pub fn sets_said() -> Int {
  sets_count.val
}

///|
/// Where a signal was last set to another value, as words ("" none).
pub fn last_set_at() -> String {
  match set_at.val {
    Some(l) => l.to_string()
    None => ""
  }
}

///|
/// Whether what the watch's last read read has changed by now, told or not yet (in a batch, before it ends): what is
/// worked out of it is pulled (a computed it read worked out again where what that read changed), nothing told, nothing
/// run but that. For what must read the latest at once (a size asked mid-change), not what waits for the change's end.
/// Found the same, it is watching again: a change after it marks it again (Watch::on_marked), in the same batch too.
pub fn Watch::changed_now(self : Watch) -> Bool {
  if self.own.stale {
    return true
  }
  let e = self.node
  let flags = e.flags
  if (flags & DIRTY) != 0 {
    return true
  }
  if (flags & PENDING) == 0 {
    return false
  }
  let dirty = match e.deps {
    Some(d) => check_dirty(d, e)
    None => false
  }
  // (looked at and found the same: watching again, as a watch told is as it runs (run_effect), so that what changes
  // next in the same batch marks it again; its place in the queue, if it has one, runs to nothing)
  if !dirty {
    e.flags = WATCHING
  }
  dirty
}

///|
/// `f` called as what the watch read changes, at once, in a batch too (before it is told as the batch ends): only to
/// note that it may be stale (a flag, a list), nothing read or set there. Whether it is is Watch::changed_now's to say.
pub fn Watch::on_marked(self : Watch, f : () -> Unit) -> Unit {
  self.own.marked = Some(f)
}
