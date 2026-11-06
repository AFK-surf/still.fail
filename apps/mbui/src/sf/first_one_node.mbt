// The first one to make (first_one's: FirstOne) as nodes of the window's tree, made once: a picture where it has one,
// its title, what it means, what to do, in the middle of what holds it, each as it changes.

///|
/// The first one to make in `parent` (first_one's): `art` drawn first where given, `title`, `lead` under it where it
/// says anything (442 wide at most), what `actions` puts in a row under them, centred. 480 wide at most.
pub fn first_one_node(
  parent : @view.View,
  title : () -> String,
  actions : (@view.View) -> Unit,
  art? : (@view.View) -> Unit,
  lead? : () -> String = fn() { "" },
) -> Unit {
  parent.box(fn(room) {
    // (first_room: all of it wide, 24 over and under, what it holds centred)
    room.width_share(Is(1.0)).padding(Is((0.0, 24.0, 0.0, 24.0))).lines_up(Is(Some(Middle))) |> ignore
    room.box(fn(b) {
      // (first_box: 480 at most, 8 over it, 24 under, its parts 8 apart and centred)
      b.width_share(Is(1.0)).max_width(Is(Some(480.0))).padding(Is((0.0, 8.0, 0.0, 24.0))).gap(Is(8.0))
      .lines_up(Is(Some(Middle))) |> ignore
      match art {
        Some(f) => f(b)
        None => ()
      }
      b.box(fn(at) {
        at.padding(Is((0.0, 12.0, 0.0, 0.0))) |> ignore
        at.box(fn(t) {
          t
          .words_centered(Is(true))
          .words(By(title))
          .words_look(By(fn() { @ui.style_words(first_title) }))
          .ink(By(fn() { @ui.style_ink(first_title) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      b.show(fn() { lead() != "" }, fn(l) {
        l.max_width(Is(Some(442.0))).lines_up(Is(Some(Middle))) |> ignore
        l.box(fn(t) {
          t
          .words_centered(Is(true))
          .words(By(lead))
          .words_look(By(fn() { @ui.style_words(first_lead) }))
          .ink(By(fn() { @ui.style_ink(first_lead) }))
          |> ignore
        })
        |> ignore
      })
      b.box(fn(a) {
        // (first_actions: in a row, 8 apart, centred, 12 over)
        a.width_share(Is(1.0)).row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
        .padding(Is((0.0, 12.0, 0.0, 0.0))) |> ignore
        actions(a)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
