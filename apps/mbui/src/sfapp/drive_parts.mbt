// The small parts the drive's pages are made of, as the Android app draws them (shared ui/Parts.kt NavBar, NavBack,
// NavButton, SectionHeader; ui/Controls.kt Button, Field, PickRow; ui/Sheet.kt SheetHost, SheetGrab, SheetHead;
// screens/PageParts.kt ask, confirm; screens/PlaceRows.kt PlaceRow), and what the drive keeps while the app runs: the
// sheet open, what is chosen, the files going up, what is under way.

///|
/// A sheet of the drive's (one at a time, over the page that opened it).
priv enum DvSheet {
  NoSheet
  /// ＋: upload, a new folder, the folders lent (owners and admins, at the drive's top)
  Add(DriveAt, String, Bool)
  /// how the folder is shown: its order, hidden files; the folders lent for those who name them
  View(DriveAt, Bool)
  /// one entry: rename, download, share, copy its path, delete
  Entry(DriveAt, DvEntry, Array[String])
  /// several chosen: download, copy their paths, delete
  Chosen(DriveAt, Array[DvEntry])
  /// a line asked for (a name): its title, the words in it at first, the placeholder, the action; what it does
  Ask(String, String, String, String, (String) -> Unit)
  /// asked first: its title, the words, the action, whether it is a danger; what it does
  Confirm(String, String, String, Bool, () -> Unit)
  /// the folders a station lends (owners and admins)
  Roots(String)
  /// a root held: stop lending it
  RootHeld(String, DvRoot)
  /// on which station to lend another folder
  LendOn(Array[DvStation])
  /// the station's folders, to lend one
  Picker(String, Array[String])
}

///|
/// A file going up into a folder of a drive (DriveScreen.kt DriveUpload): its row in the folder's list until it is
/// there.
priv struct DvUpload {
  serial : Int
  station : String
  root : String
  dir : String
  mut name : String
  bytes : Bytes
  mut sent : Int
  /// waiting | going | taken | failed
  mut state : String
  mut error : String
  mut replace : Bool
  mut id : String
}

///|
/// The drive's state while the app runs.
priv struct DriveUi {
  mut sheet : DvSheet
  /// the sheet closing, what it showed kept until it is down
  mut closing : DvSheet
  /// the page the sheet is over (dv_page_of: the one that opened it), and the page being built: a page under another
  /// one (a folder pushed over 文件, both drawn while it slides in) draws no sheet of the other's
  mut sheet_on : String
  mut building : String
  /// what is chosen in a folder (by its page's key), by name
  chosen : Map[String, Array[String]]
  uploads : Array[DvUpload]
  mut serial : Int
  mut pumping : Bool
  /// what is under way on an entry ("remove|<station>|<root>|<path>"), and what failed a moment ago (its words: shown
  /// on its row for dv_failed_ms)
  busy : Map[String, Bool]
  failed : Map[String, String]
  /// folders being read again
  refreshing : Map[String, Bool]
  /// a row held: its id, whether the hold has acted
  mut held : Int
  mut held_done : Bool
  /// the views chosen here, before the prefs say
  mut sort_set : String?
  mut hidden_set : Bool?
  /// a file being picked to go up, and where to
  mut picking : @ui.Pick?
  mut picking_for : DriveAt
  /// what is asked for in an Ask sheet, the folder picker's place and filter
  mut asked : String
  mut picker_at : String?
  mut picker : Json?
  mut picker_error : String
  mut picker_denied : Bool
  mut picker_serial : Int
  /// the folder picker's last ask (`picker_serial`) on its way, not answered yet: what is shown is coming, not asked
  /// again
  mut picker_asking : Bool
  /// the Ask sheet's words and the folder picker's filter (their fields show them)
  mut ask_field : @ui.Field
  mut picker_filter : @ui.Field
}

///|
let dv : DriveUi = {
  sheet: NoSheet,
  closing: NoSheet,
  sheet_on: "",
  building: "",
  chosen: {},
  uploads: [],
  serial: 0,
  pumping: false,
  busy: {},
  failed: {},
  refreshing: {},
  held: 0,
  held_done: false,
  sort_set: None,
  hidden_set: None,
  picking: None,
  picking_for: { station: "", root: None, path: "" },
  asked: "",
  picker_at: None,
  picker: None,
  picker_error: "",
  picker_denied: false,
  picker_serial: 0,
  picker_asking: false,
  ask_field: @ui.Field::new(),
  picker_filter: @ui.Field::new(),
}

