// A station's file in the draft, its card pressed (web's mobile/StationFiles.tsx openRefSheet, RefSheet; the wide
// screen's RefCard on hover, Chat.tsx): its name, where it is, how it goes (发送方式: its path, or the file; a folder of
// the chat's own station as a zip) and whether this chat takes such files as files. The presenters' panel from its card
// (a sheet with a finger short of Large, else a popover); what it says read anew from the draft each frame.

///|
/// The card of file `id` in draft `w` pressed: its panel up, by `card` (its card's id).
fn ref_panel(src : Source, w : Writing, station : String, id : String, name : String, card : Int) -> Unit {
  @sf.panel(name, fn(c, _) { ref_panel_body(c, src, w.key, station, id) }, from=Of(card))
}

///|
/// The panel of file `id` in draft `key` (`<station>:<chat>`) put up from no card (a screen's fixture: a sheet on a
/// phone, as from its card).
pub fn ref_panel_put(src : Source, key : String, station : String, id : String, name : String) -> Unit {
  @sf.panel(name, fn(c, _) { ref_panel_body(c, src, key, station, id) }, from=Unanchored)
}

///|
fn ref_panel_body(c : @ui.Ctx, src : Source, key : String, station : String, id : String) -> Unit {
  let w = @sfbase.writing(src, key)
  guard w.files.get().iter().find_first(fn(f) { text(Some(f), "id") == id }) is Some(f) else { return }
  let r = field(Some(f), "ref")
  let path = text(r, "path")
  let dir = flag(r, "dir")
  // where it is: its station and its folder
  let folder = match path.rev_find("/") {
    Some(i) if i > 0 => path.view(end_offset=i).to_owned()
    _ => path
  }
  // (its words on the panel's words' line, wherever it is drawn)
  c.box(style=@sf.panel_words_in(), fn() { c.text(text(r, "stationName") + " · " + folder, style=ref_where) |> ignore })
  |> ignore
  // how it goes: a folder only zipped on the chat's own station
  if !dir || text(r, "station") == station {
    c.box(style=ref_block, fn() {
      c.box(style=@sf.panel_words_in(), fn() { c.text(@sf.t("web-main.file.sendAs"), style=ref_label) |> ignore })
      |> ignore
      let now = if text(r, "mode") == "file" { 1 } else { 0 }
      let picked = @sf.segmented(c, "composer/ref/mode", [
        @sf.t("web-main.file.modePath"),
        @sf.t(if dir { "web-main.file.modeZip" } else { "web-main.file.modeFile" }),
      ], now)
      if picked != now {
        @sfbase.writing_mode(src, w, id, if picked == 0 { "path" } else { "file" })
      }
    })
    |> ignore
  }
  let chat = drops_as_files(src, key)
  // (this chat's say, a row as the page's rows are: on its card where narrow)
  c.box(style=ref_block, fn() {
    @sf.group(c, fn() {
      if @sf.switch_row(c, "composer/ref/chat-files", @sf.t("web-main.file.chatAsFiles"), chat) != chat {
        set_drops_as_files(src, key, !chat)
      }
    })
  })
  |> ignore
}

///|
/// Draft `key`'s chat set to take them as files or not (AppState.setDropsAsFiles): its own say dropped when it is the
/// device's anyway (prefs `dropAs`).
fn set_drops_as_files(src : Source, key : String, on : Bool) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let own : Json = if on == (text(prefs, "dropAs") == "file") { Json::null() } else { Json::boolean(on) }
  let files : Map[String, Json] = {}
  files[key] = own
  (src.call)("prefs.set", { "dropFiles": Json::object(files) }, fn(_) {  })
}

///|
/// Where it is (where): the meta size, a line under its name, 14 over what follows.
// kept across runs: a value (no field of it changes)
let ref_where : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// Each part (block): its label over it, 8 apart, 14 over the next.
// kept across runs: a value (no field of it changes)
let ref_block : @ui.Style = @ui.css("w=Full gap=S2 pt=S3_5")

///|
/// A part's label (label): the meta size, muted.
// kept across runs: a value (no field of it changes)
let ref_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)
