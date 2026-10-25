// The settings' sheets (Sheet.kt SheetHost, one at a time): over the page from its foot, a share of the screen tall,
// its top corners round, frosted over the page, the grabber at its top, the page under it darkened; a tap there
// closes it. It comes up and goes down on the sheet's spring, the scrim in and out over 300 ms, and is only drawn as
// it goes (a tap meanwhile is what is under it's). A station's actions, a device to confirm into security mode, a
// member's role are drawn in it. What asks for a line (ask) and whether to go on (confirm) are the library's
// presenters (@sf.ask, @sf.confirm), put up in its place.

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
  sheet.draw is Some(_)
}

///|
/// Closes the sheet that is up, as a tap beside it does (the system's back).
pub fn close() -> Unit {
  if sheet.draw is Some(_) {
    sheet.draw = None
    (sheet.on_close)()
  }
}

///|
/// The sheet, over everything the app shows: call after the pages each frame.
pub fn overlay(c : @ui.Ctx, core : Core) -> Unit {
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
        @sf.sheet_laid(fn() { c.box(w=Fill(1.0), h=Fill(1.0), fn() { draw(c, core) }) |> ignore })
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
    c.text(title, size=t.t.title, weight=700, color=t.p.text, wrap=false, w=Fill(1.0), line=24.0) |> ignore
  })
  |> ignore
}

///|
/// The pages' editors' fields by their editors' keys (@ui.Field: the only way to write an editor), so an answer that
/// puts words in one writes them by its key; put back by reset.
let keyed_fields : Map[String, @ui.Field] = {}

///|
pub fn field_of(key : String) -> @ui.Field {
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
/// Asks for a line (PageParts.kt ask: @sf.ask, in place of the sheet up): its title, the field (with `value` in it at
/// first), a hint under it, then 取消 and `action`, which can be pressed once the line has words and differs from
/// `value`. Said, it closes and `run` goes on with the line, trimmed.
pub fn ask(
  title : String,
  value : String,
  placeholder : String,
  action : String,
  run : (String) -> Unit,
  hint? : String = "",
  secret? : Bool = false,
) -> Unit {
  close_sheet()
  @sf.ask(title, action, run, value~, placeholder~, hint~, secret~)
}

///|
/// Asks before something that cannot be undone (PageParts.kt confirm: @sf.confirm, in place of the sheet up): its
/// title, what it does, 取消 and `action` (red when `danger`). Said, it closes and `run` goes on.
pub fn confirm(title : String, words : String, action : String, run : () -> Unit, danger? : Bool = false) -> Unit {
  close_sheet()
  @sf.confirm(title, words, action, run, danger~)
}

///|
/// A button that opens a pick of `options` (PlaceRows.kt BandFilter: the filter's icon, in the accent while not the
/// first): @sf.pick, by it.
fn band_filter(c : @ui.Ctx, key : String, options : Array[String], selected : Int, pick : (Int) -> Unit) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  if hit(c, id) {
    let choices = options.mapi(fn(i, label) { @sf.choice(i.to_string(), label) })
    @sf.pick("", choices, selected.to_string(), fn(k) { pick(int_of(k, 0)) }, from=Of(id))
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
