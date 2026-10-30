// alien-signals' signals, computeds and effects (https://github.com/stackblitz/alien-signals 3.2.1, src/index.ts;
// MIT, Copyright (c) 2024-present Johnson Chu), ported line for line over system.mbt's graph. What differs is
// MoonBit's: a signal and a computed are their node with `get` and `set` rather than functions bound to it, what
// index.ts's node of their kind holds besides the graph's fields kept in the node's `own` (system.mbt) as the type its
// signal or computed says (`coerce`); an effect's cleanup is said by which of `effect` and `effect_cleanup` makes it;
// nothing throws, so nothing is put back in a `finally`; and "the same value" is `same` (physical_equal without one:
// index.ts's `!==`, but for strings, which it compares by their words: say `same=fn(a, b) { a == b }` where that
// matters). Added for what keeps its own computeds (docs/signals.md): Computed::peek, Computed::dispose,
// Signal::watched, untracked; and for what holds what another computed builds after it ran: Computed::reading,
// Computed::lend; Computed::invalidate.

///|
/// A parent (an effect or a scope) whose deps include at least one effect of its own (HasChildEffect): what it runs
/// again or disposes of disposes of those first. Outside ReactiveFlags' range, never touched by system.mbt.
const HAS_CHILD_EFFECT : Int = 64

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
}

///|
/// A signal (SignalNode): its node, whose own is a SignalState[T].
struct Signal[T](ReactiveNode)

///|
/// A signal's own: its value and the one set (pendingValue), what is the same as what (physical_equal without one).
priv struct SignalState[T] {
  mut current : T
  mut pending : T
  same : ((T, T) -> Bool)?
}

///|
/// A computed (ComputedNode): its node, whose own is a ComputedState[T].
struct Computed[T](ReactiveNode)

///|
/// A computed's own: its getter, given the value it made last (none the first time), and that value.
priv struct ComputedState[T] {
  mut value : T?
  getter : (T?) -> T
  same : ((T, T) -> Bool)?
}

///|
/// The same reference as another type: a node's own to and from what it is (the SignalState[_], ComputedState[_] or
/// fn the node was made with, as its Signal[_], Computed[_], update or kind says).
fn[A, B] coerce(a : A) -> B = "%identity"

///|
/// Whether `a` is `b` as `same` says, physical_equal (index.ts's `===`) without one.
fn[T] same_as(same : ((T, T) -> Bool)?, a : T, b : T) -> Bool {
  match same {
    None => physical_equal(a, b)
    Some(f) => f(a, b)
  }
}

///|
/// A signal's update (updateSignal) for its node to call, one function for every signal of `T` (`_state` says which).
fn[T] signal_update(_state : SignalState[T]) -> (ReactiveNode) -> Bool {
  fn(n) {
    let own : SignalState[T] = coerce(n.own)
    update_signal(n, own)
  }
}

///|
/// A computed's update (updateComputed) for its node to call, one function for every computed of `T`.
fn[T] computed_update(_state : ComputedState[T]) -> (ReactiveNode) -> Bool {
  fn(n) {
    let own : ComputedState[T] = coerce(n.own)
    update_computed(n, own)
  }
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
      if node.deps_tail is Some(_) {
        node.flags = MUTABLE | DIRTY
        dispose_all_deps_in_reverse(node)
      }
    // (nothing for signals: always mutable, never dirty until their pending value changes)
    SignalNode => ()
    EffectNode => effect_oper(node)
    ScopeNode | TriggerNode | WatchNode => effect_scope_oper(node)
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
/// A signal holding `initial`.
pub fn[T] signal(initial : T, same? : (T, T) -> Bool) -> Signal[T] {
  let state : SignalState[T] = { current: initial, pending: initial, same }
  Signal(
    ReactiveNode::new(
      MUTABLE,
      SignalNode,
      own=coerce(state),
      update=signal_update(state),
    ),
  )
}

///|
/// A computed: `getter` worked out (given what it made last) as it is read after what it read changed.
pub fn[T] computed(getter : (T?) -> T, same? : (T, T) -> Bool) -> Computed[T] {
  let state : ComputedState[T] = { value: None, getter, same }
  Computed(
    ReactiveNode::new(
      NONE,
      ComputedNode,
      own=coerce(state),
      update=computed_update(state),
    ),
  )
}

///|
/// An effect: `fn` run now, and again as what it read changes; the function that stops it.
pub fn effect(f : () -> Unit) -> () -> Unit {
  effect_of(fn() {
    f()
    None
  })
}

///|
/// An effect whose run returns its cleanup, run before it runs again and as it is stopped.
pub fn effect_cleanup(f : () -> (() -> Unit)) -> () -> Unit {
  effect_of(fn() { Some(f()) })
}

///|
fn effect_of(f : () -> (() -> Unit)?) -> () -> Unit {
  let e = ReactiveNode::new(WATCHING | RECURSED_CHECK, EffectNode, own=coerce(f))
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
  c.flags = MUTABLE | RECURSED_CHECK
  let prev_sub = set_active_sub(Some(c))
  run.cycle += 1
  let old_value = state.value
  let value = (state.getter)(old_value)
  state.value = Some(value)
  run.active_sub = prev_sub
  c.flags = c.flags & RECURSED_CHECK.lnot()
  purge_deps(c)
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
      let told : () -> Unit = coerce(e.own)
      told()
    }
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
      let f : () -> (() -> Unit)? = coerce(e.own)
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
  while run.notify_index < run.queued_length {
    let effect = run.queued[run.notify_index].unwrap()
    run.queued[run.notify_index] = None
    run.notify_index += 1
    run_effect(effect)
  }
  run.notify_index = 0
  run.queued_length = 0
}

