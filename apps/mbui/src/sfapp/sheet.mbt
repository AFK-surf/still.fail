// The app's sheets (ember apps/android shared/ui/Sheet.kt SheetHost), one at a time: each the library's panel
// (@sf.panel, src/sf presenters.mbt), with a finger the phone's sheet, its share of the screen, a draggable one between
// half (55%) and nearly all (94%); with a mouse beside what opened it. What it shows is its kind's (SheetKind), drawn
// anew each frame by what the frame tells (sheet_contents).

///|
/// Which sheet: what it shows and how it sits.
priv enum SheetKind {
  NoSheet
  /// what another app shares in, to a chat (ShareSheet.kt): 72%, draggable
  ShareSheet
  /// what an invitation's link leads to, before it is accepted (Workspaces.kt InviteLinkSheet): half the screen
  InviteLink
} derive(Eq)

///|
/// How a sheet sits: its share of the screen at first, whether its top drags it between half and full.
fn sheet_spec(kind : SheetKind) -> (Double, Bool) {
  match kind {
    ShareSheet => (0.72, true)
    InviteLink => (0.5, false)
    NoSheet => (0.5, false)
  }
}

///|
/// The sheet up (NoSheet: none), and the presenter it is (@sf.last_presented).
priv struct SheetHost {
  kind : @signals.Signal[SheetKind]
  serial : @signals.Signal[Int]
}

///|
let sheet_host : SheetHost = { kind: @signals.signal(NoSheet), serial: @signals.signal(0, same=fn(a, b) { a == b }) }

///|
/// What each kind draws, as this frame has it (its source, its workspace): told by the frame before the library's
/// host draws (sheet_contents).
// kept across runs: told anew by each frame before it is read
// (plain: a closure, what to do, not a value shown)
let sheet_drawer : Ref[(SheetKind) -> Unit] = Ref(fn(_) {  })

///|
/// Opens `kind` (in place of one open), by what opened it: the library's panel (@sf.panel), as tall as its share of
/// the window (a sheet with a finger, beside `from` or in the middle of the window with a mouse). What was typed lets
/// go of the keyboard first.
fn raise_sheet(kind : SheetKind, from? : @sf.Anchor = Unanchored) -> Unit {
  lower_sheet()
  let s = sheet_host
  s.kind.set(kind)
  let (share, draggable) = sheet_spec(kind)
  @sf.panel(
    // (each draws its own head: what is shared, an invitation)
    "",
    fn(_, _) { (sheet_drawer.val)(kind) },
    from~,
    tall=share,
    grows=draggable,
    gone=fn() {
      if s.kind.get() == kind {
        s.kind.set(NoSheet)
      }
    },
  )
  s.serial.set(@sf.last_presented())
}

///|
/// Closes the sheet open: it sinks away.
fn lower_sheet() -> Unit {
  if sheet_host.kind.get() != NoSheet {
    sheet_host.kind.set(NoSheet)
    @sf.close_presented_of(sheet_host.serial.get())
  }
}

///|
/// Whether a sheet is open.
fn sheet_open() -> Bool {
  sheet_host.kind.get() != NoSheet
}

///|
/// What the kinds draw this frame (call before the library's host, @sf.presented): `content` draws a kind's content in
/// the room it is given (closed by lower_sheet).
fn sheet_contents(content : (SheetKind) -> Unit) -> Unit {
  sheet_drawer.val = content
}

// The grabber and a sheet's head (Sheet.kt SheetGrab, SheetHead) are decide.mbt's `sheet_grab`, `sheet_head`.

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}
