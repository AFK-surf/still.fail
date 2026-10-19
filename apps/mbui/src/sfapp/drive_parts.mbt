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
  mut sheet_at : Double
  /// the sheet closing (from when), what it showed kept until it is down
  mut closing : DvSheet
  mut closed_at : Double
  /// what is chosen in a folder (by its page's key), by name
  chosen : Map[String, Array[String]]
  uploads : Array[DvUpload]
  mut serial : Int
  mut pumping : Bool
  /// what is under way on an entry ("remove|<station>|<root>|<path>"), and what failed a moment ago (its words, when)
  busy : Map[String, Bool]
  failed : Map[String, (String, Double)]
  /// folders being read again
  refreshing : Map[String, Bool]
  /// a row held: its id, since when, whether the hold has acted
  mut held : Int
  mut held_at : Double
  mut held_done : Bool
  /// the views chosen here, before the prefs say
  mut sort_set : String?
  mut hidden_set : Bool?
  /// a file being picked to go up, and where to
  mut picking : @host.Pick?
  mut picking_for : DriveAt
  /// what is asked for in an Ask sheet, the folder picker's place and filter
  mut asked : String
  mut picker_at : String?
  mut picker : Json?
  mut picker_error : String
  mut picker_denied : Bool
  mut picker_serial : Int
}

///|
let dv : DriveUi = {
  sheet: NoSheet,
  sheet_at: 0.0,
  closing: NoSheet,
  closed_at: 0.0,
  chosen: {},
  uploads: [],
  serial: 0,
  pumping: false,
  busy: {},
  failed: {},
  refreshing: {},
  held: 0,
  held_at: 0.0,
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
}

///|
/// As at the start (tests).
fn dv_reset() -> Unit {
  dv.sheet = NoSheet
  dv.closing = NoSheet
  dv.chosen.clear()
  dv.uploads.clear()
  dv.pumping = false
  dv.busy.clear()
  dv.failed.clear()
  dv.refreshing.clear()
  dv.held = 0
  dv.held_done = false
  dv.sort_set = None
  dv.hidden_set = None
  dv.picking = None
  reader_ui.clear()
  reader_set.clear()
  dv_reads.clear()
  fix_folders.clear()
  fix_places.clear()
  draft_refs.clear()
  sfs.open = false
  sfs.ticked.clear()
}

///|
fn dv_open(c : @ui.Ctx, s : DvSheet) -> Unit {
  c.blur()
  dv.sheet = s
  dv.sheet_at = c.now()
}

