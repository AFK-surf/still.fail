// The frame's input targets alone (Ctx::targets): what a press, a pointer, a finger find where, as the frame is laid
// out, found as painting it would say them (in its order, cut by its clips, what holds what, what passes it on, what is
// drawn moved but taken where it is laid out), nothing drawn and nothing else kept of it; the paint after says none of
// them again (dr's `targets_said`). What the window's tree is told of a pointer (view_host.mbt) and what routes an input
// to the old views or the tree's nodes read the same targets, found before the tree is drawn.

///|
/// Node `i`'s targets (as Ctx::paint_node says them, drawing nothing): its own, where it takes presses or is pointed
/// at; its links' (rich words); its bar's thumb; what it holds, in its clip.
fn Ctx::node_targets(self : Ctx, i : Int, alpha_in : Double) -> Unit {
  let n = self.nodes[i]
  let alpha = alpha_in * n.opacity
  if alpha <= 0.002 {
    return
  }
  let k = clip_top()
  let cx0 = clip_stack[k]
  let cy0 = clip_stack[k + 1]
  let cx1 = clip_stack[k + 2]
  let cy1 = clip_stack[k + 3]
  // (outside the clip: what a box that does not cut holds, each where it is)
  if n.x > cx1 || n.y > cy1 || n.x + n.fw < cx0 || n.y + n.fh < cy0 {
    if !n.clip && (n.kind == kind_box || n.kind == kind_scroll) {
      self.paint_held(n, alpha)
    }
    return
  }
  // (a page's bones: nothing in them is pressed or pointed at)
  if n.bones != 0L && n.bone_whole {
    return
  }
  if (n.hit || n.points) && n.id != 0 && n.bones == 0L {
    if self.push_hit(n.id, dmax(n.x, cx0), dmax(n.y, cy0), dmin(n.x + n.fw, cx1), dmin(n.y + n.fh, cy1), marks=n.marks) &&
      n.points {
      self.point_said(n.id)
    }
  }
  if stops_wheel(n) {
    self.scroll_target(n, cx0, cy0, cx1, cy1)
  }
  if n.bones != 0L && n.kind != kind_box && n.kind != kind_scroll && n.kind != kind_list {
    return
  }
  if n.kind == kind_rich {
    self.rich_targets(n)
    return
  }
  if n.kind == kind_editor && editor_scrolls(n) {
    self.scroll_target(n, cx0, cy0, cx1, cy1)
  }
  // (a native view: where it is among the targets, what is said after it over it, its covers: NativeView::tell_covers)
  if n.kind == kind_native {
    match native_nodes.get(i) {
      Some((v, _, _)) if !v.closed && v.id != 0 => {
        v.hits_before = self.next_hit_ids.length()
        v.island = targets_island.val
      }
      _ => ()
    }
    return
  }
  if n.kind == kind_text ||
    n.kind == kind_editor ||
    n.kind == kind_image ||
    n.kind == kind_page {
    return
  }
  if scrolls(n) {
    self.scroll_target(n, cx0, cy0, cx1, cy1)
  }
  let clipped = n.clip
  if clipped {
    push_round_clip(n)
  }
  // (its bar where it runs, kept for the pointer near its edge, whether it shows or not: the frame's bars)
  let bar = if n.kind == kind_list || (n.sideways && n.id != 0) { self.bar_where(n) } else { None }
  match bar {
    Some(b) => self.next_bars.push(b)
    None => ()
  }
  let across_from = self.across_seen.length()
  self.paint_held(n, alpha)
  match bar {
    Some(b) if self.bar_shows(b) * alpha > 0.002 => self.bar_target(b)
    _ => ()
  }
  if n.kind == kind_list {
    self.across_targets(n, across_from, alpha)
  }
  if clipped {
    pop_clip()
  }
}

///|
/// Rich words `n`'s links' targets: each piece of each, on its line, in the clip (Ctx::paint_rich says them so).
fn Ctx::rich_targets(self : Ctx, n : Node) -> Unit {
  let lay = match n.rich_layout(dmax(n.fw - n.pad_l - n.pad_r, 0.0)) {
    Some(l) => l
    None => return
  }
  let r = match (n.rcut, n.rich) {
    (Some(r), _) | (None, Some(r)) => r
    _ => return
  }
  let ox = n.x + n.pad_l
  let oy = n.y + n.pad_t
  let k = clip_top()
  let cx0 = clip_stack[k]
  let cy0 = clip_stack[k + 1]
  let cx1 = clip_stack[k + 2]
  let cy1 = clip_stack[k + 3]
  for k, run in r.runs {
    if run.link == "" {
      continue
    }
    let id = link_id(r.base, r.runs, k)
    if id == 0 {
      continue
    }
    for p in lay.pieces(k) {
      let (l, c0, c1) = p
      let top = oy + lay.line_y[l]
      let (sx0, sx1) = lay.span_x(c0, c1)
      self.rich_link_target(id, ox + sx0, top, ox + sx1, top + lay.line_h[l], cx0, cy0, cx1, cy1)
    }
  }
}

