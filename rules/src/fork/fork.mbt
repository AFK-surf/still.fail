// The fork choice among the children of one parent in a log (a person's, or the workspace's lock), the order of
// Tailscale's Tailnet Lock (tailscale/tka `pickNextAUM`): the highest weight; equal, a removal; equal, the lowest tie
// value. The third step is ours (station/test/lock-fork-choice-model.ts `tie=signer`): sha256 of the parent's hash and
// the signing key's id, one value a signer and parent that nothing in the entry can vary; two children of one signer
// after one parent, by their hashes. What a child weighs, whether it is a removal and its tie value are the caller's
// (rules/src/lock/chain.mbt); here they are numbers: a tie value and a hash by their place in the text order of the
// children's own. Proved (fork.mbtp, `moon prove`): it is a strict total order on children of distinct hashes
// (`ahead_itself`, `ahead_both`, `ahead_through`, `ahead_either`), and `best` picks the one child that comes before
// every other (`best`, `same_choice`), so every keeper with the same children picks the same, in whatever order it
// has them. Not proved: that the text order of tie values and hashes is a total order (MoonBit's `String` compare), and
// what the caller weighs.

///|
/// The step of the fork choice that put one child before another.
pub(all) enum Step {
  Weight
  Removal
  Tie
  Hash
}

///|
/// Whether a child of weight `wa`, a removal or not (`ra`), with tie value `ta` and hash `ha` (their places in the text
/// order) comes before one of `wb`, `rb`, `tb`, `hb`.
#proof_pure
pub fn ahead(wa : Int, ra : Bool, ta : Int, ha : Int, wb : Int, rb : Bool, tb : Int, hb : Int) -> Bool {
  if wa > wb {
    true
  } else if wa < wb {
    false
  } else if ra && !rb {
    true
  } else if rb && !ra {
    false
  } else if ta < tb {
    true
  } else if ta > tb {
    false
  } else {
    ha < hb
  }
}

///|
/// The step by which the first child comes before the second, as `ahead` has them; none where it does not.
pub fn step(wa : Int, ra : Bool, ta : Int, ha : Int, wb : Int, rb : Bool, tb : Int, hb : Int) -> Step? {
  if !ahead(wa, ra, ta, ha, wb, rb, tb, hb) {
    None
  } else if wa != wb {
    Some(Weight)
  } else if ra != rb {
    Some(Removal)
  } else if ta != tb {
    Some(Tie)
  } else {
    Some(Step::Hash)
  }
}

///|
/// The child chosen among children of weights `ws`, removals `rs`, tie values `ts` and hashes `hs` (distinct), by its
/// index. Proved: it comes before every other child (and so, by `same_choice`, it is the one child that does: given in
/// another order, the same child is chosen).
pub fn best(ws : FixedArray[Int], rs : FixedArray[Bool], ts : FixedArray[Int], hs : FixedArray[Int]) -> Int where {
  proof_require: ws.length() > 0,
  proof_require: same_length(ws, rs, ts, hs),
  proof_require: distinct(hs),
  proof_ensure: result => chosen(ws, rs, ts, hs, result),
} {
  let mut b = 0
  for i = 1; i < ws.length(); i = i + 1 {
    if ahead(ws[i], rs[i], ts[i], hs[i], ws[b], rs[b], ts[b], hs[b]) {
      b = i
    }
  } where {
    proof_invariant: i >= 1,
    proof_invariant: i <= ws.length(),
    proof_invariant: in_range(i, b),
    proof_invariant: before_upto(ws, rs, ts, hs, b, i),
    proof_reasoning: #| i grows by one to the number of children
  }
  b
}

// What `ahead` is, proved of it for every value (these are its proofs; nothing calls them).

///|
/// Proved: no child comes before itself.
pub fn ahead_itself(w : Int, r : Bool, t : Int, h : Int) -> Bool where {
  proof_ensure: result => never(result),
} {
  ahead(w, r, t, h, w, r, t, h)
}

///|
/// Proved: of two children, not each comes before the other.
pub fn ahead_both(wa : Int, ra : Bool, ta : Int, ha : Int, wb : Int, rb : Bool, tb : Int, hb : Int) -> Bool where {
  proof_ensure: result => never(result),
} {
  ahead(wa, ra, ta, ha, wb, rb, tb, hb) && ahead(wb, rb, tb, hb, wa, ra, ta, ha)
}

///|
/// Proved: a child before one before a third comes before the third.
pub fn ahead_through(wa : Int, ra : Bool, ta : Int, ha : Int, wb : Int, rb : Bool, tb : Int, hb : Int, wc : Int, rc : Bool, tc : Int, hc : Int) -> Bool where {
  proof_require: ahead(wa, ra, ta, ha, wb, rb, tb, hb),
  proof_require: ahead(wb, rb, tb, hb, wc, rc, tc, hc),
  proof_ensure: result => holds(result),
} {
  ahead(wa, ra, ta, ha, wc, rc, tc, hc)
}

///|
/// Proved: of two children of distinct hashes, one comes before the other.
pub fn ahead_either(wa : Int, ra : Bool, ta : Int, ha : Int, wb : Int, rb : Bool, tb : Int, hb : Int) -> Bool where {
  proof_require: ha != hb,
  proof_ensure: result => holds(result),
} {
  ahead(wa, ra, ta, ha, wb, rb, tb, hb) || ahead(wb, rb, tb, hb, wa, ra, ta, ha)
}

///|
/// Proved: only one child comes before every other.
pub fn same_choice(ws : FixedArray[Int], rs : FixedArray[Bool], ts : FixedArray[Int], hs : FixedArray[Int], b : Int, c : Int) -> Bool where {
  proof_require: same_length(ws, rs, ts, hs),
  proof_require: chosen(ws, rs, ts, hs, b),
  proof_require: chosen(ws, rs, ts, hs, c),
  proof_ensure: result => holds(result),
} {
  b == c
}
