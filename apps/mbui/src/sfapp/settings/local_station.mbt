// What 本机 Station rests on (its page: src/sfpages local_station.mbt, one in every frame): whether this machine's
// station is the app's to add and update, how the machine is called, its data's folder named as the system names it,
// how often the page reads it again; 添加这台 Mac where a station is added.

///|
/// Whether this machine's station is the app's to add and to bring up to date (its host runs the station's installer:
/// macOS's, Windows', Linux's); a phone's and a page's are not.
pub fn local_station_managed() -> Bool {
  let p = @ui.platform()
  p == 0 || p == 3 || p == 5
}

///|
/// Whether this machine can be added from here now (添加这台 Mac): the app adds its station (local_station_managed) and
/// there is none here, nor one being installed.
pub fn local_station_addable() -> Bool {
  if !local_station_managed() {
    return false
  }
  let s = Some(@json.parse(@ui.local_station()) catch { _ => Json::null() })
  text(s, "data") == "" && text(s, "doing") == ""
}

///|
/// 添加这台 Mac offered where a station is added (添加 station's sheet, a workspace's first): what it does, its button;
/// pressed, `then` (the sheet closed), the station added and 本机 Station opened, where how far it is shows.
fn add_this_machine(c : @ui.Ctx, core : Core, then : () -> Unit) -> Unit {
  let pc = local_machine_pc()
  c.box(style=here_column, fn() {
    c.text(tr(if pc { "android-settings.station.addHerePc" } else { "android-settings.station.addHere" }), style=here_words)
    |> ignore
    if @sf.button(c, tr(if pc { "web-pages.settings.thisPc.add" } else { "web-pages.settings.thisMac.add" }), key="add-here") {
      then()
      (core.local_install)(true)
      (core.push)(LocalStation)
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
/// 添加这台 Mac's words over its button.
let here_column : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let here_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
/// 添加这台 Mac in 添加 station's sheet: in from its sides as its words are, apart from the steps under it.
let here_room : @ui.Style = @ui.css("w=Full pb=S4")

///|
/// This machine called as the person would call it: a Mac, else a computer (Windows', Linux's: 这台电脑).
pub fn local_machine_pc() -> Bool {
  @ui.platform() == 3 || @ui.platform() == 5
}

///|
/// Its data shown in the system's own file manager, named as the system names it (Finder, Explorer, a Linux desktop's).
pub fn local_folder_label() -> String {
  tr(
    match @ui.platform() {
      3 => "web-pages.localStation.openFolderPc"
      5 => "web-pages.localStation.openFolderFiles"
      _ => "web-pages.localStation.openFolder"
    },
  )
}

///|
/// How often the page reads the station again while shown (LocalStation.tsx: 3 s).
pub let local_read_ms : Double = 3000.0
