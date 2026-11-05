// The header owns its title, people, agents and controls in one layout. The
// title's limit is a share of this allocation, not last frame's published width.

///|
fn chat_bar_layout(
  row : @view.View,
  back : @view.View,
  cells : Map[String, @view.View],
  actions : @view.View,
  parts : () -> Array[(String, Int)],
  insets : () -> (Double, Double, Double, Double, Double, Bool),
) -> Unit {
  row.layout(By(fn() { (parts(), insets()) }), fn(inputs, space) {
    let (parts, (left, right, before, after, top, has_actions)) = inputs
    let width = space.width().unwrap_or(space.max_width().unwrap_or(0.0))
    let height = space.height().unwrap_or(@sf.wide_bar_h + top)
    let start = dmax(0.0, before)
    let end = width - after - dmin(0.0, before)
    let background = space.measure(back, width=dmax(0.0, end - start), height~)
    let placed = [background.at(start, 0.0)]
    let controls = space.measure(actions, max_width=None, max_height=None)
    let (cw, ch) = controls.size()
    let y = top + (height - top - 1.0) / 2.0
    let gap = @ui.Space::px(S2_5)
    let x0 = start + left + @ui.Space::px(S2)
    let room = dmax(0.0, end - right - cw - (if has_actions { @ui.Space::px(S4) } else { 0.0 }) - @ui.Space::px(S1) - x0)
    let title = cells["title"]
    let natural = space.measure(title, max_width=None, max_height=None)
    let title_width = dmin(natural.size().0, dmax(chat_title_least, width * chat_title_part))
    // Keep the title whole up to its limit, then leave people out before later
    // agents, the last of each kind first. Only then may the title be shortened.
    let measures = parts.map(fn(part) { space.measure(cells[part.0], max_width=None, max_height=None) })
    let kept = Array::make(parts.length(), true)
    let mut total = title_width
    let mut count = parts.length()
    for i in 1..<parts.length() { total = total + measures[i].size().0 }
    while total + gap * (count - 1).to_double() > room + 0.01 {
      let mut pick = -1
      for i, part in parts {
        if kept[i] && part.1 > 0 && (pick < 0 || part.1 <= parts[pick].1) { pick = i }
      }
      if pick < 0 { break }
      kept[pick] = false
      total = total - measures[pick].size().0
      count = count - 1
    }
    let text_width = dmax(0.0, dmin(title_width, room - (total - title_width) - gap * (count - 1).to_double()))
    let text = space.measure(title, width=text_width, max_height=None)
    placed.push(text.at(x0, y - text.size().1 / 2.0))
    let mut x = x0 + text_width
    for i in 1..<parts.length() {
      if kept[i] {
        let part = measures[i]
        x = x + gap
        placed.push(part.at(x, y - part.size().1 / 2.0))
        x = x + part.size().0
      }
    }
    placed.push(controls.at(end - right - cw, y - ch / 2.0))
    @view.arrangement(width, height, placed)
  }) |> ignore
}
