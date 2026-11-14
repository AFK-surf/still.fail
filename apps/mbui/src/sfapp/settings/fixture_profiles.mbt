// The workspace's accounts as the core gives them (client/core-ts views.ts), out of a `profiles` value whose items are
// whole (each an account as its own page reads it, WorkspaceProfile, as the core sent them before they were rows):
// `profiles` a row each (profiles_rows), `profile` one whole (profile_said). The made-up cores describe their accounts
// so; a replay of a trace from before the rows has them so from its run (sfreplay's source.mbt). Beside
// fixture_connects.mbt, which does the same for the connects.

///|
/// What a list's row of an account carries (the core's `profiles` items, ProfileRow), but what the core works out of
/// the rest (`several`, `usedCount`: profile_row_said).
// kept across runs: a table, never written
let profile_row_fields : Array[String] = ["key", "group", "groupTitle", "station", "profile", "title", "usable", "state", "look", "where"]

///|
/// What a row's profile carries (RowProfile).
// kept across runs: a table, never written
let row_profile_fields : Array[String] = [
  "id", "name", "runtime", "access", "providerMark", "checkText", "checkTone", "usesText", "kindText", "planText", "quota",
]

///|
/// What a row's allowance carries (RowQuota): its windows as their chips draw them (quota_window_fields).
// kept across runs: a table, never written
let row_quota_fields : Array[String] = ["state", "windows", "creditsText"]

///|
/// Account `e` (whole) as its row: the row's fields, whether it is signed in on several of its members (those not a
/// copy of another station's) and how many use its profile, as views/profiles.ts makes them.
pub fn profile_row_said(e : Json) -> Json {
  let ev = Some(e)
  let several = items(ev, "members").filter(fn(m) { text(Some(m), "role") != "user" }).length() > 1
  let used = items(field(ev, "profile"), "usedBy").length()
  let row = fields_kept(e, profile_row_fields)
    |> field_made("profile", fn(p) {
      fields_kept(p, row_profile_fields)
      |> field_made("quota", fn(q) {
        fields_kept(q, row_quota_fields) |> field_made("windows", fn(w) { each_made(w, fn(x) { fields_kept(x, quota_window_fields) }) })
      })
    })
  match row {
    Object(o) => {
      let m = o.copy()
      m["several"] = Json::boolean(several)
      m["usedCount"] = Json::number(used.to_double())
      Json::object(m)
    }
    v => v
  }
}

///|
/// `profiles`' value `v` (whole items) as a list is sent it: each item its row.
pub fn profiles_rows(v : Json?) -> Json? {
  match v {
    Some(Object(o)) => {
      let m = o.copy()
      match o.get("items") {
        Some(Array(a)) => m["items"] = Json::array(a.map(profile_row_said))
        _ => ()
      }
      Some(Json::object(m))
    }
    _ => v
  }
}

///|
/// One account out of the `profiles` value `all` (whole items, every one's), as `profile` answers what it is asked
/// (`params`: its `key`, else `station` and `id`, a profile of it there): no value while the accounts are not known;
/// null where it is not there.
pub fn profile_said(all : Json?, params : Map[String, Json]) -> Json? {
  guard all is Some(Object(_)) else { None }
  let p = Some(Json::object(params))
  let key = opt_text(p, "key")
  let station = text(p, "station")
  let id = text(p, "id")
  let found = items(all, "items")
    .iter()
    .find_first(fn(e) {
      match key {
        Some(k) => text(Some(e), "key") == k
        None => items(Some(e), "members").iter().any(fn(m) { text(Some(m), "station") == station && text(Some(m), "profileId") == id })
      }
    })
  match found {
    Some(e) => Some(e)
    None => Some(Json::null())
  }
}
