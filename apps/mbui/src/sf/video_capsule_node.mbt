///|
/// The video's duration and download capsule, with the same measurements and two-stage fade as video_capsule.
/// Its wider label keeps its room until it has gone; the incoming label has its whole room before it appears.
pub fn video_capsule_node(
  parent : @view.View,
  duration : () -> Double,
  coming? : () -> Double? = fn() { None },
  corner? : Double = message_file_corner,
) -> Unit {
  parent.box(fn(foot) {
    let part = @signals.signal(@signals.untracked(coming).unwrap_or(0.0))
    let way = EdgeWay::new(if @signals.untracked(coming) is Some(_) { 1.0 } else { 0.0 })
    foot.reacts(coming, fn(now) {
      if now is Some(p) { part.set(p) }
      way.go(foot, if now is Some(_) { 1.0 } else { 0.0 }, dur_ms)
    })
    foot.owns(fn() { (way.due)() }) |> ignore
    let k = fn() { way.shown(foot) }
    let length = fn() { if duration() > 0.0 { clock(duration()) } else { "" } }
    let share = fn() { "\{(dmin(1.0, dmax(0.0, part.get())) * 100.0).floor().to_int()}%" }
    let gap = @ui.Space::px(S1)
    let end = @ui.Space::px(S1_5)
    let across = fn() {
      @ui.font_scale() |> ignore
      @ui.tree_theme() |> ignore
      let c = @ui.current()
      let words = length()
      let length_w = c.fitting_width(
        if words != "" { c.words_across(words, video_capsule_words) } else { 0.0 },
        if words != "" { [video_capsule_mark, gap, end, end] } else { [video_capsule_mark, end, end] },
      )
      let share_w = c.fitting_width(c.words_across(share(), video_capsule_words), [video_capsule_ring, gap, end, end])
      let p = k()
      let width_way = if length_w >= share_w { dmax(0.0, 2.0 * p - 1.0) } else { dmin(1.0, 2.0 * p) }
      length_w + (share_w - length_w) * @ui.Ease::Move.at(width_way)
    }
    let inset = if corner == message_file_corner {
      capsule_in(message_file_corner, video_capsule_h)
    } else {
      capsule_fit(corner, video_capsule_h, video_capsule_alone_in)
    }
    foot.over(Is(true))
    .width(By(fn() { parent.laid_size_told().map(fn(z) { z.0 }) }))
    .height(By(fn() { parent.laid_size_told().map(fn(z) { z.1 }) }))
    .lies_along(Is(End)).lines_up(Is(Some(Start)))
    .padding(Is((inset, inset, inset, inset))) |> ignore
    foot.box(fn(cap) {
      cap.width(By(fn() { Some(across()) })).height(Is(Some(video_capsule_h)))
      .radius(Is(video_capsule_h / 2.0)).ground(By(fn() { @ui.tree_theme().color(video_shade) })) |> ignore
      cap.box(fn(row) {
        row.row(Is(true)).height(Is(Some(video_capsule_h)))
        .padding(Is((end, 0.0, end, 0.0))).gap(Is(gap)).lines_up(Is(Some(Middle)))
        .alpha(By(fn() { dmax(0.0, 1.0 - 2.0 * k()) })) |> ignore
        icon_node(row, "play", video_capsule_mark, Is(white)) |> ignore
        row.show(fn() { length() != "" }, fn(words) {
          words_node(words, length, fn() { video_capsule_words }) |> ignore
        })
      }) |> ignore
      cap.box(fn(row) {
        row.over(Is(true)).row(Is(true)).height(Is(Some(video_capsule_h)))
        .width(By(fn() { Some(across()) }))
        .padding(Is((end, 0.0, end, 0.0))).gap(Is(gap)).lines_up(Is(Some(Middle)))
        .alpha(By(fn() { dmax(0.0, 2.0 * k() - 1.0) })) |> ignore
        row.box(fn(ring) {
          ring.width(Is(Some(video_capsule_ring))).height(Is(Some(video_capsule_ring)))
          .shapes(By(fn() { ring_shapes(video_capsule_ring, part.get(), white) })) |> ignore
        }) |> ignore
        words_node(row, share, fn() { video_capsule_words }) |> ignore
      }) |> ignore
    }) |> ignore
  }) |> ignore
}
