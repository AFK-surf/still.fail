// A log's active chain among entries that may branch (station/test/lock-fork-choice-model.ts `Keeper`): every entry
// whose parent is one that follows and that the log's rules take after it follows; the chain goes from the genesis hop
// by hop to the child the fork choice picks (rules/src/fork). Length is never compared. The entries may come in any
// order and with several children to a parent; the chain is the same whatever their order.

///|
/// Why an entry given is not on the active chain.
pub(all) enum Off {
  /// The log's rules refuse it after its parent: why.
  NotValid(String)
  /// Its parent is none of the entries that follow.
  NoParent
  /// Another child of its parent was chosen (its hash), by that step.
  Beaten(String, @fork.Step)
  /// It hangs below a child that was not chosen (its hash).
  Below(String)
  /// The same entry (its hash) with another signature that was taken first.
  Again
}

///|
/// A log's active chain: its entries from the genesis, their hashes, and for each entry given (by its place) that is not
/// on it, why.
pub(all) struct Chain {
  entries : Array[Json]
  /// Their places among the entries given.
  at : Array[Int]
  hashes : Array[String]
  off : Array[(Int, Off)]
}

///|
/// What one log's rules say, for choosing among its entries: the state its genesis starts, the state after an entry
/// (raising why not), and what the fork choice weighs of a child in its parent's state.
priv struct Log[S] {
  start : (Json) -> S raise LockError
  next : (S, Json) -> S raise LockError
  weight : (S, Json) -> Int
  removal : (S, Json) -> Bool
}

///|
/// The fork choice's tie value of a child: sha256 of its parent's hash and the id of the key that signed it.
pub fn tie_of(parent : String, key : String, c : &Crypto) -> String {
  c.sha256_hex(parent + "\u0000" + key)
}

///|
/// The step of the fork choice by which `a` comes before `b`, children of one parent (`ta`, `tb` their tie values,
/// `ha`, `hb` their hashes), or none.
pub fn before(wa : Int, ra : Bool, ta : String, ha : String, wb : Int, rb : Bool, tb : String, hb : String) -> @fork.Step? {
  let place = fn(x : String, y : String) -> (Int, Int) { if x < y { (0, 1) } else if x > y { (1, 0) } else { (0, 0) } }
  let (pta, ptb) = place(ta, tb)
  let (pha, phb) = place(ha, hb)
  @fork.step(wa, ra, pta, pha, wb, rb, ptb, phb)
}

///|
/// The places of `xs` in their text order (equal ones one place). MoonBit's `String` order puts a shorter text first;
/// tie values and hashes are all 64 hex digits, among which it is the text order JS's `<` has.
fn places(xs : Array[String]) -> FixedArray[Int] {
  let sorted = xs.copy()
  sorted.sort()
  let at : Map[String, Int] = Map([])
  for x in sorted {
    if !at.contains(x) {
      at[x] = at.length()
    }
  }
  FixedArray::makei(xs.length(), fn(i) { at.get(xs[i]).unwrap() })
}

///|
/// One entry that follows: its place among those given, its hash, and the state after it.
priv struct Node[S] {
  at : Int
  hash : String
  state : S
}

