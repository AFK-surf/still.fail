// A cap whose overflow is remembered by the layout that actually placed it, without publishing a layout result as a
// signal. It is for a container which stays at its cap after its contents have once exceeded it.

///|
pub struct LayoutCap {
  priv mut reached : Bool
  priv pending : Array[(View, Bool)]
}

///|
/// A fresh cap. Keep it with the owning presentation if its layout may be replaced while it is open; independent
/// capped regions each keep their own.
pub fn LayoutCap::new() -> LayoutCap {
  { reached: false, pending: [] }
}

///|
/// `natural` capped at `most`. Once the placed layout has seen it exceed `most`, this cap stays at `most`, including
/// when its contents become short or `most` changes. The transition itself changes no result in the layout that
/// observes it: an overflowing natural size was already capped. A provisional layout
/// that is replaced or left out does not set it. No signal or reactive binding is changed by the layout.
pub fn Layout::sticky_cap(self : Layout, cap : LayoutCap, natural : Double, most : Double) -> Double {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout cap is only used inside its own layout callback")
  }
  if !cap.reached {
    let owner = self.owner
    let id = owner.id()
    let tree = owner.tree
    let same_owner = fn(other : View) { physical_equal(other.tree, tree) && other.id() == id }
    match cap.pending.search_by(fn(p) { same_owner(p.0) }) {
      Some(i) => cap.pending[i] = (owner, natural > most)
      None => cap.pending.push((owner, natural > most))
    }
    // The last proposal belongs to the layout that was placed, after every pass and provisional measurement. No
    // reactive state is written, and the cap cannot change the result of the layout which first reaches it.
    tree.said_after_laid(fn() {
      match cap.pending.search_by(fn(p) { same_owner(p.0) }) {
        Some(i) => {
          let (_, exceeded) = cap.pending.remove(i)
          if tree.alive_id(id) && !tree.out_at(id.at) && exceeded { cap.reached = true }
        }
        None => ()
      }
    })
  }
  if cap.reached { most } else { dmin(natural, most) }
}
