// A station's file in the draft, its card pressed (web's mobile/StationFiles.tsx openRefSheet, RefSheet; the wide
// screen's RefCard on hover, Chat.tsx): its name, where it is, how it goes (发送方式: its path, or the file; a folder of
// the chat's own station as a zip) and whether this chat takes such files as files. The presenters' panel from its card
// (a sheet with a finger short of Large, else a popover); what it holds nodes of the window's tree, made once as it
// opens (@sf.panel_nodes), bound to what the draft says of the file.

///|
/// The card of file `id` in draft `w` pressed: its panel up, by `card` (its card's id).
fn ref_panel(src : Source, w : Writing, station : String, id : String, name : String, card : Int) -> Unit {
  @sf.panel_nodes(name, fn(v, close) { ref_panel_body(v, close, src, w.key, station, id) }, from=Of(card))
}

///|
/// The panel of file `id` in draft `key` (`<station>:<chat>`) put up from no card (a screen's fixture: a sheet on a
/// phone, as from its card).
pub fn ref_panel_put(src : Source, key : String, station : String, id : String, name : String) -> Unit {
  @sf.panel_nodes(name, fn(v, close) { ref_panel_body(v, close, src, key, station, id) }, from=Unanchored)
}

///|
/// What the panel of file `id` in draft `key` holds, in node `v` (its body's), made once as it opens, bound to what the
/// draft says of it: where it is, how it goes (what is picked told to the draft as it is picked), this chat's say
/// (turned, set as it is turned). The file taken out of the draft: the panel closes (`close`), what it showed last kept
/// as it goes.
fn ref_panel_body(v : @view.View, close : () -> Unit, src : Source, key : String, station : String, id : String) -> Unit {
  let w = @signals.untracked(fn() { @sfbase.writing(src, key) })
  let now = fn() { w.files.get().iter().find_first(fn(f) { text(Some(f), "id") == id }) }
  let last : Ref[Json?] = Ref(None)
  let file = fn() {
    match now() {
      Some(f) => {
        last.val = Some(f)
        Some(f)
      }
      None => last.val
    }
  }
  v.reacts(fn() { now() is None }, fn(gone) {
    if gone {
      close()
    }
  })
  let r = fn() { field(file(), "ref") }
  let dir = fn() { flag(r(), "dir") }
  // where it is: its station and its folder (its words on the panel's words' line, wherever it is drawn)
  v.box(fn(b) {
    @sf.style_node(b, fn() { @sf.panel_words_in_node(b) })
    @sf.words_node(
      b,
      fn() {
        let path = text(r(), "path")
        let folder = match path.rev_find("/") {
          Some(i) if i > 0 => path.exact_view(end=i).to_owned()
          _ => path
        }
        text(r(), "stationName") + " · " + folder
      },
      fn() { ref_where },
    )
    |> ignore
  })
  |> ignore
  // how it goes: a folder only zipped on the chat's own station
  v.show(fn() { !dir() || text(r(), "station") == station }, fn(block) {
    @sf.style_node(block, fn() { ref_block })
    block.box(fn(b) {
      @sf.style_node(b, fn() { @sf.panel_words_in_node(b) })
      @sf.words_node(b, fn() { @sf.t("web-main.file.sendAs") }, fn() { ref_label }) |> ignore
    })
    |> ignore
    let chosen = fn() { if text(r(), "mode") == "file" { 1 } else { 0 } }
    block.box(fn(line) {
      line.row(Is(true)) |> ignore
      line.box(fn(slot) {
        @sf.segmented_node(
          slot,
          fn() {
            [
              @sf.t("web-main.file.modePath"),
              @sf.t(if dir() { "web-main.file.modeZip" } else { "web-main.file.modeFile" }),
            ]
          },
          chosen,
          fn(picked) {
            if picked != @signals.untracked(chosen) {
              @sfbase.writing_mode(src, w, id, if picked == 0 { "path" } else { "file" })
            }
          },
        )
      })
      |> ignore
    })
    |> ignore
  })
  // (this chat's say, a row as the page's rows are: on its card where narrow; the last of it, as far over the
  // dialog's foot as from its sides)
  v.box(fn(block) {
    @sf.style_node(block, fn() { ref_block.then(@sf.panel_card_last_node(block)) })
    @sf.group_node(block, fn(g) {
      @sf.switch_row_node(g, fn() { @sf.t("web-main.file.chatAsFiles") }, fn() { drops_as_files(src, key) }, fn(on) {
        set_drops_as_files(src, key, on)
      })
    })
  })
  |> ignore
}

///|
/// Draft `key`'s chat set to take them as files or not (AppState.setDropsAsFiles): its own say dropped when it is the
/// device's anyway (prefs `dropAs`).
fn set_drops_as_files(src : Source, key : String, on : Bool) -> Unit {
  let prefs = src.topic("prefs", {}).get().value
  let own : Json = if on == (text(prefs, "dropAs") == "file") { Json::null() } else { Json::boolean(on) }
  let files : Map[String, Json] = Map([])
  files[key] = own
  (src.call)("prefs.set", { "dropFiles": Json::object(files) }, @sfbase.answer_unread)
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