///|
/// As at the start (tests).
fn dv_reset() -> Unit {
  dv.sheet = NoSheet
  dv.closing = NoSheet
  dv.sheet_on = ""
  dv.building = ""
  dv.chosen.clear()
  dv.uploads.clear()
  dv.serial = 0
  dv.pumping = false
  dv.busy.clear()
  dv.failed.clear()
  dv.refreshing.clear()
  dv.held = 0
  dv.held_done = false
  dv.sort_set = None
  dv.hidden_set = None
  dv.picking = None
  dv.picking_for = { station: "", root: None, path: "" }
  dv.asked = ""
  // (a new one: an editor knows its Field by the build it was last given in, and a run started again counts builds
  // from the start)
  dv.ask_field = @ui.Field::new()
  dv.picker_filter = @ui.Field::new()
  dv.picker_at = None
  dv.picker = None
  dv.picker_error = ""
  dv.picker_denied = false
  dv.picker_serial = 0
  dv.picker_asking = false
  reader_set.clear()
  fix_folders.clear()
  fix_places.clear()
  fix_transfers.clear()
  fix_reads.clear()
  draft_refs.clear()
  sfs.open = false
  sfs.closing = false
  sfs.draft = ""
  sfs.place = None
  sfs.ticked.clear()
  sfs.ref = None
  sfs.ref_closing = false
}

///|
fn dv_open(c : @ui.Ctx, s : DvSheet) -> Unit {
  c.blur()
  dv.sheet = s
  dv.sheet_on = dv.building
}

///|
/// A drive's page by what it shows (文件, a station's drive or one of its folders): the page a sheet is over.
fn dv_page_of(at : DriveAt?) -> String {
  match at {
    None => "files"
    Some(a) =>
      "drive\u{1}" +
      a.station +
      "\u{1}" +
      (match a.root {
        Some(r) => r
        None => ""
      }) +
      "\u{1}" +
      a.path
  }
}

///|
fn dv_close(c : @ui.Ctx) -> Unit {
  match dv.sheet {
    NoSheet => ()
    s => {
      dv.closing = s
    }
  }
  dv.sheet = NoSheet
  c.blur()
}

///|
/// A card's ground (C.surface).
fn dv_surface() -> Int64 {
  @sf.theme().p.card
}

// ── the bar ──────────────────────────────────────────────────────────────

///|
/// A page's compact bar (Parts.kt NavBar): back and where to, the title in the middle, what it does at the right; no
/// line under it. True on the frame after back was tapped.
fn dv_nav_bar(c : @ui.Ctx, back : String, title : String, trailing : () -> Unit) -> Bool {
  // the wide frame's page bar (wide_chat.mbt)
  if wide_on.val {
    return page_bar_wide(c, title, app.nav.depth() > 1, trailing)
  }
  @sf.nav_bar(c, "dv-nav-back", back, title, trailing~, back_max=dmax(80.0, c.width / 2.0 - 120.0), bg=@sf.theme().p.bg, top=status_top())
}

///|
/// A round button in a bar (Parts.kt NavButton), 34 across, the icon alone (18 unless said).
fn dv_nav_button(c : @ui.Ctx, key : String, icon : String, size? : Double = 18.0, said? : String) -> Bool {
  nav_button(c, icon, size, key~, said?)
}

///|
/// A heading over a group of rows (Parts.kt SectionHeader): 15 semibold, 20 in.
fn dv_section(c : @ui.Ctx, label : String, trailing? : String = "") -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=20.0, pr=20.0, pt=14.0, pb=6.0, align=AEnd, fn() {
    c.box(w=Fill(1.0), fn() {
      c.text(label, size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0)
      |> ignore
    })
    |> ignore
    if trailing != "" {
      c.text(trailing, size=13.0, color=t.p.muted, wrap=false) |> ignore
    }
  })
  |> ignore
}

// ── buttons and fields ───────────────────────────────────────────────────

///|
/// A button (Controls.kt Button): 38 high, a pill; the primary one in ink (red when it is a danger), the other on the
/// chip's ground. True on the frame after it was tapped (not while busy or off).
fn dv_button(
  c : @ui.Ctx,
  key : String,
  label : String,
  primary~ : Bool,
  enabled? : Bool = true,
  busy? : Bool = false,
  danger? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let on = enabled && !busy
  let id = c.id(key)
  let ink = if primary && danger && enabled {
    0xFFFFFFFFL
  } else if primary {
    t.p.bg
  } else {
    t.p.text
  }
  let ground = if primary {
    if !enabled {
      t.p.line
    } else if danger {
      t.p.red
    } else {
      t.p.text
    }
  } else {
    t.p.chip
  }
  c.box(
    dir=Row,
    h=Px(38.0),
    radius=19.0,
    padx=16.0,
    gap=8.0,
    align=ACenter,
    bg=ground,
    id=if on { id } else { 0 },
    fn() {
      if busy {
        @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
      }
      c.text(label, size=14.0, weight=600, color=ink, wrap=false) |> ignore
      // Controls.kt Button: clickable over its capsule
      if on {
        @motion.ripple(c, id, 19.0)
      }
    },
  )
  |> ignore
  on && c.clicked(id)
}

