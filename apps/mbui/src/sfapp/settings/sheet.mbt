// The settings' sheets (Sheet.kt SheetHost, one at a time): over the page from its foot, a share of the screen tall,
// its top corners round, the grabber at its top, the page under it darkened; a tap there closes it. What asks for a
// line (PageParts.kt ask: a station's new name), whether to go on (confirm), a station's actions, a device to confirm
// into security mode, a member's role are drawn in it.

///|
priv struct SheetHost {
  /// what it shows, or None when there is none
  mut draw : ((@ui.Ctx, Core) -> Unit)?
  /// how tall, as a share of the screen
  mut height : Double
  /// when it was put up
  mut at : Double
  /// what to run when it closes by hand (the scrim, back)
  mut on_close : () -> Unit
  /// a count of sheets put up: each one's fields are its own
  mut serial : Int
}

///|
let sheet : SheetHost = {
  draw: None,
  height: 0.5,
  at: -1.0,
  on_close: fn() {  },
  serial: 0,
}

///|
/// Puts a sheet up in place of any other (SheetSpec): `height` a share of the screen.
fn open_sheet(height : Double, draw : (@ui.Ctx, Core) -> Unit, on_close? : () -> Unit = fn() {  }) -> Unit {
  sheet.draw = Some(draw)
  sheet.height = height
  sheet.at = -1.0
  sheet.on_close = on_close
  sheet.serial += 1
  wake()
}

///|
/// Takes the sheet away.
fn close_sheet() -> Unit {
  sheet.draw = None
  wake()
}

///|
/// Whether a sheet of the settings is up (the system's back closes it first).
pub fn sheet_up() -> Bool {
  sheet.draw is Some(_) || menu.up
}

///|
/// Closes the sheet that is up, as a tap beside it does (the system's back).
pub fn close() -> Unit {
  menu.up = false
  if sheet.draw is Some(_) {
    sheet.draw = None
    (sheet.on_close)()
  }
}

