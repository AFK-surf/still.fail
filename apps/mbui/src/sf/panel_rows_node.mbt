// Where a panel's retained body puts its rows. Unlike the old frame's drawing-time globals, this is lent to the
// body's nodes for their lifetime, including children made later.

///|
/// A panel body's geometry, in logical pixels. `sides_in` is its column's distance from the panel's sides; `rows_out`
/// is the room at either side for a row's ground, and `words_in` the distance from the column to its words. `small` is
/// a panel beside its anchor. Outside a panel no value is lent. Values that change are read through the lent function.
pub(all) struct PanelRowContext {
  sides_in : Double
  rows_out : Double
  words_in : Double
  small : Bool
} derive(Eq, Show)

///|
/// How a row stands in that body. `out` is the distance its ground extends past its column on each side. `padding`,
/// when present, replaces the row's own horizontal padding; absent, the row keeps its own. `inner` says its ground is
/// concentric with the nearest rounded container, as a small panel's row is.
pub(all) struct PanelRowLayout {
  out : Double
  padding : Double?
  inner : Bool
} derive(Eq, Show)

///|
// kept across runs: a kind of value lent by each body, released with its node
let panel_rows_at : @view.Lent[() -> PanelRowContext] = @view.Lent::new()

///|
/// Lend a panel body's current geometry to `v` and its descendants. `value` can read signals, so a row that reads its
/// layout in a binding follows them without being remade. A nested body may lend its own; it ends with that node.
pub fn panel_rows_lent(v : @view.View, value : () -> PanelRowContext) -> Unit {
  v.lends(panel_rows_at, value) |> ignore
}

///|
/// The closest panel body's current geometry; zero insets and `small=false` outside a panel. Reading this in a
/// binding follows the signals read by its lender, including for children made after the panel body.
pub fn panel_row_context(v : @view.View) -> PanelRowContext {
  match v.lent(panel_rows_at) {
    Some(read) => read()
    None => { sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false }
  }
}

///|
/// Whether `v` is in a presented panel's body. A panel may lend all-zero geometry, so the values alone cannot tell
/// it apart from a page outside a panel.
pub fn in_panel_node(v : @view.View) -> Bool {
  v.lent(panel_rows_at) is Some(_)
}

///|
/// A room that clips or scrolls cards, at the same line as `panel_card_out`. Its children see the panel's sides and
/// words from that room, so a card in it does not reach out a second time. A small panel and a page keep their room.
pub fn panel_card_room_node(parent : @view.View, body : (@view.View) -> Unit) -> @view.View {
  // Take the lender before the room lends its adjusted value: reading the room itself would find that new lender.
  let inherited = parent.lent(panel_rows_at)
  parent.box(fn(room) {
    match inherited {
      Some(read) => {
        let margin = fn() {
          let at = read()
          if at.small || (at.sides_in <= 0.0 && at.words_in <= 0.0) { 0.0 } else { panel_card_in - at.sides_in }
        }
        room.margin(By(fn() { let x = margin(); (x, 0.0, x, 0.0) })) |> ignore
        panel_rows_lent(room, fn() {
          let at = read()
          if at.small || (at.sides_in <= 0.0 && at.words_in <= 0.0) {
            at
          } else {
            { ..at, sides_in: panel_card_in, words_in: at.words_in + at.sides_in - panel_card_in }
          }
        })
      }
      None => ()
    }
    body(room)
  })
}

///|
/// A row's panel geometry at `v`, as row_line's: a small panel's own padding and inner corner; no panel reach on a
/// list card; otherwise the panel's words inset, or its reach capped by the row's own room. A page outside a panel
/// keeps its own margin, padding and corner. Read in a node binding for changes of the lent geometry to be followed.
pub fn panel_row_layout(v : @view.View, narrow : Bool, in_card : Bool) -> PanelRowLayout {
  let none : PanelRowLayout = { out: 0.0, padding: None, inner: false }
  let at = panel_row_context(v)
  if at.small {
    return { out: 0.0, padding: Some(text_in), inner: true }
  }
  if in_card {
    return none
  }
  if at.words_in > 0.0 {
    return { out: 0.0, padding: Some(at.words_in), inner: false }
  }
  let own = if narrow { card_pad - corner_inset } else { desk_list_out }
  let out = dmin(at.rows_out, own)
  if out > 0.0 {
    { out, padding: Some(out), inner: false }
  } else {
    none
  }
}
