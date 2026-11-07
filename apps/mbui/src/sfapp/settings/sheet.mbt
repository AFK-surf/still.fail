// What the settings' pages put up over them is the library's presenters' (@sf.panel, @sf.pick, @sf.ask, @sf.confirm),
// shown as the screen and the native input have them. A page with no core at hand when it puts one up (a station's card
// from a chat) draws with the frame's (panels_core).

///|
/// The core the settings' panels put up by what has none at hand draw with (a station's card, a device asking): the
/// frame's, said by panels_frame.
// kept across runs: said again by every frame (panels_frame)
let panels_core : Ref[Core?] = Ref(None)

///|
/// The settings' core for this frame (what a panel put up by what has none at hand draws with): call each frame, before
/// the presenters.
pub fn panels_frame(core : Core) -> Unit {
  panels_core.val = Some(core)
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
  @sf.ask(title, action, run, value~, placeholder~, hint~, secret~)
}

///|
/// Asks before something that cannot be undone (PageParts.kt confirm: @sf.confirm, in place of the sheet up): its
/// title, what it does, 取消 and `action` (red when `danger`). Said, it closes and `run` goes on.
pub fn confirm(title : String, words : String, action : String, run : () -> Unit, danger? : Bool = false) -> Unit {
  @sf.confirm(title, words, action, run, danger~)
}