///|
/// A piece of link `id` (x0 to x1 across, top to foot), in the clip (cx0 cy0 cx1 cy1): its target.
fn Ctx::rich_link_target(
  self : Ctx,
  id : Int,
  x0 : Double,
  top : Double,
  x1 : Double,
  foot : Double,
  cx0 : Double,
  cy0 : Double,
  cx1 : Double,
  cy1 : Double,
) -> Unit {
  // (a link is no node of its own: what was said of it as it was built, Ctx::mark_id)
  let marks = self.marks_ahead.get(id).unwrap_or(0)
  self.push_hit(id, dmax(x0, cx0), dmax(top, cy0), dmin(x1, cx1), dmin(foot, cy1), marks~) |> ignore
}

///|
/// The frame's targets where the window is a tree (view_host.mbt's view_paint), found before anything is drawn: each old
/// view's, in its place in the tree's order, the one the whole window its root's (what it put over all of it aside),
/// then what the old frame put over all of it at its root (its layers), in their order; each old view's kept with its
/// node (old_hits: placed where the tree has it as an input comes, cut to the window there, none while it takes no
/// presses: old_hits_place). Where the layers' begin among them.
fn Ctx::view_targets(self : Ctx, root : Int, tree : @view.Tree) -> Int {
  // (found as they were, nothing they are found from changed since: kept)
  let key = self.targets_key(tree)
  if targets_kept.found && !targets_kept.stale && targets_kept.key == key {
    self.targets_again()
    return targets_kept.layers_from
  }
  match targets_kept.watch {
    Some(w) => w.stop()
    None => ()
  }
  let watch = @signals.watch(fn() { targets_kept.stale = true })
  targets_kept.watch = Some(watch)
  targets_kept.stale = false
  let layers_from = watch.read(fn() { self.targets_found(root, tree) })
  targets_kept.key = key
  targets_kept.found = true
  targets_kept.layers_from = layers_from
  layers_from
}

///|
/// The targets found (Ctx::view_targets): where the layers' begin among them.
fn Ctx::targets_found(self : Ctx, root : Int, tree : @view.Tree) -> Int {
  targets_finds.val = targets_finds.val + 1
  let mode = dr.mode
  dr.mode = mode_hits
  next_old_hits.clear()
  tree.each_drawn(fn(c, _, _, a) {
    if c.id.at == 0 || a <= 0.002 || !c.hosted {
      return
    }
    targets_island.val = Some(c.id)
    if old_whole.val {
      let from = self.next_hit_ids.length()
      let scrolls_from = self.next_scroll_ids.length()
      let bars_from = self.next_bars.length()
      self.paint_held(self.nodes[root], 1.0, but=fn(ch) { self.nodes[ch].layer || self.nodes[ch].portal })
      next_old_hits.push({
        id: c.id,
        from,
        to: self.next_hit_ids.length(),
        scrolls_from,
        scrolls_to: self.next_scroll_ids.length(),
        bars_from,
        bars_to: self.next_bars.length(),
        x: 0.0,
        y: 0.0,
      })
    } else {
      match old_boxes.get(c.id) {
        Some(i) => {
          // (in no clip of the window's (island_clips), where it was laid out)
          let from = self.next_hit_ids.length()
          let scrolls_from = self.next_scroll_ids.length()
          let bars_from = self.next_bars.length()
          island_clips(fn() { self.paint(i, a) })
          next_old_hits.push({
            id: c.id,
            from,
            to: self.next_hit_ids.length(),
            scrolls_from,
            scrolls_to: self.next_scroll_ids.length(),
            bars_from,
            bars_to: self.next_bars.length(),
            x: self.nodes[i].x,
            y: self.nodes[i].y,
          })
        }
        None => ()
      }
    }
  })
  targets_island.val = None
  let layers_from = self.next_hit_ids.length()
  let mut ch = self.nodes[root].first
  while ch >= 0 {
    let n = self.nodes[ch]
    if (n.layer || n.portal) && !old_boxes.values().any(fn(i) { i == ch }) {
      self.paint(ch, 1.0)
    }
    ch = n.next
  }
  dr.mode = mode
  layers_from
}

