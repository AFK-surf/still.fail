// alien-signals' reactive graph (https://github.com/stackblitz/alien-signals 3.2.1, src/system.ts; MIT, Copyright (c)
// 2024-present Johnson Chu), ported line for line: what reads what (a node's deps, a node's subs, each edge a Link in
// both lists), a change pushed down as Pending / Dirty (propagate, shallowPropagate) and pulled back up as what is read
// checks whether what it read changed (checkDirty). Its three callbacks (update, notify, unwatched) are signals.mbt's,
// called here by name: the system is made once (createReactiveSystem), not a value passed round.

///|
/// A node of the graph (ReactiveNode): a signal, a computed, an effect, a scope or a trigger's reader, by `kind`, and
/// what index.ts's node of that kind holds besides the graph's fields (a signal's values, a computed's getter and value,
/// an effect's fn), its `own`, as one object: a signal and a computed are their node.
pub struct ReactiveNode {
  priv mut deps : Link?
  priv mut deps_tail : Link?
  priv mut subs : Link?
  priv mut subs_tail : Link?
  priv mut flags : Int
  priv kind : NodeKind
  /// an effect's fn, a watch's own (NoOwn for a signal's, a computed's, a scope's and a trigger's: a signal's and a
  /// computed's state is its Signal's and Computed's, and its update's)
  priv own : Own
  /// a signal's or a computed's update of its own (updateSignal, updateComputed), over its state
  priv update : ((ReactiveNode) -> Bool)?
  /// an effect's cleanup, as its fn returned it (EffectNode.cleanup)
  priv mut cleanup : (() -> Unit)?
  /// not alien-signals': whether what it reads, or it, holds something outside while it is read (a resource told as
  /// its last reader leaves: Signal::on_unwatched, computed_scoped), once it has; so what reads it does (holds_up). For
  /// rest: what holds nothing keeps what it read at rest
  priv mut holds : Bool
}

///|
/// What a node is (the fields index.ts tells them apart by: `getter`, `currentValue`, `fn`): a signal, a computed, an
/// effect, a scope, a trigger's reader (neither: as a scope, index.ts's last case).
enum NodeKind {
  SignalNode
  ComputedNode
  EffectNode
  ScopeNode
  TriggerNode
  /// a watch (signals.mbt's Watch): told, it calls its own (a `() -> Unit`), what it read still followed
  WatchNode
}

///|
/// What a node holds besides the graph's fields that is not a value of a type of its own: an effect's fn, a watch's
/// own (signals.mbt's WatchOwn). (A signal's and a computed's state, of their value's type, are held by their Signal and
/// Computed and their update: as one reference of another type (`%identity`) the Wasm GC's types do not take it.)
priv enum Own {
  NoOwn
  EffectOwn(() -> (() -> Unit)?)
  WatchOwned(WatchOwn)
}

///|
/// An edge: `sub` read `dep` (Link), in `dep`'s subs and `sub`'s deps both; `version` the cycle it was read in.
struct Link {
  mut version : Int
  dep : ReactiveNode
  sub : ReactiveNode
  mut prev_sub : Link?
  mut next_sub : Link?
  mut prev_dep : Link?
  mut next_dep : Link?
}

///|
/// The frames checkDirty and propagate stack up as they go down (index.ts's Stack, a list of them): an array each,
/// kept, where index.ts makes a frame an object, under reference counting a malloc and a free a level. A call works
/// above where it found its array's end and leaves it there (what checkDirty updates may check again, inside).
let check_frames : Array[Link?] = []

///|
/// (propagate's frames that would hold no link, which it would only step over, left out)
let propagate_frames : Array[Link?] = []

///|
/// ReactiveFlags.
pub const NONE : Int = 0

///|
pub const MUTABLE : Int = 1

///|
pub const WATCHING : Int = 2

///|
pub const RECURSED_CHECK : Int = 4

///|
pub const RECURSED : Int = 8

///|
pub const DIRTY : Int = 16

///|
pub const PENDING : Int = 32

///|
fn ReactiveNode::new(
  flags : Int,
  kind : NodeKind,
  own? : Own = NoOwn,
  update? : (ReactiveNode) -> Bool,
) -> ReactiveNode {
  { deps: None, deps_tail: None, subs: None, subs_tail: None, flags, kind, own, update, cleanup: None, holds: false }
}

///|
fn link(dep : ReactiveNode, sub : ReactiveNode, version : Int) -> Unit {
  // (not alien-signals': what reads what holds, holds)
  if dep.holds && !sub.holds {
    holds_up(sub)
  }
  let prev_dep = sub.deps_tail
  if prev_dep is Some(p) && physical_equal(p.dep, dep) {
    return
  }
  let next_dep = match prev_dep {
    Some(p) => p.next_dep
    None => sub.deps
  }
  if next_dep is Some(n) && physical_equal(n.dep, dep) {
    n.version = version
    sub.deps_tail = next_dep
    return
  }
  let prev_sub = dep.subs_tail
  if prev_sub is Some(p) && p.version == version && physical_equal(p.sub, sub) {
    return
  }
  let new_link = { version, dep, sub, prev_dep, next_dep, prev_sub, next_sub: None }
  sub.deps_tail = Some(new_link)
  dep.subs_tail = Some(new_link)
  match next_dep {
    Some(n) => n.prev_dep = Some(new_link)
    None => ()
  }
  match prev_dep {
    Some(p) => p.next_dep = Some(new_link)
    None => sub.deps = Some(new_link)
  }
  match prev_sub {
    Some(p) => p.next_sub = Some(new_link)
    None => dep.subs = Some(new_link)
  }
}

