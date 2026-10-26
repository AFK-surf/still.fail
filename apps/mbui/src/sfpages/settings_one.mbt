// The settings' pages only the narrow app had (本机缓存 and a chat's files kept, sharing a phone's screen with a station
// over ADB, an account on several stations), in the library's page frame in every frame: their content as the settings
// draw it (their `…_blocks`), each a line of a listed page, until each is drawn again of the library's parts with its
// area.

///|
/// 本机缓存 (FilesScreen): what this device keeps, by chat and the rest; each let go when asked.
pub fn kept_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  @sf.page(c, on_back=core.pop, frame~, "kept", @sf.t("android-settings.files.title"), @settings.kept_blocks(c, core), listed=true)
}

///|
/// A chat's files kept (FilesScreen's chat), or those of no chat known (`station` ""): each let go by its bin.
pub fn kept_chat_page(c : @ui.Ctx, core : Core, frame : PageFrame, station : String, thread : Int) -> Unit {
  let (title, blocks) = @settings.kept_chat_blocks(c, core, station, thread)
  @sf.page(c, on_back=core.pop, frame~, "kept/" + station + "/" + thread.to_string(), title, blocks, listed=true)
}

///|
/// A station's ADB (AdbScreen): this phone's screen shared with it, the station it is of over the title.
pub fn adb_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, address : String) -> Unit {
  let (name, blocks) = @settings.adb_blocks(c, core, here, address)
  @sf.page(c, on_back=core.pop, frame~, "adb/" + address, @sf.t("android-misc.adb.title"), blocks, listed=true, small=name)
}

///|
/// An account on several stations (ProfileAccountScreen): who it is and how it is over its title, then each station's
/// part.
pub fn profile_account_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, key : String) -> Unit {
  let (title, small, blocks) = @settings.profile_account_blocks(c, core, here, key)
  @sf.page(c, on_back=core.pop, frame~, "profile-account/" + key, title, blocks, listed=true, small~)
}
