// A link to a station's login (`/w/<ws>/s/<station>/login/<id>`): the station's page opens at its 设置, its 登录 (the
// pages' station_cards.mbt station_logins) brought into view.

///|
/// The login a link pointed to (AppState.open's `login`: Screen.Station(address, login)), on the station's page that
/// opens: its card marked, brought into view once (`true` once it was).
let login_marked : Ref[(String, String, Bool)?] = Ref(None)

///|
/// A link's login: the station's page about to open shows it marked, brought into view.
pub fn mark_login(address : String, login : String) -> Unit {
  login_marked.val = Some((address, login, false))
  // its card is in the page's 设置
  station_parts[address] = "settings"
}
