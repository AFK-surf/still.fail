// A retained thumbnail names its own node. The viewer reads that node's current geometry when it opens or closes,
// including the scroll and motion of its holders; no old-view id or per-frame measurement is needed.

///|
let pv_tree_thumbs : Map[String, @signals.Signal[(@view.View, () -> ThumbLook)?]] = {}

///|
/// A thumbnail's current owner, followed by its key. Windowed rows can leave and come back with a new node while
/// the viewer is flying; readers must then follow that new node's geometry, including after an absent owner.
fn tree_thumb_owner(id : String) -> @signals.Signal[(@view.View, () -> ThumbLook)?] {
  match pv_tree_thumbs.get(id) {
    Some(cell) => cell
    None => {
      // As in signals.Keyed: absent owners needed by a flight stay observed; those nobody reads are let go.
      if pv_tree_thumbs.length() > 64 {
        let gone : Array[String] = []
        pv_tree_thumbs.each(fn(k, cell) {
          if !cell.watched() && @signals.untracked(fn() { cell.get() }) is None { gone.push(k) }
        })
        for k in gone { pv_tree_thumbs.remove(k) }
      }
      let cell : @signals.Signal[(@view.View, () -> ThumbLook)?] = @signals.signal(None)
      pv_tree_thumbs[id] = cell
      cell
    }
  }
}

///|
let pv_tree_lists : Map[String, (@view.View, () -> Double, () -> Double)] = {}

///|
pub fn note_thumb_node(
  node : @view.View,
  id : String,
  radius : () -> Double,
  picture : () -> String,
  letterbox? : () -> Bool = fn() { false },
  top_crop? : () -> Bool = fn() { false },
  list? : String = "",
  over? : (Double) -> Unit = fn(_) {  },
  said? : () -> String = fn() { "" },
) -> Unit {
  let look = fn() -> ThumbLook {
    { radius: radius(), letterbox: letterbox(), top_crop: top_crop(), picture: picture(), id: 0, list, over, said: said() }
  }
  let owner = tree_thumb_owner(id)
  owner.set(Some((node, look)))
  node.owns(@signals.effect(fn() {
    let r = radius()
    let p = picture()
    let l = letterbox()
    let crop = top_crop()
    let s = said()
    let changed = match pv_thumbs.get(id) { Some(was) => was.said != s; None => s != "" }
    pv_thumbs[id] = { radius: r, letterbox: l, top_crop: crop, picture: p, id: 0, list, over, said: s }
    if changed { thumbs_told.set(@signals.untracked(fn() { thumbs_told.get() }) + 1) }
  })) |> ignore
  node.owns(fn() {
    match @signals.untracked(fn() { owner.get() }) {
      Some((held, _)) if held.id() == node.id() => {
        pv_thumbs.remove(id)
        owner.set(None)
        if !owner.watched() { pv_tree_thumbs.remove(id) }
      }
      _ => ()
    }
  }) |> ignore
}

///|
/// How much of a retained message list's top and foot is covered by its bar and composer. Read when a thumbnail
/// flies, so a composer changing height leaves the same list and its thumbnails registered.
pub fn note_list_node(node : @view.View, key : String, bar : () -> Double, room : () -> Double) -> Unit {
  pv_tree_lists[key] = (node, bar, room)
  node.owns(fn() {
    match pv_tree_lists.get(key) {
      Some((held, _, _)) if held.id() == node.id() => pv_tree_lists.remove(key)
      _ => ()
    }
  }) |> ignore
}

///|
fn tree_thumb_of(c : @ui.Ctx, node : @view.View, look : () -> ThumbLook, laid? : @view.Laid) -> Thumb? {
  // Follow placement even while it is laid out nowhere, so showing the same node again tells its readers (but where it
  // is read as a frame is painted, `laid`: where it is drawn in that frame, Laid::drawn, nothing followed).
  if laid is None {
    ignore(node.owed_drawn_window())
  }
  guard node.alive() && !node.shown_nowhere() else { return None }
  guard @ui.view_tree() is Some(tree) else { return None }
  let l = look()
  let (x, y, w, h) = match laid {
    Some(laid) =>
      match laid.drawn(node) {
        Some(r) => r
        None => return None
      }
    None =>
      match tree.drawn_of(node.id()) {
        Some(drawn) => (drawn.x, drawn.y, drawn.w, drawn.h)
        None => return None
      }
  }
  guard w > 0.0 && h > 0.0 && x < c.width && x + w > 0.0 && y < c.height && y + h > 0.0 else { return None }
  let bounds = tree.seen_bounds(node.id(), drawing=true)
  let (left, top) = (dmax(x, bounds.0), dmax(y, bounds.1))
  let (right, foot) = (dmin(x + w, bounds.2), dmin(y + h, bounds.3))
  let scale = node.drawn_scale()
  let corners = match tree.drawn_of(node.id()) {
    Some(d) => match d.corners {
      Some((a, b, c, e)) => @motion.MeasuredCorners::from_each((a * scale, b * scale, c * scale, e * scale))
      None => @motion.MeasuredCorners::uniform(l.radius * scale)
    }
    None => @motion.MeasuredCorners::uniform(l.radius * scale)
  }
  Some({ x, y, w, h, corners, letterbox: l.letterbox, top_crop: l.top_crop, picture: l.picture,
    seen: Some((left, top, dmax(0.0, right - left), dmax(0.0, foot - top))), over: l.over,
    clear: match pv_tree_lists.get(l.list) {
      Some((list, bar, room)) if list.alive() => {
        let (_, ly, _, lh) = list.rect()
        Some((ly + bar(), ly + lh - room()))
      }
      _ => None
    },
  })
}