///|
/// A row of a picking sheet (Controls.kt PickRow): an icon before it, what, a line under it, a check on the chosen one.
/// True on the frame after it was tapped.
fn dv_pick_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub? : String = "",
  icon? : String = "",
  color? : Int64 = 0L,
  icon_color? : Int64 = 0L,
  checked? : Bool = false,
  mark? : String = "",
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ink = if color == 0L { t.p.text } else { color }
  // (its icon in its words' colour, or one of its own: a link's row's in the accent, PickRow `leading`)
  let icon_ink = if icon_color == 0L { ink } else { icon_color }
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=8.0,
      pady=12.0,
      gap=12.0,
      align=ACenter,
      id~,
      fn() {
        if icon != "" {
          @sf.icon(c, icon, size=20.0, color=icon_ink) |> ignore
        }
        c.box(w=Fill(1.0), fn() {
          c.box(dir=Row, gap=6.0, align=ACenter, fn() {
            c.text(label, size=15.0, color=ink, wrap=false, line=21.0) |> ignore
            if mark != "" {
              c.text(mark, size=12.0, color=t.p.red, wrap=false) |> ignore
            }
          })
          |> ignore
          if sub != "" {
            c.text(sub, size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
          }
        })
        |> ignore
        if checked {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        }
        // Controls.kt PickRow: clip(Smooth(LIST_ROW_CORNER)).clickable
        @motion.ripple(c, id, @sf.row_corner)
      },
    )
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// A line to type in (Controls.kt Field): mbui's field in its look (@sf.field_look), its words 15 on 21.
fn dv_field(c : @ui.Ctx, key : String, placeholder : String, field : @ui.Field) -> String {
  @kit.text_field(c, key, placeholder~, size=15.0, line=21.0, look=@sf.field_look, field~).text
}

// ── sheets ───────────────────────────────────────────────────────────────

///|
/// A sheet's height for a title and `rows` rows (DriveScreen.kt fit).
fn dv_fit(rows : Int) -> Double {
  (96 + rows * 48 + 24).to_double()
}

///|
/// A sheet from the bottom over the page (Sheet.kt SheetHost, mbui's @kit.sheet): the scrim (black at 28%, a tap beside
/// it closes it), top corners of 26, frosted over the page and the scrim (@sf.sheet_look; `ground`: on that instead),
/// only drawn while it closes; `h` tall (most of the screen at most). Its grabber (SheetGrab) and head (SheetHead), then
/// `body`. The drive's sheets are one sheet, the reader's panels and Station 文件's (`reader`) another. `closing`: closed, drawn sinking
/// away on the sheet's springs (they ask for their frames) until it has gone, `gone` then told.
fn dv_sheet_frame(
  c : @ui.Ctx,
  title : String,
  h : Double,
  body : () -> Unit,
  closing~ : Bool,
  reader? : Bool = false,
  close? : (() -> Unit)? = None,
  gone? : () -> Unit = fn() { dv.closing = NoSheet },
  ground? : Int64 = 0L,
) -> Unit {
  let t = @sf.theme()
  let r = @kit.sheet(
    c,
    if reader { "dv-reader-sheet" } else { "dv-sheet" },
    !closing,
    h=dmin(h, c.height * 0.9),
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(ground~),
    fn() {
      c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
        c.box(w=Px(38.0), h=Px(5.0), radius=3.0, bg=t.p.line, fn() {  }) |> ignore
      })
      |> ignore
      if title != "" {
        c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, fn() {
          c.text(title, size=17.0, weight=700, color=t.p.text, wrap=false) |> ignore
        })
        |> ignore
      }
      c.box(w=Fill(1.0), h=Fill(1.0), clip=true, body) |> ignore
    },
  )
  if closing && !r.shown {
    gone()
  }
  if !closing && !r.open {
    match close {
      Some(f) => f()
      None => dv_close(c)
    }
  }
}

