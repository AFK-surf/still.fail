// alien-signals' signals, computeds and effects (https://github.com/stackblitz/alien-signals 3.2.1, src/index.ts;
// MIT, Copyright (c) 2024-present Johnson Chu), ported line for line over system.mbt's graph. What differs is
// MoonBit's: a signal and a computed are values with `get` and `set` rather than functions bound to their node; an
// effect's cleanup is said by which of `effect` and `effect_cleanup` makes it; nothing throws, so nothing is put back
// in a `finally`; and "the same value" is `same` (physical_equal by default: index.ts's `!==`, but for strings, which it
// compares by their words: say `same=fn(a, b) { a == b }` where that matters). Added for what keeps its own computeds
// (docs/signals.md): Computed::peek, Computed::dispose, Signal::watched, untracked.

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
  queued: [],
}

///|
/// A signal (SignalNode): its value and the one set (pendingValue), what is the same as what.
pub struct Signal[T] {
  priv node : ReactiveNode
  priv state : SignalState[T]
}

///|
struct SignalState[T] {
  mut current : T
  mut pending : T
  same : (T, T) -> Bool
}

///|
/// A computed (ComputedNode): its getter, given the value it made last (none the first time), and that value.
pub struct Computed[T] {
  priv node : ReactiveNode
  priv state : ComputedState[T]
}

///|
struct ComputedState[T] {
  mut value : T?
  getter : (T?) -> T
  same : (T, T) -> Bool
}

// ── system.mbt's callbacks (createReactiveSystem's update, notify, unwatched) ─────────────────────────────

///|
fn update(node : ReactiveNode) -> Bool {
  match node.kind {
    ComputedNode(u) => u(node)
    SignalNode(u) => u(node)
    _ => {
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
    queued_put(insert_index, Some(effect))
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
/// queued[i] = e, the array grown as index.ts's is by its index.
fn queued_put(i : Int, e : ReactiveNode?) -> Unit {
  if i < run.queued.length() {
    run.queued[i] = e
  } else {
    run.queued.push(e)
  }
}

///|
fn unwatched(node : ReactiveNode) -> Unit {
  match node.kind {
    ComputedNode(_) =>
      if node.deps_tail is Some(_) {
        node.flags = MUTABLE | DIRTY
        dispose_all_deps_in_reverse(node)
      }
    // (nothing for signals: always mutable, never dirty until their pending value changes)
    SignalNode(_) => ()
    EffectNode(_) => effect_oper(node)
    ScopeNode | TriggerNode => effect_scope_oper(node)
  }
}

///|
/// Whether `dep` is neither a computed nor a signal (`!('getter' in dep) && !('currentValue' in dep)`).
fn effect_like(dep : ReactiveNode) -> Bool {
  match dep.kind {
    ComputedNode(_) | SignalNode(_) => false
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
pub fn[T] signal(initial : T, same? : (T, T) -> Bool = physical_equal) -> Signal[T] {
  let state = { current: initial, pending: initial, same }
  { node: ReactiveNode::new(MUTABLE, SignalNode(fn(n) { update_signal(n, state) })), state }
}

///|
/// A computed: `getter` worked out (given what it made last) as it is read after what it read changed.
pub fn[T] computed(getter : (T?) -> T, same? : (T, T) -> Bool = physical_equal) -> Computed[T] {
  let state = { value: None, getter, same }
  { node: ReactiveNode::new(NONE, ComputedNode(fn(n) { update_computed(n, state) })), state }
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
  let e = ReactiveNode::new(WATCHING | RECURSED_CHECK, EffectNode(f))
  let prev_sub = set_active_sub(Some(e))
  match prev_sub {
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
  e.flags = e.flags & RECURSED_CHECK.lnot()
  fn() { effect_oper(e) }
}

///|
/// A scope: what `fn` makes (effects) stopped together by the function returned.
pub fn effect_scope(f : () -> Unit) -> () -> Unit {
  let e = ReactiveNode::new(MUTABLE, ScopeNode)
  let prev_sub = set_active_sub(Some(e))
  match prev_sub {
    Some(p) => {
      link(e, p, 0)
      p.flags = p.flags | HAS_CHILD_EFFECT
    }
    None => ()
  }
  f()
  run.active_sub = prev_sub
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
    Some(old) => !(state.same)(old, value)
    None => true
  }
}

///|
fn[T] update_signal(s : ReactiveNode, state : SignalState[T]) -> Bool {
  s.flags = MUTABLE
  let was = state.current
  state.current = state.pending
  !(state.same)(was, state.current)
}

///|
fn run_effect(e : ReactiveNode) -> Unit {
  let flags = e.flags
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
    run.cycle += 1
    run.run_depth += 1
    match e.kind {
      EffectNode(f) => e.cleanup = f()
      _ => ()
    }
    run.run_depth -= 1
    run.active_sub = prev_sub
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
  let node = self.node
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
    if update(node) {
      match node.subs {
        Some(subs) => shallow_propagate(subs)
        None => ()
      }
    }
  } else if flags == 0 {
    node.flags = MUTABLE | RECURSED_CHECK
    let prev_sub = set_active_sub(Some(node))
    self.state.value = Some((self.state.getter)(None))
    run.active_sub = prev_sub
    node.flags = node.flags & RECURSED_CHECK.lnot()
  }
  match run.active_sub {
    Some(sub) => link(node, sub, run.cycle)
    None => ()
  }
  self.state.value.unwrap()
}

///|
/// The signal's value (signalOper read): what was set, once it is read after.
pub fn[T] Signal::get(self : Signal[T]) -> T {
  let node = self.node
  if (node.flags & DIRTY) != 0 {
    if update_signal(node, self.state) {
      match node.subs {
        Some(subs) => shallow_propagate(subs)
        None => ()
      }
    }
  }
  match run.active_sub {
    Some(sub) => link(node, sub, run.cycle)
    None => ()
  }
  self.state.current
}

///|
/// The signal set (signalOper write): what follows it told, unless it is the same as what was set.
pub fn[T] Signal::set(self : Signal[T], value : T) -> Unit {
  let state = self.state
  let changed = !(state.same)(state.pending, value)
  state.pending = value
  if changed {
    let node = self.node
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
  self.state.value
}

///|
/// The computed let go of what it read (as unwatched does with a computed nothing reads any more): what it read no
/// longer holds it, and it is worked out anew if it is read again.
pub fn[T] Computed::dispose(self : Computed[T]) -> Unit {
  unwatched(self.node)
}

///|
/// Whether anything reads the signal (a computed, an effect).
pub fn[T] Signal::watched(self : Signal[T]) -> Bool {
  self.node.subs is Some(_)
}

///|
/// What `f` makes, nothing it reads followed by what is reading now.
pub fn[T] untracked(f : () -> T) -> T {
  let prev_sub = set_active_sub(None)
  let v = f()
  run.active_sub = prev_sub
  v
}
