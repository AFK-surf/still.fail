// The columns' widths on the files' page (ember web/src/pages/DriveViews.tsx ColumnsView, Column, ColumnEdge; drive/
// kept.ts column widths): every column as wide as the rest (240 until one is set, kept on this device: prefs
// `driveViews.column`), a column dragged by its edge wider or narrower for this run (160 to 640), with ⌥ held every
// column (kept); its edge pressed twice as wide as its longest name needs. Its edge is the app's other edges' (ui.tsx
// ResizeHandle): a bar at its middle while the pointer is over the column, longer and a line along it while on the edge.

///|
/// What the columns' widths are here: each column's set by dragging it (by its folder), every column's as set here
/// until the prefs say, and the edge in hand (its column's key, "" every one; where it went down; its width then;
/// whether it has moved; how wide it is now).
priv struct FCols {
  widths : Map[String, Double]
  mut every : Double?
  mut drag : (String, Double, Double, Bool, Double)?
}

///|
let fcols : FCols = { widths: {}, every: None, drag: None }

///|
fn fcols_reset() -> Unit {
  fcols.widths.clear()
  fcols.every = None
  fcols.drag = None
}

///|
/// A column's width at least, at most (COLUMN_MIN, COLUMN_MAX).
let fcols_least : Double = 160.0

///|
let fcols_most : Double = 640.0

///|
/// How far an edge moves before it is dragged (3), a column's room about its name (its row's: 4 in, 8 in, its mark and
/// 8, 8 after; a folder's chevron and 8).
let fcols_slop : Double = 3.0

///|
let fcols_row_room : Double = 52.0

///|
let fcols_chevron_room : Double = 24.0

///|
fn fcols_clamp(px : Double) -> Double {
  dmax(fcols_least, dmin(fcols_most, px.round()))
}

///|
/// Every column's width: as set here, else as kept on this device, else 240.
fn fcols_every(src : Source) -> Double {
  match fcols.every {
    Some(w) => w
    None =>
      match (@json.parse(text(field((src.topic)("prefs", {}).value, "driveViews"), "column")) catch { _ => Json::null() }) {
        Number(w, ..) if w > 0.0 => w
        _ => files_column_w
      }
  }
}

///|
/// The width of the column `key` (its folder): while its edge (or ⌥, every edge) is in hand, as dragged; else its own,
/// else every column's.
fn fcols_width(src : Source, key : String) -> Double {
  match fcols.drag {
    Some((k, _, _, true, w)) if k == key || k == "" => w
    _ => fcols.widths.get(key).unwrap_or(fcols_every(src))
  }
}

///|
/// The edge of the column `key` (its folder's), `width` wide now, after it: dragged, its width (⌥ held as it is let go:
/// every column's, kept); pressed twice, as wide as `names` need (its rows' names; a folder's with its chevron).
fn files_column_edge(
  c : @ui.Ctx,
  src : Source,
  key : String,
  column : Int,
  width : Double,
  names : Array[(String, Bool)],
) -> Unit {
  let t = @sf.theme()
  let id = c.id("files/column-edge/" + key)
  let (px, py, down) = c.pointer()
  c.cursor(id, ResizeX)
  let mine = match fcols.drag {
    Some((k, _, _, _, _)) => k == key || k == ""
    None => false
  }
  if c.pressed(id) {
    match fcols.drag {
      // (from where it went down: the frame that sees the press may see it moved already)
      None => fcols.drag = Some((key, c.press_x, width, false, width))
      Some((k, x0, w0, moved, _)) if k == key || (k == "" && moved) => {
        let now_moved = moved || (px - x0).abs() >= fcols_slop
        let every = (@ui.mods_held() & @ui.mod_alt) != 0
        fcols.drag = Some((if every { "" } else { key }, x0, w0, now_moved, fcols_clamp(w0 + px - x0)))
      }
      _ => ()
    }
  }
  if !down {
    match fcols.drag {
      Some((k, _, _, moved, w)) if k == key || (k == "" && mine) => {
        fcols.drag = None
        if moved {
          if k == "" || (@ui.mods_held() & @ui.mod_alt) != 0 {
            // every column as wide, kept on this device
            fcols.widths.clear()
            fcols.every = Some(w)
            (src.call)(
              "prefs.set",
              { "driveViews": { "column": if w == files_column_w { Json::null() } else { Json::string(w.to_int().to_string()) } } },
              fn(_) {  },
            )
          } else {
            fcols.widths[key] = w
          }
        }
      }
      _ => ()
    }
  }
  if c.double_clicked(id) {
    let need = names.fold(init=0.0, fn(m, n) {
      dmax(m, @ui.text_advance(n.0, size=13.0) + (if n.1 { fcols_chevron_room } else { 0.0 }))
    })
    if need > 0.0 {
      fcols.widths[key] = fcols_clamp(need + fcols_row_room)
    }
  }
  // the bar at its middle while the pointer is over its column (or on it, longer), a line along it while on it
  let on = c.hovered(id) || mine
  let over_column = match c.rect_of(column) {
    Some((x, y, w, h)) => px >= x && px < x + w + fcols_edge_w && py >= y && py < y + h
    None => false
  }
  let b = c.box(style=fcols_edge, id~, fn() {
    if on {
      c.layer(fn() { c.box(style=fcols_line_place, fn() { c.box(style=fcols_line, fn() {  }) |> ignore }) |> ignore }) |> ignore
    }
    if on || over_column {
      c.box(style=if mine { fcols_grip_active } else if on { fcols_grip_long } else { fcols_grip }, fn() {  }) |> ignore
    }
  })
  ignore(t)
  c.semantics(b, Button, id~, label=tr("web-pages.drive.resizeColumn"))
}

///|
/// An edge: as wide as the gap between two columns (6), the bar's and the line's place in it.
let fcols_edge_w : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
let fcols_edge : @ui.Style = @ui.style(w=Fixed(fcols_edge_w), h=Full, align=ACenter, justify=JCenter)

///|
/// The line along it (8 short of its ends), in the field's hover ink.
// kept across runs: a value (no field of it changes)
let fcols_line_place : @ui.Style = @ui.style(w=Full, h=Full, py=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let fcols_line : @ui.Style = @ui.style(w=SPx, h=Full, bg=Border)

///|
/// The bar (5 wide, 24 high; 48 on the edge; darker in hand).
// kept across runs: a value (no field of it changes)
let fcols_grip : @ui.Style = @ui.style(w=Fixed(fcols_grip_w), h=S6, radius=Full, bg=Border)

///|
// kept across runs: a value (no field of it changes)
let fcols_grip_long : @ui.Style = fcols_grip.then(@ui.style(h=S12))

///|
// kept across runs: a value (no field of it changes)
let fcols_grip_active : @ui.Style = fcols_grip_long.then(@ui.style(bg=Muted))

///|
let fcols_grip_w : Double = 5.0
