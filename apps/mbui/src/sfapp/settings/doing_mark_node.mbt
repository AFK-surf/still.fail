// The mark of an operation as nodes of the window's tree (doing_mark): a turning ring while it runs, else a red
// info mark while it failed, with its reason in a tip. It takes the pointer but no press from the row around it.

///|
/// The operation's mark in `parent`, as `running` and `failed` change. `tips` is the layer over the page or window;
/// `inline` draws the mark 12 across beside small words, otherwise it is 14 across. Running takes precedence.
pub fn doing_mark_node(
  parent : @view.View,
  running : () -> Bool,
  failed : () -> String?,
  tips : @sf.TipLayer,
  inline? : Bool = false,
) -> Unit {
  let size = if inline { 12.0 } else { 14.0 }
  parent.pick(fn() { if running() { 1 } else if failed() is Some(_) { 2 } else { 0 } }, fn(p, what) {
    match what {
      1 => @sf.spinner_node(p, size~) |> ignore
      2 => {
        let why = fn() {
          match failed() {
            Some("") | None => @sf.t("web-main.doing.failed")
            Some(reason) => reason
          }
        }
        let mark = @sf.icon_node(p, "info", size, By(fn() { @sf.theme().p.red }))
        mark.points(Is(true)).says(By(fn() { Some(@view.said(Status, label=why())) })) |> ignore
        @sf.tip_node(tips, mark, why) |> ignore
      }
      _ => ()
    }
  })
}
