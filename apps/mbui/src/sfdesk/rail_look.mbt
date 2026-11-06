// The rail's selected and pointed looks belong to the wide frame's timeline. Its old drawing only samples them:
// returning from another page without drawing in between must not start the rail's transition on that late frame.

///|
priv struct RailLook {
  id : @signals.Signal[Int]
  on : @motion.Way
  hover : @motion.Way
  ink : @motion.Way
}

///|
/// Each declared place owns its ways and subscriptions; removing it or the frame lets those go together. The old
/// control lends its input id when first built, in its own scope. Its workspace and selection are read at each cause,
/// never captured from a previous build of that control.
fn rail_looks(parent : @view.View, src : Source) -> Map[String, RailLook] {
  let looks : Map[String, RailLook] = {}
  parent.box(fn(owner) {
    owner.over(Is(true)) |> ignore
    owner.each(fn() {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => {
          let places = rail_shown(src, w)
          if !places.contains("settings") { places.push("settings") }
          places
        }
        None => []
      }
    }, fn(place) { place }, fn(n, place) {
      let key = place.get()
      let selected = fn() {
        if key == "settings" {
          lit_place() == "settings"
        } else {
          match @sfbase.workspace_in_view(src).0 {
            Some(w) => rail_lit(src, w, key) || (key == "attention" && wide.attention_open.get())
            None => false
          }
        }
      }
      let initial = if @signals.untracked(selected) { 1.0 } else { 0.0 }
      let look : RailLook = {
        id: @signals.signal(0, same=fn(a, b) { a == b }),
        on: @motion.Way::new(initial),
        hover: @motion.Way::new(0.0),
        ink: @motion.Way::new(initial),
      }
      looks[key] = look
      n.owns(fn() { looks.remove(key) |> ignore }) |> ignore
      n.reacts(fn() {
        let id = look.id.get()
        (selected(), id != 0 && @ui.current().lit(id))
      }, fn(state) {
        let (on, hover) = state
        let at = n.cause_at()
        rail_look_go(look.on, on, at)
        rail_look_go(look.hover, hover, at)
        rail_look_go(look.ink, on || hover, at)
      })
    })
  }) |> ignore
  looks
}

///|
fn rail_look_go(way : @motion.Way, on : Bool, at : Double) -> Unit {
  let target = if on { 1.0 } else { 0.0 }
  if way.target() != target { way.go(target, nav_fade, at~) }
}