///|
fn dv_close(c : @ui.Ctx) -> Unit {
  match dv.sheet {
    NoSheet => ()
    s => {
      dv.closing = s
      dv.closed_at = c.now()
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
/// Back, in the accent: a chevron and where to (Parts.kt NavBack).
fn dv_nav_back(c : @ui.Ctx, key : String, label : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    dir=Row,
    pr=6.0,
    pt=4.0,
    pb=4.0,
    radius=8.0,
    align=ACenter,
    opacity=if c.pressed(id) { 0.6 } else { 1.0 },
    id~,
    fn() {
      @sf.icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore
      c.box(max_w=dmax(80.0, c.width / 2.0 - 120.0), fn() {
        c.text(label, size=17.0, color=t.p.accent, wrap=false) |> ignore
      })
      |> ignore
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// A page's compact bar (Parts.kt NavBar): back and where to, the title in the middle, what it does at the right; no
/// line under it. True on the frame after back was tapped.
fn dv_nav_bar(c : @ui.Ctx, back : String, title : String, trailing : () -> Unit) -> Bool {
  let t = @sf.theme()
  let mut went = false
  c.box(w=Fill(1.0), bg=t.p.bg, pl=10.0, pr=16.0, pt=6.0, pb=10.0, fn() {
    c.box(dir=Row, w=Fill(1.0), h=Px(32.0), align=ACenter, fn() {
      went = dv_nav_back(c, "dv-nav-back", back)
      c.spacer()
      c.box(dir=Row, h=Px(32.0), align=ACenter, trailing) |> ignore
      c.layer(align=ACenter, fn() {
        c.box(h=Px(30.0), justify=JCenter, pl=84.0, pr=84.0, fn() {
          c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  went
}

///|
/// A round button in a bar (Parts.kt NavButton), 34 across, the icon alone (18 unless said).
fn dv_nav_button(c : @ui.Ctx, key : String, icon : String, size? : Double = 18.0) -> Bool {
  nav_button(c, icon, size, key~)
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
    bg=if on && c.pressed(id) { @sf.mix(ground, 0.85, t.p.bg) } else { ground },
    id=if on { id } else { 0 },
    fn() {
      if busy {
        @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
      }
      c.text(label, size=14.0, weight=600, color=ink, wrap=false) |> ignore
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
  checked? : Bool = false,
  mark? : String = "",
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ink = if color == 0L { t.p.text } else { color }
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=8.0,
      pady=12.0,
      gap=12.0,
      align=ACenter,
      bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
      id~,
      fn() {
        if icon != "" {
          @sf.icon(c, icon, size=20.0, color=ink) |> ignore
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
      },
    )
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// A line to type in, on a soft frame (Controls.kt Field): 12 corners, the card's ground, a line round it.
fn dv_field(c : @ui.Ctx, key : String, placeholder : String) -> String {
  let t = @sf.theme()
  let mut words = ""
  c.box(
    w=Fill(1.0),
    radius=12.0,
    bg=t.p.card,
    border=1.0,
    border_color=t.p.line,
    padx=12.0,
    pady=10.0,
    fn() {
      let res = c.editor(
        key,
        placeholder~,
        font_size=15.0,
        line=21.0,
        max_lines=1,
        plain=true,
        color=t.p.text,
        placeholder_color=t.p.subtle,
        caret_color=t.p.accent,
      )
      words = res.text
    },
  )
  |> ignore
  words
}

// ── sheets ───────────────────────────────────────────────────────────────

///|
/// A sheet's height for a title and `rows` rows (DriveScreen.kt fit).
fn dv_fit(rows : Int) -> Double {
  (96 + rows * 48 + 24).to_double()
}

///|
/// A sheet from the bottom over the page (Sheet.kt SheetHost): the scrim (black at 28%, a tap beside it closes it),
/// top corners of 26, the page's paper under the card's ground at 80%; `h` tall (most of the screen at most). Its
/// grabber (SheetGrab) and head (SheetHead), then `body`.
fn dv_sheet_frame(
  c : @ui.Ctx,
  title : String,
  h : Double,
  body : () -> Unit,
  closing~ : Bool,
  at? : Double = -1.0,
  close? : (() -> Unit)? = None,
  ground? : Int64 = 0L,
) -> Unit {
  let t = @sf.theme()
  let at = if at >= 0.0 {
    at
  } else if closing {
    dv.closed_at
  } else {
    dv.sheet_at
  }
  let k = opening(c, at, 300.0)
  let shown = if closing { 1.0 - k } else { k }
  if !closing {
    scrim(c, "dv-scrim", shown, fn() {
      match close {
        Some(f) => f()
        None => dv_close(c)
      }
    })
  } else {
    c.layer(fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=@sf.alpha(0x000000FFL, 0.28 * shown), fn() {  })
      |> ignore
    })
    |> ignore
  }
  let h = dmin(h, c.height * 0.9)
  c.layer(fn() {
    c.spacer()
    c.box(
      w=Fill(1.0),
      h=Px(h + 26.0),
      ty=26.0 + (1.0 - shown) * (h + 26.0),
      radius=26.0,
      bg=if ground != 0L { ground } else { @sf.mix(t.p.card, 0.8, t.p.bg) },
      shadow=24.0,
      clip=true,
      id=c.id("dv-sheet"),
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
        c.box(w=Fill(1.0), h=Fill(1.0), pb=26.0, clip=true, body) |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The rows of a card in a list (DriveScreen.kt cardRow): 12 in from the sides, the first and last carrying its 16
/// corners, 10 under the last.
fn dv_card_row(
  c : @ui.Ctx,
  first : Bool,
  last : Bool,
  ground : Int64,
  id : Int,
  body : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, pb=if last { 10.0 } else { 0.0 }, fn() {
    c.box(w=Fill(1.0), fn() {
      c.layer(fn() {
        c.box(
          w=Fill(1.0),
          h=Fill(1.0),
          radius=if first || last { 16.0 } else { 0.0 },
          bg=ground,
          fn() {  },
        )
        |> ignore
      })
      |> ignore
      // the corners the card does not have here: squared again
      if first != last || (!first && !last) {
        if !first {
          c.layer(fn() { c.box(w=Fill(1.0), h=Px(16.0), bg=ground, fn() {  }) |> ignore })
          |> ignore
        }
        if !last {
          c.layer(fn() {
            c.spacer()
            c.box(w=Fill(1.0), h=Px(16.0), bg=ground, fn() {  }) |> ignore
          })
          |> ignore
        }
      }
      if id != 0 && c.pressed(id) {
        c.layer(fn() {
          c.box(
            w=Fill(1.0),
            h=Fill(1.0),
            radius=if first && last { 16.0 } else { 0.0 },
            bg=@sf.alpha(t.p.text, 0.05),
            fn() {  },
          )
          |> ignore
        })
        |> ignore
      }
      c.box(w=Fill(1.0), id~, body) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row held (a long press, 400 ms as the system's): true on the frame the hold acts, once; the tap that ends it is
/// then no tap (`dv_tapped`).
fn dv_held(c : @ui.Ctx, id : Int) -> Bool {
  if c.pressed(id) {
    if dv.held != id {
      dv.held = id
      dv.held_at = c.now()
      dv.held_done = false
    }
    let held = c.now() - dv.held_at
    if !dv.held_done && !cui.moved {
      if held >= 400.0 {
        dv.held_done = true
        return true
      }
      c.wake_in(400.0 - held)
    }
  } else if dv.held == id && !c.clicked(id) {
    dv.held = 0
  }
  false
}

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
        dv.failed[key] = (dv_error(e), c.now())
        (dv_act(c, what))(r)
      }
    }
  })
}
