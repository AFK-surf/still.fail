// The compact page bar as nodes of the view tree. The title stays in the middle of the bar, with at least the old
// bar's 84 points clear at either end; longer back words or actions make that room larger in the same layout.

///|
/// A compact bar in `parent`: back to where `back` names, `title` in the middle, optional `sub` under it and
/// `trailing` at the end. Each slot is made once and can bind its contents to signals. `back_max` limits the back
/// word alone (0 means no limit); a word that does not fit is left out whole, while the button keeps its full name.
/// `top` is the status bar's inset and `bg` the ground including that inset. The bar node.
pub fn nav_bar_node(
  parent : @view.View,
  back : () -> String,
  title : () -> String,
  on_back : () -> Unit,
  sub? : (@view.View) -> Unit,
  trailing? : (@view.View) -> Unit,
  back_max? : () -> Double = fn() { 0.0 },
  bg? : () -> Int64 = fn() { 0L },
  top? : () -> Double = fn() { 0.0 },
) -> @view.View {
  parent.box(fn(bar) {
    bar
    .padding(By(fn() { (16.0, 6.0 + dmax(top(), 0.0), 16.0, 10.0) }))
    .ground(By(bg))
    |> ignore
    bar.box(fn(line) {
      line.layout_box(Is(()), sized=true, fn(l, _) {
        let back_node = l.child("back", fn(b) {
          b
          .row(Is(true))
          .padding(Is((0.0, nav_back_y, nav_back_end, nav_back_y)))
          .radius(By(fn() { @ui.tree_theme().corner(Lg) }))
          .lines_up(Is(Some(Middle)))
          |> ignore
          pressed_node(b, on_back, Is(nav_back_ripple), Button, back)
          icon_node(b, "chevron-left", nav_back_icon, By(fn() { theme().p.accent_text })) |> ignore
          b.box(fn(room) {
            room
            .row(Is(true))
            .fits(Is(true))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            .max_width(By(fn() { if back_max() > 0.0 { Some(back_max()) } else { None } }))
            |> ignore
            room.box(fn(w) {
              w.drops(Is(1)) |> ignore
              styled_words(w, back, fn() { nav_back_words }) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        let (back_w, back_h) = l.fit(back_node, l.width / 2.0)
        let end_node = match trailing {
          Some(make) => {
            let end = l.child("trailing", fn(v) {
              v.row(Is(true)).height(Is(Some(32.0))).lines_up(Is(Some(Middle))) |> ignore
              make(v)
            })
            let (w, _) = l.fit(end, l.width / 2.0)
            Some((end, w))
          }
          None => None
        }
        let end_w = match end_node { Some((_, w)) => w; None => 0.0 }
        let clear = dmin(l.width / 2.0, dmax(84.0, dmax(back_w, end_w)))
        let middle = dmax(0.0, l.width - 2.0 * clear)
        let title_node = l.child("title", fn(row) {
          row.row(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
          row.box(fn(w) {
            styled_words(w, title, fn() { nav_title_words }).cuts(Is(true)).allow_ellipsis(Is(true)) |> ignore
          })
          |> ignore
        })
        l.measure(title_node, middle, height=32.0) |> ignore
        l.place(title_node, clear, 0.0)
        let mut height = 32.0
        match sub {
          Some(make) => {
            let under = l.child("sub", fn(v) {
              v.row(Is(true)).gap(Is(5.0)).lines_up(Is(Some(Middle))) |> ignore
              make(v)
            })
            let (w, h) = l.fit(under, middle)
            l.place(under, (l.width - w) / 2.0, 28.0)
            height = height + h
          }
          None => ()
        }
        // Back and the action are drawn over the title as in the old bar, but have their own press targets.
        l.place(back_node, 0.0, (32.0 - back_h) / 2.0)
        match end_node {
          Some((end, w)) => l.place(end, l.width - w, 0.0)
          None => ()
        }
        l.size_to(height)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The usual caption under a compact bar's title, in the muted ink, on a 16 point line. Its words may change without
/// remaking the bar. Use the `sub` slot directly to put an icon or other nodes beside it.
pub fn nav_bar_subtitle_node(parent : @view.View, words : () -> String) -> @view.View {
  parent.box(fn(w) {
    w
    .words(By(words))
    .words_look(By(fn() { { ..@view.words_plain, size: theme().t.caption, line: 16.0, wrap: false } }))
    .ink(By(fn() { theme().p.muted }))
    .cuts(Is(true))
    .min_width(Is(Some(0.0)))
    .allow_ellipsis(Is(true))
    |> ignore
  })
}
