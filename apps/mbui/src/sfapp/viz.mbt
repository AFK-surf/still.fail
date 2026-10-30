// A visualization in the phone's chat (sfbase viz_page.mbt: the page, a mermaid chart, one open over the whole
// screen): in a message, with the ways under it in the phone's grey; its wait under the words whose link opened it.

///|
/// A placed HTML file `a` of the message `ts`, drawn there, with the ways to open it on its own under it (the whole
/// screen, or a page of its own: 在侧边打开); `failed`: what shows instead when the file cannot be read (its card).
fn viz_file(c : @ui.Ctx, src : Source, here : Here, ts : String, a : Attachment, failed : () -> Unit) -> Unit {
  viz_file_of(c, src, here.station, here.session, owner_of(here, a), ts, a, failed, ink().subtle)
}

///|
// kept across runs: a value (no field of it changes)
let viz_opening_box : @ui.Style = @ui.css("pt=S1_5 pb=S1_5")

///|
/// Under the words whose link opened a visualization, while it is fetched (VizFiles.kt VizOpen: 正在打开).
fn viz_opening(c : @ui.Ctx, src : Source, here : Here) -> Unit {
  match viz_full.get() {
    Some(v) if v.linked && v.station == here.station && v.session == here.session =>
      if viz_load(c, src, v.station, v.key, v.path) is None {
        c.box(style=viz_opening_box, fn() { @sf.wait_line(c, viz_tr("common.opening"), key="viz-open") }) |> ignore
      }
    _ => ()
  }
}

// ── a mermaid chart (Viz.kt Mermaid) ───────────────────────────────────

