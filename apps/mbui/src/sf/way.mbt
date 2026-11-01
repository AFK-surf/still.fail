// A way to where something is (the web's crumbs: the files page's on a phone, the folder picker's, the station
// picker's): the places over it, each a way back to it, in a line that neither scrolls nor wraps.

///|
/// How a way looks: its line, each step's box, a step's words and the last's (where it is), the chevrons between and
/// their ink.
pub(all) struct WayLook {
  line : @ui.Style
  step : @ui.Style
  words : @ui.TextStyle
  here : @ui.TextStyle
  chevron : Double
  chevron_ink : Int64
}

///|
/// The way `steps` (where it is the last) in a line, `key` its name, a chevron between, each but the last a way back
/// to it (`go`, given its index). Where the line has not the room, steps leave it whole, never cut short: those
/// between the first and the last first (the one after the first first, the one before the last last), then the
/// first; a … where they were offers them instead (a menu of them, in their order). Only where the last alone has not
/// the room are its words cut short. Nothing scrolled, nothing wrapped (the user, 2026-10-25: a control short of room
/// neither scrolls nor wraps, and words cut short past knowing are no use). `last_link` is for a way of ancestors
/// when the current place is shown separately: its last visible step is a way back too.
pub fn way_line(c : @ui.Ctx, key : String, steps : Array[String], look : WayLook, go : (Int) -> Unit, last_link? : Bool = false) -> Unit {
  let n = steps.length()
  // (each step but the last, and the …: -1)
  let slot = fn(i : Int) { c.id(key + "/slot/\{i}") }
  // those the line left out as last laid out (read back: the frame is built again where that changes)
  let gone : Array[MenuItem?] = []
  for i in 0..<(n - 1) {
    if c.left_out(slot(i)) {
      gone.push(Some(menu_item_of(steps[i], fn() { go(i) }, icon="folder")))
    }
  }
  let first_out = n > 1 && c.left_out(slot(0))
  let chevron = fn() { icon(c, "chevron-right", size=look.chevron, color=look.chevron_ink) |> ignore }
  c.box(style=look.line, fn() {
    for i, name in steps {
      let last = i == n - 1
      let id = c.id(key + "/\{i}")
      if (!last || last_link) && c.clicked(id) {
        go(i)
      }
      // (the last: always there, its words kept whole while another may leave, cut short only after)
      if last {
        c.box(style=way_part, fn() {
          if i > 0 {
            chevron()
          }
          let b = c.box(style=look.step, id=if last_link { id } else { 0 }, fn() {
            c.text(name, style=(if last_link { look.words } else { look.here }).then(way_last), keep=true) |> ignore
          })
          if last_link {
            c.semantics(b, Link, id~, label=name)
          }
        })
        |> ignore
      } else {
        // (another: whole with the chevron before it, or out of the line; the first the last of them to go)
        c.box(style=way_part, id=slot(i), taps=false, drop=if i == 0 { n } else { i }, fn() {
          if i > 0 {
            chevron()
          }
          c.box(style=look.step, id~, fn() { c.text(name, style=look.words) |> ignore }) |> ignore
        })
        |> ignore
      }
      // (the …, there only while one is out: after the first, or in its place once it is out too)
      if i == 0 && n > 1 {
        c.box(style=way_part, id=slot(-1), taps=false, more=true, fn() {
          if !first_out {
            chevron()
          }
          let more = c.id(key + "/more")
          if c.clicked(more) {
            menu(gone, from=Of(more))
          }
          let b = c.box(style=look.step, id=more, fn() { c.text(way_more, style=look.words) |> ignore })
          c.semantics(b, Button, id=more, label=t("common.more"))
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// A step and the chevron before it, in a line.
// kept across runs: a value (no field of it changes)
let way_part : @ui.Style = @ui.css("row align=ACenter")

///|
/// The last's words: cut short only where they alone have not the room.
// kept across runs: a value (no field of it changes)
let way_last : @ui.TextStyle = @ui.text_style(w=Cut)

///|
/// What stands for those that left the line.
pub let way_more : String = "…"
