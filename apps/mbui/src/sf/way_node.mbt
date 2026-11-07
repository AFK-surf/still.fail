// The way to a place as nodes of the window's tree. The steps that do not fit leave whole, in the same order as
// way_line's, and remain available in a menu. The last gives way only after the others have left.

///|
/// A way in `parent`, its `steps` and `look` as they are now. `go` is given the index in the current steps. The last
/// is the current place unless `last_link` says it is a way too. `in_row` says that the parent lays its children in a
/// row (so the line's Full/Grow width takes the remaining room); `width`, when supplied, gives its width in points.
pub fn way_line_node(
  parent : @view.View,
  steps : () -> Array[String],
  look : () -> WayLook,
  go : (Int) -> Unit,
  last_link? : Bool = false,
  in_row? : Bool = false,
  width? : () -> Double?,
) -> @view.View {
  parent.box(fn(line) {
    style_node(line, fn() { look().line }, in_row~)
    line.row(Is(true)).fits(Is(true)).min_width(Is(Some(0.0))) |> ignore
    match width {
      Some(w) => line.width(By(w)) |> ignore
      None => ()
    }
    let slots : Map[Int, @view.View] = {}
    let opened = @signals.signal(0)
    let close = fn() {
      let serial = @signals.untracked(fn() { opened.get() })
      if serial != 0 {
        close_presented_of(serial)
        opened.set(0)
      }
    }
    line.owns(close) |> ignore
    line.each(
      fn() {
        let n = steps().length()
        let keys : Array[Int] = []
        if n > 0 {
          keys.push(0)
          if n > 1 {
            keys.push(-1)
          }
          for i in 1..<n {
            keys.push(i)
          }
        }
        keys
      },
      fn(i) { i },
      fn(part, item) {
        let i = @signals.untracked(fn() { item.get() })
        part.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        if i < 0 {
          part.drops(Is(-1)) |> ignore
          part.show(fn() {
            match slots.get(0) {
              Some(v) => !v.left_out()
              None => false
            }
          }, fn(p) { way_chevron_node(p, look) })
          part.box(fn(more) {
            style_node(more, fn() { look().step }, in_row=true)
            way_step_ground(more, fn() { look().step })
            let open = fn() {
              let all = @signals.untracked(steps).copy()
              let items : Array[MenuItem?] = []
              for j in 0..<(all.length() - 1) {
                match slots.get(j) {
                  Some(v) if v.left_out() => items.push(Some(menu_item_of(all[j], fn() {
                    if @signals.untracked(steps) == all && v.left_out() {
                      go(j)
                    }
                  }, icon="folder")))
                  _ => ()
                }
              }
              if !items.is_empty() {
                let (x, y, w, h) = more.rect()
                menu(items, from=At(x, y, w, h))
                opened.set(last_presented())
              }
            }
            presses_node(more, open)
            more.says(By(fn() {
              let serial = opened.get()
              Some(@view.said(Button, label=t("common.more"), expanded=serial != 0 && presented_drawn_of(serial)))
            })) |> ignore
            more.box(fn(words) {
              styled_words(words, fn() { way_more }, fn() { look().words }) |> ignore
            })
            |> ignore
          })
          |> ignore
        } else {
          slots[i] = part
          part.owns(fn() { slots.remove(i) }) |> ignore
          let last = fn() { i == steps().length() - 1 }
          let link = fn() { !last() || last_link }
          let name = fn() { steps().get(i).unwrap_or("") }
          part
          .drops(By(fn() { if last() { 0 } else if i == 0 { steps().length() } else { i } }))
          .cuts(By(last), keep=true)
          .min_width(By(fn() { if last() { Some(0.0) } else { None } }))
          |> ignore
          if i > 0 {
            way_chevron_node(part, look)
          }
          part.box(fn(step) {
            style_node(step, fn() { look().step }, in_row=true)
            way_step_ground(step, fn() { look().step })
            step.cuts(By(last), keep=true).min_width(By(fn() { if last() { Some(0.0) } else { None } })) |> ignore
            presses_node(step, fn() { if @signals.untracked(link) { go(i) } }, on=link)
            step.says(By(fn() { if link() { Some(@view.said(Link, label=name())) } else { None } })) |> ignore
            step.box(fn(words) {
              words
              .words(By(name))
              .words_look(By(fn() { @ui.style_words(if link() { look().words } else { look().here }) }))
              .ink(By(fn() { @ui.style_ink(if link() { look().words } else { look().here }) }))
              .cuts(By(last), keep=true)
              .min_width(By(fn() { if last() { Some(0.0) } else { None } }))
              .allow_ellipsis(Is(true))
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      },
    )
    // A menu's items are a snapshot. Close it when the path or hidden steps change, before an index could name a
    // different place. Register after each has made its first slots so their left_out changes are followed too.
    line.reacts(fn() {
      let all = steps()
      let hidden : Array[Int] = []
      for i in 0..<all.length() {
        match slots.get(i) {
          Some(v) if v.left_out() => hidden.push(i)
          _ => ()
        }
      }
      (all, hidden)
    }, fn(_) { close() })
  })
}

///|
/// A chevron follows both its size and its ink as the way's look changes.
fn way_chevron_node(parent : @view.View, look : () -> WayLook) -> Unit {
  parent.box(fn(icon) {
    icon
    .width(By(fn() { Some(look().chevron) }))
    .height(By(fn() { Some(look().chevron) }))
    .shapes(By(fn() {
      match icon_numbers("chevron-right") {
        Some(d) => icon_shapes(d, look().chevron / 24.0, 0x000000FFL)
        None => []
      }
    }))
    .drawn_as(Is("/icon/chevron-right/"))
    .tint(By(fn() { look().chevron_ink }))
    |> ignore
  })
  |> ignore
}

///|
/// A step's base ground and its hover tint, as the old style draws them.
fn way_step_ground(step : @view.View, style : () -> @ui.Style) -> Unit {
  step.ground(By(fn() {
    let s = style()
    let th = @ui.tree_theme()
    let color = fn(c : @ui.Color?) { match c { Some(c) => th.color(c); None => 0L } }
    let base = color(s.base.bg)
    let hovered = match @ui.pointing() {
      Mouse => step.pointed()
      Finger => step.pressed()
    }
    match s.hovered {
      Some(p) if hovered => @ui.over(base, color(p.bg))
      _ => base
    }
  })) |> ignore
}
