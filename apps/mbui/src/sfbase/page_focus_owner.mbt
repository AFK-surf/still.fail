// Focus scopes belong to navigation entries, while the owner belongs to the window's signed-in tree and survives a
// shell being replaced. A page lends its entry's scope before it makes its retained controls.

///|
pub struct PageFocusOwner {
  scopes : Map[Int, @sf.PageFocusScope]
  live : Map[Int, Int]
  replacing : Ref[Int?]
}

///|
// kept across runs: each signed-in tree lends its own owner and releases it with that tree
let page_focus_owner_lent : @view.Lent[PageFocusOwner] = @view.Lent::new()

///|
pub fn page_focus_owner(parent : @view.View) -> PageFocusOwner {
  let owner : PageFocusOwner = { scopes: {}, live: {}, replacing: Ref(None) }
  parent.lends(page_focus_owner_lent, owner) |> ignore
  owner
}

///|
/// Lend the entry's scope to a page. Two pages with equal control keys cannot return one another's focus.
pub fn page_focus_entry(parent : @view.View, entry : Int) -> Unit {
  guard parent.lent(page_focus_owner_lent) is Some(owner) else { return }
  let scope = match owner.scopes.get(entry) {
    Some(existing) => existing
    None => {
      let made = @sf.PageFocusScope::new()
      owner.scopes[entry] = made
      made
    }
  }
  owner.live[entry] = owner.live.get(entry).unwrap_or(0) + 1
  scope.lend(parent)
  parent.owns(fn() {
    let remaining = owner.live.get(entry).unwrap_or(1) - 1
    if remaining > 0 {
      owner.live[entry] = remaining
    } else {
      owner.live.remove(entry) |> ignore
      if owner.replacing.val != Some(entry) {
        scope.cancel()
        owner.scopes.remove(entry) |> ignore
      }
    }
  }) |> ignore
}

///|
/// Capture before replacing a shell, keeping the scope even if another replacement precedes its new control.
pub fn PageFocusOwner::replace(self : PageFocusOwner, entry : Int) -> Bool {
  match self.scopes.get(entry) {
    Some(scope) => {
      let carrying = scope.capture()
      if carrying {
        self.replacing.val = Some(entry)
      } else if self.replacing.val == Some(entry) {
        self.replacing.val = None
      }
      carrying
    }
    None => false
  }
}

///|
/// Leaving the entry is different from replacing its shell: no pending return may follow it to another page.
pub fn PageFocusOwner::leave(self : PageFocusOwner, entry : Int) -> Unit {
  match self.scopes.get(entry) {
    Some(scope) => scope.cancel()
    None => ()
  }
  if self.replacing.val == Some(entry) {
    self.replacing.val = None
  }
  if self.live.get(entry).unwrap_or(0) == 0 {
    self.scopes.remove(entry) |> ignore
  }
}
