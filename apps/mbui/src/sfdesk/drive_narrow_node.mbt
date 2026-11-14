// The narrow files' saying what could not be read and that nothing is here (drive_narrow.mbt's narrow_retry and
// narrow_empty) as nodes of the window's tree, for what is made once (the station files picker: station_pick.mbt).

///|
/// What could not be read (`words`, in `look`), and 重试 after it in the link's ink: `retry` as it is pressed
/// (narrow_retry's).
fn narrow_retry_node(v : @view.View, words : () -> String, look : @ui.TextStyle, retry : () -> Unit) -> Unit {
  v.box(fn(b) {
    @sf.style_node(b, fn() { narrow_problem })
    b.box(fn(w) {
      @sf.style_node(w, fn() { narrow_problem_words }, in_row=true)
      @sf.words_node(w, words, fn() { look }) |> ignore
    })
    |> ignore
    b.box(fn(l) {
      @sf.style_node(l, fn() { narrow_link }, in_row=true)
      @sf.presses_node(l, retry)
      l.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-pages.drive.retry"))) })) |> ignore
      @sf.words_node(l, fn() { @sf.t("web-pages.drive.retry") }, fn() { narrow_link_words }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Nothing here (narrow_empty's): a folder's mark (40), why (`words`), and what can be done about it (`action`: its
/// words, what it does).
fn narrow_empty_node(v : @view.View, words : () -> String, action : (() -> String, () -> Unit)?) -> Unit {
  v.box(fn(b) {
    // (its words as wide as it, their lines in its middle, narrow_empty_words' w=Full and center; its mark and its
    // button in its middle, narrow_empty_box's align)
    @sf.style_node(b, fn() { narrow_empty_across })
    b.box(fn(m) {
      @sf.style_node(m, fn() { narrow_in_middle })
      @sf.icon_node(m, "folder", narrow_empty_icon, By(fn() { @sf.theme().p.subtle })) |> ignore
    })
    |> ignore
    @sf.words_node(b, words, fn() { narrow_empty_words }).words_centered(Is(true)) |> ignore
    match action {
      Some((label, go)) =>
        b.box(fn(m) {
          @sf.style_node(m, fn() { narrow_in_middle })
          @sf.button_node(m, label, go, tone=Ghost) |> ignore
        })
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// narrow_empty_box, what it holds as wide as it.
// kept across runs: a value (no field of it changes)
let narrow_empty_across : @ui.Style = @ui.css("w=Full px=S8 py=S14 gap=S3")

///|
/// What it holds in its middle across.
// kept across runs: a value (no field of it changes)
let narrow_in_middle : @ui.Style = @ui.css("align=ACenter")
