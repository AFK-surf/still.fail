// The small parts the phone's sheets are made of, as the Android app draws them (shared ui/Parts.kt NavBar, NavButton,
// SectionHeader; ui/Controls.kt Button, PickRow; ui/Sheet.kt SheetHost, SheetGrab, SheetHead): a station file's sheet and
// the reader's panels (station_files.mbt, viewer_host.mbt) until they are the library's presenters, and 文件's bar.

///|
/// As at the start (tests).
fn dv_reset() -> Unit {
  reader_set.clear()
  draft_refs.clear()
  sfs.ref.set(None)
  sfs.ref_closing.set(false)
}

// ── the bar ──────────────────────────────────────────────────────────────

///|
/// A page's compact bar (Parts.kt NavBar): back and where to, the title in the middle, what it does at the right; no
/// line under it. True on the frame after back was tapped.
fn dv_nav_bar(c : @ui.Ctx, back : String, title : String, trailing : () -> Unit) -> Bool {
  @sf.nav_bar(c, "dv-nav-back", back, title, trailing~, back_max=dmax(80.0, c.width / 2.0 - 120.0), bg=@sf.theme().p.bg, top=status_top())
}

///|
/// A round button in a bar (Parts.kt NavButton), 34 across, the icon alone (18 unless said).
fn dv_nav_button(c : @ui.Ctx, key : String, icon : String, size? : Double = 18.0, said? : String) -> Bool {
  nav_button(c, icon, size, key~, said?)
}

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
      c.text(label, size=@sf.theme().t.ui, weight=600, color=ink, wrap=false) |> ignore
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
/// A sheet from the bottom over the page (Sheet.kt SheetHost, mbui's @kit.sheet): the scrim (black at 28%, a tap beside
/// it closes it), top corners of 26, frosted over the page and the scrim (@sf.sheet_look; `ground`: on that instead),
/// only drawn while it closes; `h` tall (most of the screen at most), or with `fit` as tall as what it holds as this
/// frame lays it out (read back: `h` before it is first laid out; placed by its size, not chased). Its grabber
/// (SheetGrab) and head (SheetHead), then `body`. The drive's sheets are one sheet, the reader's panels and Station 文件's (`reader`) another. `closing`: closed, drawn sinking
/// away on the sheet's springs (they ask for their frames) until it has gone, `gone` then told.
fn dv_sheet_frame(
  c : @ui.Ctx,
  title : String,
  h : Double,
  body : () -> Unit,
  closing~ : Bool,
  reader? : Bool = false,
  close~ : () -> Unit,
  gone~ : () -> Unit,
  ground? : Int64 = 0L,
  trailing? : String = "",
  fit? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let fit_id = c.id(if reader { "dv-reader-sheet/fit" } else { "dv-sheet/fit" })
  let h = match (fit, c.laid_size(fit_id)) {
    // (and the room over the navigation bar, as the decisions' fitted sheets leave it)
    (true, Some((_, laid))) => laid + nav_foot()
    _ => h
  }
  let r = @kit.sheet(
    c,
    if reader { "dv-reader-sheet" } else { "dv-sheet" },
    !closing,
    h=dmin(h, c.height * 0.9),
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(ground~),
    fn() {
      // (fitted: all of it in one box as tall as it is, read back for the sheet's height)
      let all = fn(inner : () -> Unit) {
        if fit {
          c.box(style=dv_fit_all, id=fit_id, taps=false, inner) |> ignore
        } else {
          inner()
        }
      }
      all(fn() {
        c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
          c.box(w=Px(38.0), h=Px(5.0), radius=3.0, bg=t.p.line, fn() {  }) |> ignore
        })
        |> ignore
        if title != "" {
          c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, align=ACenter, fn() {
            c.text(title, size=t.t.title, weight=700, color=t.p.text, wrap=false) |> ignore
            // what is said beside it (SheetHead's trailing: the contents' count and how far read)
            if trailing != "" {
              c.box(style=dv_sheet_trailing, fn() {
                c.text(trailing, style=dv_sheet_trailing_words) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
        if fit {
          c.box(style=dv_fit_body, body) |> ignore
        } else {
          c.box(w=Fill(1.0), h=Fill(1.0), clip=true, body) |> ignore
        }
      })
    },
  )
  if closing && !r.shown {
    gone()
  }
  if !closing && !r.open {
    close()
  }
}

///|
/// A fitted sheet's all (as tall as it is) and its body (as tall as what it holds, cutting what goes past its sides).
// kept across runs: a value (no field of it changes)
let dv_fit_all : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let dv_fit_body : @ui.Style = @ui.css("w=Full clip")

///|
/// What a sheet's head says beside its title (the web's headNote: the page's meta size, quiet, at its end).
// kept across runs: a value (no field of it changes)
let dv_sheet_trailing : @ui.Style = @ui.style(w=@sf.grow, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let dv_sheet_trailing_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)
