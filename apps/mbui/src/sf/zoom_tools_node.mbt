// An image's zoom in a bar as nodes of the window's tree (viewer_zoom's: −, its per cent, +, 1:1), each a tool_node:
// how big the picture is shown read of the zoom as it is told (Zoom::told), its glide's way read as each frame is drawn
// while it goes and not after (Zoom::glide_ends), so the per cent counts through a glide as the old bar's did; what a
// press does done at its moment, from how big it is shown then. Its per cent laid out as wide as the words of how big it
// was told to be (zoom_room), as each is told: what holds it laid out by causes, not by frames.

///|
/// The zoom `z`'s tools in `parent` (viewer_zoom's, its row of keys): − (unable at the least it zooms to), its per cent
/// (fitted again as it is pressed), + (unable at the most), 1:1; in `ink`, round as `corner` says, their tips in `tip`.
/// Each a quarter more or less, about the stage's middle, gliding, from how big it is shown at the press's moment. The
/// row's node.
pub fn zoom_tools_node(
  parent : @view.View,
  z : @kit.Zoom,
  ink : () -> ViewerInk,
  corner : @view.Live[Double],
  tip? : TipLayer,
) -> @view.View {
  parent.box(fn(row) {
    row.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(keys_apart())) |> ignore
    // (how big it is shown as drawn now: while a glide goes, read as each frame is drawn; after, as it was told)
    let shown = fn() {
      let end = z.glide_ends()
      let now = @signals.untracked(fn() { row.drawn_at() })
      z.scale_shown(if end >= 0.0 && now < end { row.drawn_at() } else { now })
    }
    let at = fn() { row.cause_at() }
    let mid = fn(s : Double) { z.zoom_to(s, z.bw / 2.0, z.bh / 2.0, true, at=at()) }
    tool_node(
      row,
      fn() {
        {
          icon: "minus",
          label: t("web-main.preview.zoomOutKey"),
          on: false,
          disabled: shown() <= z.min_scale() + viewer_zoom_slack,
        }
      },
      ink,
      corner,
      fn() { mid(z.scale_at(at()) / viewer_zoom_step) },
      tip?,
    )
    |> ignore
    tool_node(
      row,
      fn() { { icon: "", label: t("web-main.preview.fitKey"), on: false, disabled: false } },
      ink,
      corner,
      fn() { z.reset(at=at()) },
      tip?,
      words=fn() { per_cent(shown()) },
      room=fn() { zoom_room(z) },
      wide=true,
    )
    |> ignore
    tool_node(
      row,
      fn() {
        {
          icon: "plus",
          label: t("web-main.preview.zoomInKey"),
          on: false,
          disabled: shown() >= z.max_scale() - viewer_zoom_slack,
        }
      },
      ink,
      corner,
      fn() { mid(z.scale_at(at()) * viewer_zoom_step) },
      tip?,
    )
    |> ignore
    tool_node(
      row,
      fn() { { icon: "", label: t("web-main.preview.actualKey"), on: false, disabled: false } },
      ink,
      corner,
      fn() { mid(1.0) },
      tip?,
      words=fn() { "1:1" },
    )
    |> ignore
  })
}

///|
/// A scale as its per cent says it.
fn per_cent(scale : Double) -> String {
  "\{(scale * 100.0).round().to_int()}%"
}

///|
/// The words the zoom's per cent is laid out as wide as (what a bar holding it is laid out by): the longer of how big
/// it was and how big it was told to be (a glide's ends: the per cent counting between them never longer, its digits all
/// one width), as each is told (Zoom::scales_told), never by the way between.
pub fn zoom_room(z : @kit.Zoom) -> String {
  let (from, to) = z.scales_told()
  let (a, b) = (per_cent(from), per_cent(to))
  if a.length() > b.length() {
    a
  } else {
    b
  }
}