///|
/// The rows of a card in a list (DriveScreen.kt cardRow): 12 in from the sides, the first and last carrying its 16
/// corners, 10 under the last; each row list_pad in from the card's sides (and from its top on the first, its bottom
/// on the last), pressed and grounded (`ground`: a chosen row's, none for the card's own) in a row_corner, concentric
/// with the card's.
fn dv_card_row(
  c : @ui.Ctx,
  first : Bool,
  last : Bool,
  ground : Int64?,
  id : Int,
  body : () -> Unit,
) -> Unit {
  let card = dv_surface()
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, pb=if last { 10.0 } else { 0.0 }, fn() {
    c.box(w=Fill(1.0), fn() {
      c.layer(fn() {
        c.box(
          w=Fill(1.0),
          h=Fill(1.0),
          radius=if first || last { 16.0 } else { 0.0 },
          bg=card,
          fn() {  },
        )
        |> ignore
      })
      |> ignore
      // the corners the card does not have here: squared again
      if first != last || (!first && !last) {
        if !first {
          c.layer(fn() { c.box(w=Fill(1.0), h=Px(16.0), bg=card, fn() {  }) |> ignore })
          |> ignore
        }
        if !last {
          c.layer(fn() {
            c.spacer()
            c.box(w=Fill(1.0), h=Px(16.0), bg=card, fn() {  }) |> ignore
          })
          |> ignore
        }
      }
      let room = match (first, last) {
        (true, true) => dv_row_room_only
        (true, false) => dv_row_room_first
        (false, true) => dv_row_room_last
        (false, false) => dv_row_room
      }
      c.box(style=room, fn() {
        c.box(style=dv_row_ground, bg?=ground, id~, fn() {
          body()
          if id != 0 {
            @motion.ripple(c, id, @sf.row_corner)
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A card's row's room in it (DriveScreen.kt cardRow, Parts.kt LIST_PAD): 8 in from the card's sides, and from its top
/// on the first row, its bottom on the last.
// kept across runs: a value (no field of it changes)
let dv_row_room : @ui.Style = @ui.style(w=Full, px=S2)

///|
// kept across runs: a value (no field of it changes)
let dv_row_room_first : @ui.Style = @ui.style(w=Full, px=S2, pt=S2)

///|
// kept across runs: a value (no field of it changes)
let dv_row_room_last : @ui.Style = @ui.style(w=Full, px=S2, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let dv_row_room_only : @ui.Style = @ui.style(w=Full, p=S2)

///|
/// A card's row's own ground (pressed, chosen): rounded LIST_ROW_CORNER, concentric with the card's.
// kept across runs: a value (no field of it changes)
let dv_row_ground : @ui.Style = @ui.style(w=Full, radius=Xl2)

///|
/// A row held (a long press, 400 ms as the system's): true on the frame the hold acts, once; the tap that ends it is
/// then no tap (`dv_tapped`).
fn dv_held(c : @ui.Ctx, id : Int) -> Bool {
  let pressed = c.pressed(id)
  if pressed && dv.held != id {
    dv.held = id
    dv.held_done = false
  }
  // (`after` asks for the frame it acts on)
  if @kit.after(c, "dv-held/\{id}", pressed && dv.held == id && !dv.held_done && !c.press().moved, dv_hold_ms) {
    dv.held_done = true
    return true
  }
  if !pressed && dv.held == id && !c.clicked(id) {
    dv.held = 0
  }
  false
}

///|
/// How long a row is held before the hold acts (the system's long press).

let dv_hold_ms : Double = 400.0

///|
/// How long what failed on a row is said on it.
let dv_failed_ms : Double = 4000.0

///|
/// A tap on a row that was not a hold.
fn dv_tapped(c : @ui.Ctx, id : Int) -> Bool {
  if c.clicked(id) {
    let was_hold = dv.held == id && dv.held_done
    if dv.held == id {
      dv.held = 0
      dv.held_done = false
    }
    !was_hold
  } else {
    false
  }
}

///|
/// What the viewer set going, done: its failure said in a toast (AppState.act: 无法{what}：{error}).
fn dv_act(c : @ui.Ctx, what : String, done? : String = "") -> (Result[Json, Json]) -> Unit {
  fn(r) {
    match r {
      Ok(_) => if done != "" { say(c, done) }
      Err(e) =>
        say(
          c,
          fill("android-misc.act.failed", [("what", what), ("error", dv_error(e))]),
        )
    }
  }
}

///|
fn dv_error(e : Json) -> String {
  match text(Some(e), "message") {
    "" => tr("android-misc.failed")
    m => m
  }
}

///|
/// An entry's key for what is under way on it.
fn dv_key(op : String, station : String, root : String, path : String) -> String {
  op + "|" + station + "|" + root + "|" + path
}

///|
/// A call on an entry, marked under way on its row while it goes (DoingMark), its failure a moment's red mark there and
/// a toast.
fn dv_doing(
  c : @ui.Ctx,
  src : Source,
  key : String,
  what : String,
  call : String,
  params : Json,
  then? : (Json) -> Unit = fn(_) {  },
) -> Unit {
  dv.busy[key] = true
  dv.failed.remove(key)
  (src.call)(call, params, fn(r) {
    dv.busy.remove(key)
    match r {
      Ok(v) => then(v)
      Err(e) => {
        dv.failed[key] = dv_error(e)

        (dv_act(c, what))(r)
      }
    }
  })
}
