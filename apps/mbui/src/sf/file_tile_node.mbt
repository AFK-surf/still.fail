// The file sheet as a retained tree node, following the file and its upload as they change.

///|
/// A file's 30 by 36 sheet or folder. `name`, `dir`, `progress` and `error` are read as they change, as is the theme.
/// The returned node may be scaled (about its centre by default); scaling changes its drawing, not its layout.
pub fn file_tile_node(
  parent : @view.View,
  name : () -> String,
  dir? : () -> Bool = fn() { false },
  progress? : () -> Double? = fn() { None },
  error? : () -> Bool = fn() { false },
) -> @view.View {
  let ext = fn() {
    let n = name()
    match n.rev_find(".") {
      Some(i) if i > 0 && n.length() - i <= tile_ext_most => n.view(start_offset=i + 1).to_string().to_upper()
      _ => ""
    }
  }
  parent.box(fn(tile) {
    tile.width(Is(Some(tile_w))).height(Is(Some(tile_h)))
    .shapes(By(fn() {
      let t = theme()
      let scale = @ui.current().drawn_scale()
      if dir() {
        [@ui.shape_of(tile_outlines(tile_folder, scale), stroke=t.p.muted, width=tile_stroke)]
      } else {
        let shapes = match progress() {
          Some(part) => [file_tile_fill(scale, part, alpha(t.p.accent, tile_fill_share))]
          None => []
        }
        shapes.push(@ui.shape_of(
          tile_outlines(if ext() == "" { tile_sheet_lines } else { tile_sheet }, scale),
          stroke=t.p.muted,
          width=tile_stroke,
        ))
        shapes
      }
    }))
    .drawn_as(Is("file-tile")) |> ignore
    tile.box(fn(room) {
      room.over(Is(true)).offset(Is((0.0, 18.0))).width(Is(Some(tile_w))).lines_up(Is(Some(Middle))) |> ignore
      room.box(fn(words) {
        words.words(By(fn() { if dir() { "" } else { ext() } }))
        .words_look(By(fn() { { ..@ui.style_words(tile_ext), size: tile_ext_size } }))
        .ink(By(fn() { @ui.style_ink(if error() { tile_ext_failed } else { tile_ext }) })) |> ignore
      }) |> ignore
    }) |> ignore
  })
}