///|
/// What scrolls or stops the wheel in `n` (cut to the clip cx0 cy0 cx1 cy1, where it is laid out): what the wheel and a
/// finger find there (the frame's scroll targets).
fn Ctx::scroll_target(self : Ctx, n : Node, cx0 : Double, cy0 : Double, cx1 : Double, cy1 : Double) -> Unit {
  self.next_scroll_ids.push(n.id)
  self.next_scroll_rects.push(dmax(n.x, cx0))
  self.next_scroll_rects.push(dmax(n.y, cy0))
  self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
  self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
}

///|
/// Whether `n` stops the wheel: a modal's ground (overlay.mbt), what says it stops it (Ctx::stop_wheel), what scrolls in
/// it (laid in it, later) still taking it first.
fn stops_wheel(n : Node) -> Bool {
  (n.blocks || n.stops_wheel) && n.id != 0 && n.bones == 0L
}

///|
/// Whether field `n` has words more than it shows: what the wheel and a finger scroll there, as a box kept to a height
/// (sideways.mbt).
fn editor_scrolls(n : Node) -> Bool {
  match sideways.get(n.id) {
    Some(sw) => sw.max > 0.0
    None => false
  }
}

///|
/// Whether `n` scrolls or is dragged its own way: a list, a pager, a drag, a capture, what scrolls sideways.
fn scrolls(n : Node) -> Bool {
  n.kind == kind_list ||
  (
    n.id != 0 &&
    (pagers.contains(n.id) || drags.contains(n.id) || captures.contains(n.id) || sideways.contains(n.id))
  )
}

///|
/// What the frame's targets were last found from (Ctx::view_targets): the old frame's builds and layout as committed,
/// what of it was moved by what moves it, what of the tree's is where (Tree::hits_said), whether the one old view is the
/// whole window, the hand; and whether what finding them read (a bar's showing, its clock) was told changed since
/// (`stale`, by their `watch`). Where the layers' begin among them.
priv struct TargetsKept {
  mut found : Bool
  mut key : (Int, Int, Int, Int, Bool, Bool)
  mut stale : Bool
  mut watch : @signals.Watch?
  mut layers_from : Int
}

///|
// kept across runs: put back as a run begins (targets_forget)
let targets_kept : TargetsKept = {
  found: false,
  key: (0, 0, 0, 0, false, false),
  stale: true,
  watch: None,
  layers_from: 0,
}

///|
/// Found anew from the next frame on (a run begins, the tree is let go).
fn targets_forget() -> Unit {
  match targets_kept.watch {
    Some(w) => w.stop()
    None => ()
  }
  targets_kept.watch = None
  targets_kept.found = false
  targets_kept.stale = true
  targets_island.val = None
}

///|
/// What the frame's targets are found from, as of now (TargetsKept's `key`).
fn Ctx::targets_key(self : Ctx, tree : @view.Tree) -> (Int, Int, Int, Int, Bool, Bool) {
  (
    self.build_no,
    commit_counts[0] + commit_counts[1] + commit_counts[2],
    moves_said.val,
    tree.hits_said(),
    old_whole.val,
    pointing() is Mouse,
  )
}

///|
/// The frame's targets as they were last found, said again for this frame (what they are found from the same): those
/// of the old views as painted, before they were placed where the tree has them (old_hits_framed), what scrolls, the
/// bars; each old view's place among them as it was.
fn Ctx::targets_again(self : Ctx) -> Unit {
  next_old_hits.append(old_hits)
  self.next_hit_ids.append(self.hit_ids)
  self.next_hit_marks.append(self.hit_marks)
  self.next_hit_ends.append(self.hit_ends)
  self.next_hit_rects.append(old_hits_rects)
  self.next_hit_clips.append(old_hits_clips)
  self.points.each(fn(k, v) { self.next_points[k] = v })
  self.passes.each(fn(k, v) { self.next_passes[k] = v })
  self.next_scroll_ids.append(self.scroll_ids)
  self.next_scroll_rects.append(old_scrolls_rects)
  self.next_bars.append(old_bars)
}

///|
/// How many times the frame's targets were found anew (Ctx::targets_found), so far: for a test to say a frame found
/// none.
// kept across runs: only ever counted on
let targets_finds : Ref[Int] = Ref(0)

///|
/// The node of the window's tree hosting the old view whose targets are being found (none: none, or no tree).
let targets_island : Ref[@view.NodeId?] = Ref(None)
