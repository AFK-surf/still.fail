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
/// The living showings of each id and how each looks, as they come: one file shown more than once in the same place
/// (placed twice in a message's words) is one id, each showing its node.
let pv_thumb_holders : Map[String, Array[(@view.View, () -> ThumbLook)]] = {}

///|
/// `node` (a thumbnail, note_thumb_node's) pressed: the thumbnail of `id` the viewer flies from and back into, the one
/// pressed of its showings, hidden alone while the viewer has its picture.
pub fn thumb_pressed(node : @view.View, id : String) -> Unit {
  guard pv_thumb_holders.get(id).unwrap_or([]).search_by(fn(h) { h.0.id() == node.id() }) is Some(i) else { return }
  let owner = tree_thumb_owner(id)
  match @signals.untracked(fn() { owner.get() }) {
    Some((n, _)) if n.id() == node.id() => ()
    _ => owner.set(Some(pv_thumb_holders[id][i]))
  }
}

///|
/// The viewer about to fly back into the thumbnail of `id`, the showing it flew from gone (its node let go, another
/// showing of the same place still here): the one of those seen on the window now (some of it drawn, not all cut off by
/// what holds it) first as they read (from the top, then from the left) takes its place; none seen, it fades out as
/// with no thumbnail.
fn thumb_settle(c : @ui.Ctx, id : String) -> Unit {
  let owner = tree_thumb_owner(id)
  guard @signals.untracked(fn() { owner.get() }) is None else { return }
  let mut best : ((Double, Double), (@view.View, () -> ThumbLook))? = None
  for h in pv_thumb_holders.get(id).unwrap_or([]) {
    match @signals.untracked(fn() { tree_thumb_of(c, h.0, h.1) }) {
      Some(t) if t.seen is Some((_, _, sw, sh)) && sw > 0.0 && sh > 0.0 =>
        match best {
          Some(((y, x), _)) if y < t.y || (y == t.y && x <= t.x) => ()
          _ => best = Some(((t.y, t.x), h))
        }
      _ => ()
    }
  }
  if best is Some((_, h)) {
    owner.set(Some(h))
  }
}

///|
/// Whether the viewer (open, or on its way back) flies from or back into the thumbnail of `id`.
fn viewer_on(id : String) -> Bool {
  pv_hidden.get() == id || [viewer.get(), pv_leaving.get()].iter().any(fn(v) { v.map(fn(v) { v.thumb_id() }) == Some(id) })
}

///|
/// How much of the thumbnail `node` of `id` shows: none while the viewer has its picture and it is the showing the
/// viewer flies from and back into, else all of it (another showing of the same place stays).
pub fn thumb_node_shows(node : @view.View, id : String) -> Double {
  if pv_hidden.get() != id {
    return 1.0
  }
  match tree_thumb_owner(id).get() {
    Some((n, _)) if n.id() == node.id() => 0.0
    _ => 1.0
  }
}

///|
let pv_tree_lists : Map[String, (@view.View, () -> Double, () -> Double)] = {}

///|
/// `node` as the thumbnail of `id` (as it changes: a file told again where it is kept is the same thumbnail under its
/// new id, the old one let go), drawn with `radius` and `picture`, while it lives.
pub fn note_thumb_node(
  node : @view.View,
  id : () -> String,
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
  // (the id it holds, let go: its place where this node still holds it, until the viewer settles another showing of
  // it still here (thumb_settle); with the last of its showings, what it looks like and its place, whichever went last)
  let held : Ref[String?] = Ref(None)
  let let_go = fn(k : String) {
    match pv_thumb_holders.get(k) {
      Some(hs) => {
        hs.retain(fn(h) { h.0.id() != node.id() })
        if hs.is_empty() { pv_thumb_holders.remove(k) }
      }
      None => ()
    }
    let owner = pv_tree_thumbs.get(k)
    match owner {
      Some(owner) =>
        match @signals.untracked(fn() { owner.get() }) {
          Some((n, _)) if n.id() == node.id() => owner.set(None)
          _ => ()
        }
      None => ()
    }
    if !pv_thumb_holders.contains(k) {
      pv_thumbs.remove(k)
      match owner {
        Some(owner) if !owner.watched() => pv_tree_thumbs.remove(k)
        _ => ()
      }
    }
  }
  node.owns(@signals.effect(fn() {
    let k = id()
    if held.val != Some(k) {
      @signals.untracked(fn() {
        match pv_thumb_holders.get(k) {
          Some(hs) => hs.push((node, look))
          None => pv_thumb_holders[k] = [(node, look)]
        }
        // (another showing of the same place, living, that the viewer flies from or back into keeps it: the one pressed;
        // that one gone, others of it still here, it is left to be settled among them all as the viewer shuts)
        let owner = tree_thumb_owner(k)
        let kept = match owner.get() {
          Some((n, _)) => n.id() != node.id() && n.alive() && viewer_on(k)
          None => viewer_on(k) && pv_thumb_holders.get(k).unwrap_or([]).iter().any(fn(h) { h.0.id() != node.id() })
        }
        if !kept {
          owner.set(Some((node, look)))
        }
        if held.val is Some(was) {
          // (the viewer follows the showing it flies from and back into only, before that is let go: letting go runs
          // what waits, another showing moving too among it, which must find the viewer on the new id)
          let owned = match pv_tree_thumbs.get(was) {
            Some(o) => o.get() is Some((n, _)) && n.id() == node.id()
            None => false
          }
          if owned {
            thumb_moved(was, k)
          }
          let_go(was)
        }
      })
      held.val = Some(k)
    }
    let r = radius()
    let p = picture()
    let l = letterbox()
    let crop = top_crop()
    let s = said()
    let changed = match pv_thumbs.get(k) { Some(was) => was.said != s; None => s != "" }
    pv_thumbs[k] = { radius: r, letterbox: l, top_crop: crop, picture: p, id: 0, list, over, said: s }
    if changed { thumbs_told.set(@signals.untracked(fn() { thumbs_told.get() }) + 1) }
  })) |> ignore
  node.owns(fn() {
    if held.val is Some(k) { let_go(k) }
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
    ignore(node.drawn_window_told())
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
