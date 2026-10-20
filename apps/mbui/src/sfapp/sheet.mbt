// One sheet from the bottom at a time (ember apps/android shared/ui/Sheet.kt SheetHost), mbui's @kit.sheet: it rises on
// a spring over a scrim (black at 28%), takes its share of the screen, and its top (the grabber and the head, 64 high)
// drags it: a draggable sheet between half (55%) and nearly all (94%) of the screen, or down to close (under 30%); any
// other only down, closing past 80. Let go, it goes on at the finger's speed to where it settles; a tap on a
// draggable sheet's grabber switches it between half and full. A tap on the scrim, back, or the sheet dragged down
// closes it; it sinks away on the same spring. What it shows is its kind's (SheetKind), drawn anew each frame.

///|
/// Which sheet: what it shows and how it sits.
priv enum SheetKind {
  NoSheet
  /// the workspaces (Workspaces.kt WorkspacesSheet): 70%, draggable
  Workspaces
  /// where a new chat runs (NewChat.kt pickStation): half the screen
  PickStation(String)
  /// what a new chat runs on (NewChat.kt openRunPicker): 66%; its accounts' list in place of it while `accounts`
  RunPicker(String)
  /// how a service's page's resources came (PreviewLoad.kt): its station and port, 62%
  LoadOf(String, Int)
  /// a service's page's sizes (Preview.kt openViewportSheet), by the service's key: 62%
  PageSizes(String)
  /// what another app shares in, to a chat (ShareSheet.kt): 72%, draggable
  ShareSheet
  /// what an invitation's link leads to, before it is accepted (Workspaces.kt InviteLinkSheet): half the screen
  InviteLink
} derive(Eq)

///|
/// How a sheet sits: its share of the screen at first, whether its top drags it between half and full.
fn sheet_spec(kind : SheetKind) -> (Double, Bool) {
  match kind {
    Workspaces => (0.7, true)
    PickStation(_) => (0.5, false)
    RunPicker(_) => (0.66, false)
    LoadOf(_, _) | PageSizes(_) => (0.62, false)
    ShareSheet => (0.72, true)
    InviteLink => (0.5, false)
    NoSheet => (0.5, false)
  }
}

///|
priv struct SheetHost {
  /// asked open (NoSheet: closed), and what is drawn (until it has sunk away)
  mut kind : SheetKind
  mut shown : SheetKind
  /// the run picker showing its accounts' list
  mut accounts : Bool
}

///|
let sheet_host : SheetHost = { kind: NoSheet, shown: NoSheet, accounts: false }

///|
/// Opens `kind` (in place of one open). What was typed lets go of the keyboard first.
fn raise_sheet(kind : SheetKind) -> Unit {
  let s = sheet_host
  s.kind = kind
  s.accounts = false
  run_picker_opened.val = false
}

///|
/// Closes the sheet open: it sinks away.
fn lower_sheet() -> Unit {
  sheet_host.kind = NoSheet
}

///|
/// Whether a sheet is open.
fn sheet_open() -> Bool {
  sheet_host.kind != NoSheet
}

///|
/// How tall `kind` is at first (its share of `total`).
fn sheet_tall(kind : SheetKind, total : Double) -> Double {
  let (share, _) = sheet_spec(kind)
  share * total
}

///|
/// A sheet's glass (Sheet.kt: frosted over the pages, the scrim's black and the surface at 80% over a 28px blur; the
/// scrim is drawn under it, so it is in what the glass frosts): `@sf.glass_sheet`, and where glass is drawn solid, what
/// it is with nothing under it but the paper (the paper, the scrim's black as far as it shows, the surface at 80%).
fn sheet_glass(scrim : Double) -> @ui.Glass {
  let t = @sf.theme()
  {
    ..@sf.glass_sheet(),
    solid: @sf.over(@sf.over(t.p.bg, @sf.alpha(0x000000FFL, 0.28 * scrim)), @sf.alpha(t.p.card, 0.8)),
  }
}

///|
/// The sheet, over everything (call last); `content` draws a kind's content in the room it is given.
fn sheet_layer(c : @ui.Ctx, content : (SheetKind) -> Unit) -> Unit {
  let s = sheet_host
  if s.kind != NoSheet {
    s.shown = s.kind
  }
  if s.shown == NoSheet {
    return
  }
  let kind = s.shown
  let (share, draggable) = sheet_spec(kind)
  let r = @kit.sheet(
    c,
    "sheet",
    s.kind != NoSheet,
    share~,
    detents=if draggable { [0.55, 0.94] } else { [] },
    close_below=0.3,
    scrim=@sf.sheet_scrim,
    // over another app, on the page's paper, not frosted (Sheet.kt SheetSpec solid: there is nothing of the app's under it)
    look=if share_over.val { @sf.sheet_look(ground=@sf.theme().p.bg) } else { @sf.sheet_look() },
    fn() {
      content(kind)
      // over another app the view reaches under the navigation bar: what the sheet shows kept above it, the sheet's
      // ground going on down to the screen's foot (Sheet.kt: windowInsetsPadding(navigationBars) inside the sheet)
      if share_over.val && share_foot.val > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(share_foot.val)), fn() {  }) |> ignore
      }
    },
  )
  // what it comes to, for scripted runs (e2e: a sheet opened and closed by dragging)
  match r.dragged {
    Some(DraggedClosed) => @host.log("SHEET dragged closed")
    Some(DraggedBack) => @host.log("SHEET dragged back")
    Some(DraggedTo(f)) => @host.log(if f > 0.72 { "SHEET dragged to 94%" } else { "SHEET dragged to 55%" })
    None => ()
  }
  if s.kind != NoSheet && !r.open {
    lower_sheet()
  }
  if s.kind == NoSheet && !r.shown {
    s.shown = NoSheet
  }
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