///|
/// The sheet, over everything the app shows: call after the pages each frame.
pub fn overlay(c : @ui.Ctx, core : Core) -> Unit {
  frame_ctx.val = Some(c)
  menu_overlay(c)
  let draw = match sheet.draw {
    Some(d) => d
    None => return
  }
  let t = @sf.theme()
  if sheet.at < 0.0 {
    sheet.at = c.now()
  }
  let shown = if c.stable() {
    1.0
  } else {
    let p = (c.now() - sheet.at) / 300.0
    if p >= 1.0 {
      1.0
    } else {
      c.request_frame()
      let q = 1.0 - dmax(p, 0.0)
      1.0 - q * q * q
    }
  }
  // the page under it, darkened: a tap there closes it
  let scrim = c.id("settings-sheet-scrim")
  if hit(c, scrim) {
    close()
    return
  }
  c.layer(fn() {
    c.box(w=Fill(1.0), h=Fill(1.0), bg=@sf.alpha(0x000000FFL, 0.28 * shown), id=scrim, fn() {  })
    |> ignore
  })
  |> ignore
  let h = c.height * sheet.height
  c.layer(fn() {
    c.spacer()
    c.box(
      w=Fill(1.0),
      h=Px(h + 26.0),
      ty=26.0 + (1.0 - shown) * (h + 26.0),
      radius=26.0,
      bg=t.p.card,
      shadow=24.0,
      clip=true,
      id=c.id("settings-sheet"),
      fn() {
        c.scope(sheet.serial, fn() {
          sheet_grab(c)
          c.box(w=Fill(1.0), h=Fill(1.0), pb=26.0, fn() { draw(c, core) }) |> ignore
        })
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The grabber at a sheet's top (Sheet.kt SheetGrab).
fn sheet_grab(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
    c.box(w=Px(38.0), h=Px(5.0), radius=3.0, bg=t.p.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A sheet's title (Sheet.kt SheetHead): 17 bold, 18 in.
fn sheet_head(c : @ui.Ctx, title : String, lead? : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, gap=8.0, align=ACenter, fn() {
    match lead {
      Some(f) => f()
      None => ()
    }
    c.text(title, size=17.0, weight=700, color=t.p.text, wrap=false, w=Fill(1.0), line=24.0) |> ignore
  })
  |> ignore
}

///|
/// A line to type in (Controls.kt Field): on a soft frame, its placeholder until it has words.
fn field_box(c : @ui.Ctx, key : String, placeholder : String, mono? : Bool = false) -> String {
  let t = @sf.theme()
  let mut words = ""
  c.box(
    w=Fill(1.0),
    padx=12.0,
    pady=10.0,
    radius=12.0,
    bg=t.p.card,
    border=1.0,
    border_color=t.p.line,
    fn() {
      let r = c.editor(
        key,
        placeholder~,
        font_size=15.0,
        max_lines=1,
        plain=true,
        line=21.0,
        color=t.p.text,
        placeholder_color=t.p.subtle,
        caret_color=t.p.accent,
        enter_sends=true,
      )
      ignore(mono)
      words = r.text
    },
  )
  |> ignore
  words
}

///|
/// Asks for a line (PageParts.kt ask): its title, the field (with `value` in it at first), a hint under it, then
/// 取消 and `action`, which is there once the line has words and differs from `value`. The sheet closes at once and
/// `run` goes on with the line, trimmed.
fn ask(
  title : String,
  value : String,
  placeholder : String,
  action : String,
  run : (String) -> Unit,
  hint? : String = "",
) -> Unit {
  let key = "ask/" + (sheet.serial + 1).to_string()
  let filled : Ref[Bool] = Ref(false)
  open_sheet(0.42, fn(c, _core) {
    let t = @sf.theme()
    if !filled.val {
      filled.val = true
      c.set_editor_text(key, value)
      c.focus_editor(key)
    }
    sheet_head(c, title)
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      let words = field_box(c, key, placeholder).trim(chars=" \t\n").to_owned()
      if hint != "" {
        c.text(hint, size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
      }
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if button(c, "ask-cancel", tr("common.cancel"), false) {
          c.blur()
          close_sheet()
        }
        if button(c, "ask-go", action, true, enabled=words != "" && words != value) {
          c.blur()
          close_sheet()
          run(words)
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Asks before something that cannot be undone (PageParts.kt confirm, with `what`): its title, what it does, 取消 and
/// `action` (red when `danger`); the sheet closes at once and `run` goes on.
fn confirm(title : String, words : String, action : String, run : () -> Unit, danger? : Bool = false) -> Unit {
  open_sheet(0.36, fn(c, _core) {
    let t = @sf.theme()
    sheet_head(c, title)
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      c.text(words, size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
      c.box(dir=Row, w=Fill(1.0), pt=6.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
        if button(c, "confirm-cancel", tr("common.cancel"), false) {
          close_sheet()
        }
        if button(c, "confirm-go", action, true, danger~) {
          close_sheet()
          run()
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A menu from a button (Sheet.kt MenuHost, PlaceRows.kt BandFilter): 180 wide, its right edge under the button's,
/// its items with a check on the one chosen; a tap beside it closes it.
priv struct MenuHost {
  mut items : Array[String]
  mut selected : Int
  mut x : Double
  mut y : Double
  mut pick : (Int) -> Unit
  mut up : Bool
}

///|
let menu : MenuHost = { items: [], selected: -1, x: 0.0, y: 0.0, pick: fn(_) {  }, up: false }

///|
/// A button that opens a menu of `options` (BandFilter): the filter's icon, in the accent while not the first.
fn band_filter(c : @ui.Ctx, key : String, options : Array[String], selected : Int, pick : (Int) -> Unit) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  if hit(c, id) {
    match c.rect_of(id) {
      Some(r) => {
        menu.items = options
        menu.selected = selected
        menu.x = r.0 + r.2 - 180.0
        menu.y = r.1 + r.3 + 6.0
        menu.pick = pick
        menu.up = true
      }
      None => ()
    }
  }
  c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.08) } else { 0L },
    id~,
    fn() {
      @sf.icon(c, "filter", size=20.0, color=if selected != 0 { t.p.accent } else { t.p.text }) |> ignore
    },
  )
  |> ignore
}

///|
fn menu_overlay(c : @ui.Ctx) -> Unit {
  if !menu.up {
    return
  }
  let t = @sf.theme()
  let scrim = c.id("settings-menu-scrim")
  if hit(c, scrim) {
    menu.up = false
    return
  }
  c.layer(fn() { c.box(w=Fill(1.0), h=Fill(1.0), id=scrim, fn() {  }) |> ignore }) |> ignore
  c.layer(fn() {
    c.box(w=Px(180.0), tx=dmax(12.0, menu.x), ty=menu.y, radius=14.0, bg=t.p.card, shadow=18.0, shadow_y=6.0, clip=true, fn() {
      for i, label in menu.items {
        let id = c.id("settings-menu/" + i.to_string())
        if hit(c, id) {
          menu.up = false
          (menu.pick)(i)
        }
        c.box(
          dir=Row,
          w=Fill(1.0),
          padx=16.0,
          pady=12.0,
          align=ACenter,
          justify=JBetween,
          bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
          id~,
          fn() {
            c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
            if i == menu.selected {
              @sf.icon(c, "check", size=16.0, color=t.p.text) |> ignore
            } else {
              c.box(w=Px(16.0), h=Px(16.0), fn() {  }) |> ignore
            }
          },
        )
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}
