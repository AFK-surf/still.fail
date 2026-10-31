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

///|
/// The station's page (list `key`) brought to its login a link pointed to, at block `at` (its cards under way), once
/// the page's list is there.
fn bring_marked_login(c : @ui.Ctx, address : String, key : String, at : Int) -> Unit {
  match login_marked.val {
    Some((a, m, false)) if a == address && c.list_info_as(key, fn(i) { i is Some(_) }) is Some(_) => {
      c.list_scroll_to(key, at)
      login_marked.val = Some((a, m, true))
    }
    _ => ()
  }
}