///|
/// The active chain of `entries` of one log from the genesis of hash `genesis`. Raises why there is none: the genesis
/// is not among them, or not one.
fn[S] active(entries : Array[Json], genesis : String, log : Log[S], c : &Crypto) -> Chain raise LockError {
  let off : Map[Int, Off] = Map([])
  let hashes : Array[String] = []
  for i, e in entries {
    let h = entry_hash(e, c) catch {
      Refused(why) | Refusal(why) => {
        off[i] = NotValid(why)
        ""
      }
    }
    hashes.push(h)
  }
  // The entries of each hash, a second signature after the first in the text order of the signatures: whichever order
  // they come in, the same one is taken.
  let sig_text = fn(i : Int) -> String { @form.canonical(sig_of(entries[i])) catch { _ => "" } }
  let by_hash : Map[String, Array[Int]] = Map([])
  let kids : Map[String, Array[String]] = Map([])
  for i, h in hashes {
    if h == "" {
      continue
    }
    match by_hash.get(h) {
      Some(xs) => xs.push(i)
      None => {
        by_hash[h] = [i]
        match text_of(field(Some(entries[i]), "prev")) {
          Some(p) =>
            match kids.get(p) {
              Some(ks) => ks.push(h)
              None => kids[p] = [h]
            }
          None => ()
        }
      }
    }
  }
  for _, xs in by_hash {
    xs.sort_by(fn(a, b) { sig_text(a).compare(sig_text(b)) })
  }
  // The first of `h`'s entries the rules take (`take`), the others again; none taken, each refused why.
  let first = fn(h : String, take : (Json) -> S raise LockError) -> Node[S]? {
    let mut got : Node[S]? = None
    for i in by_hash.get(h).unwrap() {
      if got is Some(_) {
        off[i] = Again
        continue
      }
      match (try Ok(take(entries[i])) catch { e => Err(e) }) {
        Ok(s) => got = Some({ at: i, hash: h, state: s })
        Err(Refused(why)) | Err(Refusal(why)) => off[i] = NotValid(why)
      }
    }
    got
  }
  guard by_hash.contains(genesis) else { raise Refused("no lock") }
  let root = match first(genesis, log.start) {
    Some(r) => r
    None =>
      match off.get(by_hash.get(genesis).unwrap()[0]) {
        Some(NotValid(why)) => raise Refused(why)
        _ => raise Refused("no lock")
      }
  }
  // Every entry that follows, parents first, with its children that follow.
  let nodes : Map[String, Node[S]] = Map([(genesis, root)])
  let children : Map[String, Array[Node[S]]] = Map([])
  let todo = [root]
  while true {
    guard todo.pop() is Some(p) else { break }
    let ks : Array[Node[S]] = []
    for h in kids.get(p.hash).unwrap_or([]) {
      if first(h, fn(e) { (log.next)(p.state, e) }) is Some(n) {
        nodes[h] = n
        ks.push(n)
        todo.push(n)
      }
    }
    children[p.hash] = ks
  }
  // The chain, hop by hop; each child not chosen beaten by the one that was.
  let chain = [root]
  let beaten : Array[String] = []
  while true {
    let p = chain[chain.length() - 1]
    guard children.get(p.hash) is Some(ks) && ks.length() > 0 else { break }
    let ws = FixedArray::makei(ks.length(), fn(i) { (log.weight)(p.state, entries[ks[i].at]) })
    let rs = FixedArray::makei(ks.length(), fn(i) { (log.removal)(p.state, entries[ks[i].at]) })
    let ties = ks.map(fn(k) { tie_of(p.hash, sig_key(entries[k.at]), c) })
    let ts = places(ties)
    let hs = places(ks.map(fn(k) { k.hash }))
    let b = @fork.best(ws, rs, ts, hs)
    for i, k in ks {
      if i != b {
        let by = @fork.step(ws[b], rs[b], ts[b], hs[b], ws[i], rs[i], ts[i], hs[i]).unwrap_or(@fork.Step::Hash)
        off[k.at] = Beaten(ks[b].hash, by)
        beaten.push(k.hash)
      }
    }
    chain.push(ks[b])
  }
  // What hangs below a child not chosen.
  for top in beaten {
    let below = children.get(top).unwrap_or([]).copy()
    while true {
      guard below.pop() is Some(n) else { break }
      off[n.at] = Below(top)
      for k in children.get(n.hash).unwrap_or([]) {
        below.push(k)
      }
    }
  }
  // The rest whose parent is none that follows (a second genesis among them).
  for i, h in hashes {
    if h != "" && !off.contains(i) && !(nodes.get(h) is Some(n) && n.at == i) {
      off[i] = if field(Some(entries[i]), "prev") is Some(Null) {
        NotValid("not the genesis this log is pinned to")
      } else {
        NoParent
      }
    }
  }
  let out : Array[(Int, Off)] = []
  for i in 0..<entries.length() {
    if off.get(i) is Some(o) {
      out.push((i, o))
    }
  }
  { entries: chain.map(fn(n) { entries[n.at] }), at: chain.map(fn(n) { n.at }), hashes: chain.map(fn(n) { n.hash }), off: out }
}

///|
/// What a signature weighs in the workspace's lock: by the signer's role in the parent's state (`roles`: an owner's 3, an
/// admin's 2, a member's or viewer's 1, no member's 0), or 1 for every one (`flat`).
pub(all) enum Votes {
  Flat
  Roles
}

///|
/// The workspace lock's active chain among `entries` (any order, branching) from its genesis of hash `root`: what
/// follows by `apply` (`now` as it has it), chosen by the fork choice with `votes`; a removal is a `device.remove` of a
/// device that signs. Raises why there is none.
pub fn lock_chain(entries : Array[Json], root : String, votes : Votes, now : Double?, c : &Crypto) -> Chain raise LockError {
  active(entries, root, {
    start: fn(e) { genesis(e, c) },
    next: fn(s, e) { apply(s, e, now, c) },
    weight: fn(s, e) {
      match votes {
        Flat => 1
        Roles =>
          match signer(s, sig_key(e), None) {
            Some(w) => if w.role == "owner" { 3 } else if w.role == "admin" { 2 } else { 1 }
            None => 0
          }
      }
    },
    removal: fn(s, e) {
      let v = Some(e)
      text_of(field(v, "kind")) == Some("device.remove") &&
      (s.devices.get(text_of(field(v, "body") |> field("id")).unwrap_or("")) is Some(d) && d.sign_key is Some(_))
    },
  }, c)
}

///|
/// A person log's active chain among `entries` (any order, branching) from its genesis of hash `root`: what follows
/// by the person's rules (`fold_person`), chosen by the fork choice with one vote a device; a removal is a
/// `device.remove`. Raises why there is none.
pub fn person_chain(entries : Array[Json], root : String, c : &Crypto) -> Chain raise LockError {
  active(entries, root, {
    start: fn(e) {
      let sub = text_of(field(Some(e), "body") |> field("sub")).unwrap_or("")
      person_step(None, e, sub, c)
    },
    next: fn(p, e) { person_step(Some(p), e, p.sub, c) },
    weight: fn(_, _) { 1 },
    removal: fn(_, e) { text_of(field(Some(e), "kind")) == Some("device.remove") },
  }, c)
}
