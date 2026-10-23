// The settings' sheets (Sheet.kt SheetHost, one at a time): over the page from its foot, a share of the screen tall,
// its top corners round, frosted over the page, the grabber at its top, the page under it darkened; a tap there
// closes it. It comes up and goes down on the sheet's spring, the scrim in and out over 300 ms, and is only drawn as
// it goes (a tap meanwhile is what is under it's). What asks for a
// line (PageParts.kt ask: a station's new name), whether to go on (confirm), a station's actions, a device to confirm
// into security mode, a member's role are drawn in it.

///|
priv struct SheetHost {
  /// what it shows, or None when there is none; what it showed, drawn as it goes down
  mut draw : ((@ui.Ctx, Core) -> Unit)?
  mut last : ((@ui.Ctx, Core) -> Unit)?
  /// up last frame (gone down since: what was typed in it lets go of the keyboard)
  mut was_up : Bool
  /// how tall, as a share of the screen
  mut height : Double
  /// what to run when it closes by hand (the scrim, back)
  mut on_close : () -> Unit
  /// a count of sheets put up: each one's fields are its own
  mut serial : Int
}

///|
let sheet : SheetHost = {
  draw: None,
  last: None,
  was_up: false,
  height: 0.5,
  on_close: fn() {  },
  serial: 0,
}

///|
/// Puts a sheet up in place of any other (SheetSpec): `height` a share of the screen.
fn open_sheet(height : Double, draw : (@ui.Ctx, Core) -> Unit, on_close? : () -> Unit = fn() {  }) -> Unit {
  sheet.draw = Some(draw)
  sheet.height = height
  sheet.on_close = on_close
  sheet.serial += 1
}

///|
/// Takes the sheet away.
fn close_sheet() -> Unit {
  sheet.draw = None
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
  menu_overlay(c)
  // the desktop pages' dialogs (desk_page.mbt)
  desk_dialog_overlay(c)
  // the wide frame's question, while it is asked and as it goes
  match asked.val {
    Some(a) => {
      let r = @sf.confirm(
        c,
        "settings-confirm",
        asking.val is Some(_),
        a.title,
        a.words,
        a.action,
        cancel=tr("common.cancel"),
      )
      if r.confirmed {
        asking.val = None
        (a.run)()
      } else if !r.open {
        asking.val = None
      }
    }
    None => ()
  }
  let up = sheet.draw is Some(_)
  if up {
    sheet.last = sheet.draw
  } else if sheet.was_up {
    // let go of: a field in it is no longer typed into as it goes down
    c.blur()
  }
  sheet.was_up = up
  let draw = match sheet.last {
    Some(d) => d
    None => return
  }
  // up from below and back down on the sheet's spring, the scrim in and out (300 ms, CSS's ease): mbui's @kit.sheet
  // (Sheet.kt SheetHost); the page under it, darkened, closes it when tapped
  let r = @kit.sheet(
    c,
    "settings-sheet",
    up,
    share=sheet.height,
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(),
    fn() {
      c.scope(sheet.serial, fn() {
        @sf.sheet_grab(c)
        c.box(w=Fill(1.0), h=Fill(1.0), fn() { draw(c, core) }) |> ignore
      })
    },
  )
  if up && !r.open {
    close()
  }
  if !up && !r.shown {
    sheet.last = None
  }
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
/// The pages' editors' fields by their editors' keys (@ui.Field: the only way to write an editor), so an answer that
/// puts words in one writes them by its key; put back by reset.
let keyed_fields : Map[String, @ui.Field] = {}

///|
fn field_of(key : String) -> @ui.Field {
  match keyed_fields.get(key) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      keyed_fields[key] = f
      f
    }
  }
}

///|
/// A line to type in (Controls.kt Field): mbui's field in its look (@sf.field_look), its placeholder until it has
/// words, its words 15 on 21 (`secret`: as dots).
fn field_box(
  c : @ui.Ctx,
  key : String,
  placeholder : String,
  mono? : Bool = false,
  secret? : Bool = false,
  field? : @ui.Field,
) -> String {
  ignore(mono)
  @kit.text_field(c, key, placeholder~, secret~, size=15.0, line=21.0, look=@sf.field_look, field=match field {
    Some(f) => f
    None => field_of(key)
  }).text
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
  secret? : Bool = false,
) -> Unit {
  let key = "ask/" + (sheet.serial + 1).to_string()
  let filled : Ref[Bool] = Ref(false)
  // the line's words, `value` at first (this sheet's own)
  let field = @ui.Field::new(text=value)
  open_sheet(0.42, fn(c, _core) {
    let t = @sf.theme()
    if !filled.val {
      filled.val = true
      c.focus_editor(key)
    }
    sheet_head(c, title)
    c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
      let words = field_box(c, key, placeholder, secret~, field~).trim(chars=" \t\n").to_owned()
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
/// What the wide frame asks before something that cannot be undone (the web's Confirm, a dialog: confirm): its title,
/// what it does, its action, whether in red, and what goes on once it is said.
priv struct Asking {
  title : String
  words : String
  action : String
  danger : Bool
  run : () -> Unit
}

///|
/// What is asked now in the wide frame, and what was asked last (drawn while its dialog goes).
let asking : Ref[Asking?] = Ref(None)

///|
let asked : Ref[Asking?] = Ref(None)

///|
/// Asks before something that cannot be undone (PageParts.kt confirm, with `what`): its title, what it does, 取消 and
/// `action` (red when `danger`); the sheet closes at once and `run` goes on. The app's pages ask so too (a chat archived
/// while it keeps watch). In the wide frame the web's Confirm instead (@sf.confirm, a dialog in the middle of the window,
/// drawn by overlay).
pub fn confirm(title : String, words : String, action : String, run : () -> Unit, danger? : Bool = false) -> Unit {
  if wide.val {
    asking.val = Some({ title, words, action, danger, run })
    asked.val = asking.val
    return
  }
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
/// Its rows' ground menu_pad in from its edge, rounded menu_row, their words menu_words_in from its edge (MenuHost's
/// MENU_PAD, MENU_ROW).
let menu_pad : Double = 6.0

///|
let menu_row : Double = 14.0

///|
let menu_words_in : Double = 16.0

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
    id~,
    fn() {
      @sf.icon(c, "filter", size=20.0, color=if selected != 0 { t.p.accent } else { t.p.text }) |> ignore
      @motion.ripple(c, id, 17.0)
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
    c.box(w=Px(180.0), tx=dmax(12.0, menu.x), ty=menu.y, pad=menu_pad, radius=@sf.surface_corner(menu_pad, menu_row), bg=t.p.card, shadow=@sf.menu_raised.sigma, shadow_y=@sf.menu_raised.dy, shadow_color=@sf.menu_raised.color, clip=true, fn() {
      for i, label in menu.items {
        let id = c.id("settings-menu/" + i.to_string())
        if hit(c, id) {
          menu.up = false
          (menu.pick)(i)
        }
        c.box(
          dir=Row,
          w=Fill(1.0),
          padx=menu_words_in - menu_pad,
          pady=12.0,
          align=ACenter,
          justify=JBetween,
          radius=menu_row,
          id~,
          fn() {
            c.text(label, size=15.0, color=t.p.text, wrap=false, line=21.0) |> ignore
            if i == menu.selected {
              @sf.icon(c, "check", size=16.0, color=t.p.text) |> ignore
            } else {
              c.box(w=Px(16.0), h=Px(16.0), fn() {  }) |> ignore
            }
            // Sheet.kt MenuHost: clip(Smooth(MENU_ROW)).clickable
            @motion.ripple(c, id, menu_row)
          },
        )
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}
