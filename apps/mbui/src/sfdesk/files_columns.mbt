// The columns' widths on the files' page (ember web/src/pages/DriveViews.tsx ColumnsView, Column, ColumnEdge; drive/
// kept.ts column widths): every column as wide as the rest (240 until one is set, kept on this device: prefs
// `driveViews.column`), a column dragged by its edge wider or narrower for this run (160 to 640), with ⌥ held every
// column (kept); its edge pressed twice as wide as its longest name needs. Its edge is the library's (the web's
// resizeHandle, as ColumnEdge's is): a bar at its middle while the pointer is over the column, longer and a line along
// it while on the edge, its words by the pointer.

///|
/// What the columns' widths are here: each column's set by dragging it (by its folder), every column's as set here
/// until the prefs say, and the edge being dragged (its column's key; whose width it sets, its own key or "" for every
/// column's; the width it is dragged to).
priv struct FCols {
  widths : Map[String, Double]
  mut every : Double?
  mut drag : (String, String, Double)?
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
/// A column as wide as every column is until one is set (Drive.css.ts column: 240).
pub let files_column_w : Double = 240.0

///|
/// A column's width at least, at most (COLUMN_MIN, COLUMN_MAX).
let fcols_least : Double = 160.0

///|
let fcols_most : Double = 640.0

///|
/// A column's room about its name (its row's: 4 in, 8 in, its mark and 8, 8 after; a folder's chevron and 8).
let fcols_row_room : Double = 52.0

///|
let fcols_chevron_room : Double = 24.0

///|
fn fcols_clamp(px : Double) -> Double {
  let w = px.round()
  if w < fcols_least {
    fcols_least
  } else if w > fcols_most {
    fcols_most
  } else {
    w
  }
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
/// The width of the column `key` (its folder): while its edge (or with ⌥, any edge: every column's) is dragged, as
/// dragged; else its own, else every column's.
pub fn fcols_width(src : Source, key : String) -> Double {
  match fcols.drag {
    Some((_, whose, w)) if whose == key || whose == "" => w
    _ => fcols.widths.get(key).unwrap_or(fcols_every(src))
  }
}

///|
/// The edge of the column `key` (its folder's, drawn as `column`), `width` wide now, after it (ColumnEdge: the
/// library's edge, @sf.handle_drag and @sf.edge_look): dragged, its width, or with ⌥ held every column's (kept on
/// this device as it is let go); pressed twice, as wide as `names` need (its rows' names; a folder's with its chevron).
pub fn files_column_edge(
  c : @ui.Ctx,
  src : Source,
  key : String,
  column : Int,
  width : Double,
  names : Array[(String, Bool)],
) -> Unit {
  let id = c.id("files/column-edge/" + key)
  let (px, py, _) = c.pointer()
  c.cursor(id, ResizeX)
  let every = (@ui.mods_held() & @ui.mod_alt) != 0
  match @sf.handle_drag(c, id, width, min=fcols_least, max=fcols_most) {
    Dragging(w) => fcols.drag = Some((key, if every { "" } else { key }, w))
    Dropped(w) => {
      let was_every = match fcols.drag {
        Some((_, whose, _)) => whose == ""
        None => false
      }
      fcols.drag = None
      if every || was_every {
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
    Twice => {
      let need = names.fold(init=0.0, fn(m, n) {
        let w = @ui.text_advance(n.0, size=13.0) + (if n.1 { fcols_chevron_room } else { 0.0 })
        if w > m {
          w
        } else {
          m
        }
      })
      if need > 0.0 {
        fcols.widths[key] = fcols_clamp(need + fcols_row_room)
      }
    }
    Untouched | Pressed => ()
  }
  // in hand: this edge, or with ⌥ every one, while one is dragged
  let dragged = match fcols.drag {
    Some((k, whose, _)) => k == key || whose == ""
    None => false
  }
  let active = dragged || c.pressed(id)
  let over = match c.rect_of(column) {
    Some((x, y, w, h)) => px >= x && px < x + w + fcols_edge_w && py >= y && py < y + h
    None => false
  }
  let words = @sf.t("web-pages.drive.resizeColumn")
  let b = c.box(style=fcols_edge, id~, fn() {
    @sf.edge_look(c, "files/column-edge/" + key, over~, on=c.hovered(id) || c.focus_shown(id) || active, active~)
  })
  c.semantics(b, Separator, id~, label=words)
  @sf.edge_tip(c, "files/column-edge/" + key, id, words)
}

///|
/// An edge: as wide as the gap between two columns (6), the library's look from its left (its line 3 in, the gap's
/// middle: Drive.css.ts columnEdge, the handle 7 past the column's edge).
pub let fcols_edge_w : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
pub let fcols_edge : @ui.Style = @ui.style(w=Fixed(fcols_edge_w), h=Full)