///|
/// Not alien-signals': `node` holds (ReactiveNode's `holds`), and so does what reads it, and what reads that.
fn holds_up(node : ReactiveNode) -> Unit {
  node.holds = true
  let mut l = node.subs
  while l is Some(link) {
    if !link.sub.holds {
      holds_up(link.sub)
    }
    l = link.next_sub
  }
}

///|
/// `link` taken out of both its lists (its sub, `sub`: link.sub where index.ts leaves it out); the dep it leaves with
/// no sub at all is unwatched. Its next in the sub's deps.
fn unlink(link : Link, sub : ReactiveNode) -> Link? {
  let dep = link.dep
  let prev_dep = link.prev_dep
  let next_dep = link.next_dep
  let next_sub = link.next_sub
  let prev_sub = link.prev_sub
  match next_dep {
    Some(n) => n.prev_dep = prev_dep
    None => sub.deps_tail = prev_dep
  }
  match prev_dep {
    Some(p) => p.next_dep = next_dep
    None => sub.deps = next_dep
  }
  match next_sub {
    Some(n) => n.prev_sub = prev_sub
    None => dep.subs_tail = prev_sub
  }
  match prev_sub {
    Some(p) => p.next_sub = next_sub
    None => {
      dep.subs = next_sub
      if next_sub is None {
        unwatched(dep)
      }
    }
  }
  next_dep
}

///|
fn propagate(start : Link, inner_write : Bool) -> Unit {
  let mut link = start
  let mut next = link.next_sub
  let base = propagate_frames.length()
  while true {
    let sub = link.sub
    let mut flags = sub.flags
    if (flags & (RECURSED_CHECK | RECURSED | DIRTY | PENDING)) == 0 {
      sub.flags = flags | PENDING
      if inner_write {
        sub.flags = sub.flags | RECURSED
      }
    } else if (flags & (RECURSED_CHECK | RECURSED)) == 0 {
      flags = NONE
    } else if (flags & RECURSED_CHECK) == 0 {
      sub.flags = (flags & RECURSED.lnot()) | PENDING
    } else if (flags & (DIRTY | PENDING)) == 0 && is_valid_link(link, sub) {
      sub.flags = flags | (RECURSED | PENDING)
      flags = flags & MUTABLE
    } else {
      flags = NONE
    }
    if (flags & WATCHING) != 0 {
      notify(sub)
    }
    if (flags & MUTABLE) != 0 {
      match sub.subs {
        Some(sub_subs) => {
          link = sub_subs
          let next_sub = sub_subs.next_sub
          if next_sub is Some(_) {
            if next is Some(n) {
              propagate_frames.push(Some(n))
            }
            next = next_sub
          }
          continue
        }
        None => ()
      }
    }
    match next {
      Some(n) => {
        link = n
        next = n.next_sub
        continue
      }
      None => ()
    }
    if propagate_frames.length() > base {
      let i = propagate_frames.length() - 1
      let l = propagate_frames[i].unwrap()
      propagate_frames[i] = None
      propagate_frames.pop() |> ignore
      link = l
      next = l.next_sub
      continue
    }
    break
  }
}

///|
fn check_dirty(start : Link, start_sub : ReactiveNode) -> Bool {
  let mut link = start
  let mut sub = start_sub
  let mut check_depth = 0
  let mut dirty = false
  while true {
    let dep = link.dep
    let flags = dep.flags
    if (sub.flags & DIRTY) != 0 {
      dirty = true
    } else if (flags & (MUTABLE | DIRTY)) == (MUTABLE | DIRTY) {
      // (its subs as they were before it updated: what it did as it updated may have let go of them, `subs!`
      // read only if it changed)
      let subs = dep.subs
      if update(dep) {
        if subs is Some(subs) && subs.next_sub is Some(_) {
          shallow_propagate(subs)
        }
        dirty = true
      }
    } else if (flags & (MUTABLE | PENDING)) == (MUTABLE | PENDING) {
      check_frames.push(Some(link))
      link = dep.deps.unwrap()
      sub = dep
      check_depth += 1
      continue
    }
    if !dirty {
      match link.next_dep {
        Some(n) => {
          link = n
          continue
        }
        None => ()
      }
    }
    let mut to_top = false
    while check_depth > 0 {
      check_depth -= 1
      let i = check_frames.length() - 1
      link = check_frames[i].unwrap()
      check_frames[i] = None
      check_frames.pop() |> ignore
      if dirty {
        let subs = sub.subs
        // The update below may have disconnected this entire computed chain. Do not run a computed that no longer
        // has a reader just because check_dirty still has one of its old links on the traversal stack.
        if subs is None {
          dirty = false
        } else if update(sub) {
          if subs is Some(subs) && subs.next_sub is Some(_) {
            shallow_propagate(subs)
          }
          sub = link.sub
          continue
        }
        dirty = false
      } else {
        sub.flags = sub.flags & PENDING.lnot()
      }
      sub = link.sub
      match link.next_dep {
        Some(n) => {
          link = n
          to_top = true
          break
        }
        None => ()
      }
    }
    if to_top {
      continue
    }
    return dirty && sub.flags != 0
  }
  false
}

///|
fn shallow_propagate(start : Link) -> Unit {
  let mut link = start
  while true {
    let sub = link.sub
    let flags = sub.flags
    if (flags & (PENDING | DIRTY)) == PENDING {
      sub.flags = flags | DIRTY
      if (flags & (WATCHING | RECURSED_CHECK)) == WATCHING {
        notify(sub)
      }
    }
    match link.next_sub {
      Some(n) => link = n
      None => break
    }
  }
}

///|
fn is_valid_link(check : Link, sub : ReactiveNode) -> Bool {
  let mut link = sub.deps_tail
  while true {
    match link {
      Some(l) => {
        if physical_equal(l, check) {
          return true
        }
        link = l.prev_dep
      }
      None => break
    }
  }
  false
}
