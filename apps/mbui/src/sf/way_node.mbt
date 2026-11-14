// A way to where something is (way_line's: the places over it, each a way back to it, in a line that neither scrolls
// nor wraps) as nodes of the window's tree: what has not the room leaves the line as it is laid out (View::fits,
// View::drops), never read back to make it otherwise; a … where they were offers them in a menu.

///|
/// The way `steps` (where it is the last) in a line in `parent`, `look` how it looks, a chevron between, each but the
/// last a way back to it (`go`, given its index). Where the line has not the room, steps leave it whole, never cut
/// short: those between the first and the last first (the one after the first first, the one before the last last),
/// then the first; a … where they were offers them instead (a menu of those left out as it is pressed, in their order).
/// Only where the last alone has not the room are its words cut short. Made anew as the steps change. Its node.
#callsite(autofill(loc))
pub fn way_line_node(
  parent : @view.View,
  steps : () -> Array[String],
  look : () -> WayLook,
  go : (Int) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(line) {
    line.pick(steps, fn(row, steps) {
      let n = steps.length()
      style_node(row, fn() { look().line })
      row.fits(Is(true)) |> ignore
      let chevron = fn(p : @view.View) {
        icon_node(p, "chevron-right", @signals.untracked(fn() { look().chevron }), By(fn() { look().chevron_ink })) |> ignore
      }
      // (each step's part as it is made: which the line left out, read as the … is pressed)
      let parts : Array[@view.View] = []
      // (a step and the chevron after it but the last: what leaves the line takes its own chevron with it, so what
      // stays has one between each two, the … too, none before the first that stays)
      for i, name in steps {
        let last = i == n - 1
        let part = row.box(fn(p) {
          style_node(p, fn() { way_part }, in_row=true)
          if last {
            // (always there, its words kept whole while another may leave, cut short only after)
            p.fit_whole(Is(true)).min_width(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
          } else {
            // (another: whole with its chevron, or out of the line; the first the last of them to go)
            p.drops(Is(if i == 0 { n } else { i })) |> ignore
          }
          p.box(fn(s) {
            style_node(s, fn() { look().step }, in_row=true)
            if last {
              s.min_width(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
              words_node(s, fn() { name }, fn() { look().here.then(way_last) }).min_width(Is(Some(0.0))) |> ignore
            } else {
              presses_node(s, fn() { go(i) })
              s.says(Is(Some(@view.said(Link, label=name)))) |> ignore
              words_node(s, fn() { name }, fn() { look().words }) |> ignore
            }
          })
          |> ignore
          if !last {
            chevron(p)
          }
        })
        parts.push(part)
        // (the …, there only while one is out: after the first, or in its place once it is out too)
        if i == 0 && n > 1 {
          row.box(fn(p) {
            style_node(p, fn() { way_part }, in_row=true)
            p.drops(Is(-1)) |> ignore
            @headless.button(
              p,
              fn() { t("common.more") },
              fn(s) {
                let gone : Array[MenuItem?] = []
                for k in 0..<(n - 1) {
                  if parts[k].left_out() {
                    gone.push(Some(menu_item_of(steps[k], fn() { go(k) }, icon="folder")))
                  }
                }
                // (opened by the … itself: beside it wherever it is laid out while open, the focus given back to it
                // as the menu goes)
                present(Menu(gone, "", Start), Node(s))
              },
              fn(s, _) {
                style_node(s, fn() { look().step }, in_row=true)
                words_node(s, fn() { way_more }, fn() { look().words }) |> ignore
              },
            )
            |> ignore
            chevron(p)
          })
          |> ignore
        }
      }
    })
  })
}