///|
/// The computed's value, worked out again first if what it read changed since (computedOper).
pub fn[T] Computed::get(self : Computed[T]) -> T {
  let node = self.0
  let state : ComputedState[T] = coerce(node.own)
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
  }
  track(node)
  state.value.unwrap()
}

///|
/// The signal's value (signalOper read): what was set, once it is read after.
pub fn[T] Signal::get(self : Signal[T]) -> T {
  let node = self.0
  let state : SignalState[T] = coerce(node.own)
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
  let state : SignalState[T] = coerce(self.0.own)
  let changed = !same_as(state.same, state.pending, value)
  state.pending = value
  if changed {
    // (set as a watch reads: where, for it to say what changed what it read as it read, Watch::set_as_read)
    if watch_reading.depth > 0 && watch_reading.sets.length() < 4 {
      watch_reading.sets.push(loc.to_string())
    }
    // (where, for what it tells to say: Signal::set_at)
    set_at.val = Some(loc)
    let node = self.0
    node.flags = MUTABLE | DIRTY
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
  e.flags = NONE
  dispose_all_deps_in_reverse(e)
  match e.subs {
    Some(sub) => unlink(sub, sub.sub) |> ignore
    None => ()
  }
}

///|
fn dispose_all_deps_in_reverse(sub : ReactiveNode) -> Unit {
  let mut link = sub.deps_tail
  while true {
    match link {
      Some(l) => {
        let prev = l.prev_dep
        unlink(l, sub) |> ignore
        link = prev
      }
      None => break
    }
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
  let state : ComputedState[T] = coerce(self.0.own)
  state.value
}

///|
/// The computed let go of what it read (as unwatched does with a computed nothing reads any more): what it read no
/// longer holds it, and it is worked out anew if it is read again.
pub fn[T] Computed::dispose(self : Computed[T]) -> Unit {
  unwatched(self.0)
}

///|
/// Whether anything reads the signal (a computed, an effect).
pub fn[T] Signal::watched(self : Signal[T]) -> Bool {
  self.0.subs is Some(_)
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
  let prev_sub = set_active_sub(Some(self.0))
  let v = f()
  run.active_sub = prev_sub
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
pub struct Watch {
  priv node : ReactiveNode
  priv stale : Ref[Bool]
  /// where what it read was set again as its last read ran, the first few (Watch::set_as_read)
  priv set_by : Array[String]
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
  let stale = Ref(true)
  // (told once till it reads anew: what changes again meanwhile adds nothing to its being stale)
  let told : () -> Unit = fn() {
    if !stale.val {
      stale.val = true
      changed()
    }
  }
  // (told, it runs nothing of what it read: what it read stays followed till it reads anew, run_effect)
  let node = ReactiveNode::new(NONE, WatchNode, own=coerce(told))
  // (made where an owner is set (set_owner: a scope that is not reading, an old view's): that owner's, let go with it;
  // not what is reading's, whose reading anew would let it go)
  match run.owner {
    Some(p) => {
      link(node, p, 0)
      p.flags = p.flags | HAS_CHILD_EFFECT
    }
    None => ()
  }
  { node, stale, set_by: [] }
}

///|
/// What `f` makes, all it reads followed by the watch in place of what the last read read; not stale after it unless
/// what it read changed as it ran (a value it read set later in it), and then `changed` is called at its end. What
/// was reading before it does not read what it reads.
pub fn[T] Watch::read(self : Watch, f : () -> T) -> T {
  let e = self.node
  if watch_reading.depth == 0 {
    watch_reading.sets.clear()
  }
  watch_reading.depth += 1
  self.set_by.clear()
  e.deps_tail = None
  e.flags = WATCHING | RECURSED_CHECK
  let prev_sub = set_active_sub(Some(e))
  run.cycle += 1
  let v = f()
  run.active_sub = prev_sub
  watch_reading.depth -= 1
  e.flags = e.flags & RECURSED_CHECK.lnot()
  purge_deps(e)
  self.stale.val = false
  // (what it read set again as it ran, after it was read: told then as what reads it is, the run still going)
  if (e.flags & (DIRTY | PENDING)) != 0 {
    let dirty = (e.flags & DIRTY) != 0 ||
      (match e.deps {
        Some(d) => check_dirty(d, e)
        None => false
      })
    e.flags = WATCHING
    if dirty {
      for s in watch_reading.sets {
        self.set_by.push(s)
      }
      let told : () -> Unit = coerce(e.own)
      told()
    }
  }
  v
}

///|
/// Where values were set as the last read ran, where what it read changed as it ran (the first few; none where it did
/// not): what changed what it read as it read.
pub fn Watch::set_as_read(self : Watch) -> Array[String] {
  self.set_by.copy()
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
  self.stale.val
}

///|
/// The watch stale, as though what it read changed (`changed` not called): read anew before it is relied on.
pub fn Watch::touch(self : Watch) -> Unit {
  self.stale.val = true
}

///|
/// The watch let go of what it read: it follows nothing, and is stale.
pub fn Watch::stop(self : Watch) -> Unit {
  effect_scope_oper(self.node)
  self.stale.val = true
}

///|
/// Where a signal was last set to another value (Signal::set's caller): what a watch told as it is set says what told
/// it (frame_watch.mbt's layout watch).
// kept across runs: written by each set
let set_at : Ref[SourceLoc?] = Ref(None)

///|
/// Where a signal was last set to another value, as words ("" none).
pub fn last_set_at() -> String {
  match set_at.val {
    Some(l) => l.to_string()
    None => ""
  }
}
