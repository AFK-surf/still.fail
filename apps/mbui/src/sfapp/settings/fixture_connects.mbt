// The connects as the core gives them (client/core-ts views.ts), out of a `connects` value whose items are whole (each
// with its sessions, the one it delivers into and those it could deliver into instead, as the core sent them before
// they were rows): `connects` a row each (connects_rows), `connect` one whole without those it could deliver into, and
// `connectCandidates` those, each cut to what its choice shows (connect_said). The made-up cores describe their
// connects so; a replay of a trace from before the rows has them so from its run (sfreplay's source.mbt). Beside
// fixture_stations.mbt, which does the same for the stations.

///|
/// What a list's row of a connect carries (the core's `connects` items, ConnectRow).
// kept across runs: a table, never written
let connect_row_fields : Array[String] = ["station", "stationName", "connect"]

///|
/// What each session a connect could deliver into says (the core's `connectCandidates`, ConnectCandidate).
// kept across runs: a table, never written
let candidate_fields : Array[String] = ["key", "titleText", "description", "current"]

///|
/// `connects`' value `v` (whole items) as a list is sent it: each item its row.
pub fn connects_rows(v : Json?) -> Json? {
  match v {
    Some(Object(o)) => {
      let m = o.copy()
      match o.get("items") {
        Some(Array(a)) => m["items"] = Json::array(a.map(fn(x) { fields_kept(x, connect_row_fields) }))
        _ => ()
      }
      Some(Json::object(m))
    }
    _ => v
  }
}

///|
/// Connect `id` of station `address` out of the `connects` value `all` (whole items, every one's), as `connect`
/// (`candidates` false: its page, all of it but those it could deliver into) or `connectCandidates` (true: those, each
/// cut to what its choice shows) answer it: no value while the connects are not known, or it is not among them while
/// they are still read (or some station could not be); null where it is not there.
pub fn connect_said(all : Json?, address : String, id : String, candidates : Bool) -> Json? {
  guard all is Some(Object(_)) else { None }
  let found = items(all, "items")
    .iter()
    .find_first(fn(x) { text(Some(x), "station") == address && text(field(Some(x), "connect"), "id") == id })
  match found {
    Some(Object(o)) if candidates =>
      Some(
        Json::object({
          "candidates": Json::array(items(Some(Json::object(o)), "candidates").map(fn(c) { fields_kept(c, candidate_fields) })),
        }),
      )
    Some(Object(o)) => {
      let m = o.copy()
      m.remove("candidates")
      Some(Json::object(m))
    }
    _ => {
      let wait = field(all, "wait")
      if flag(wait, "reading") || items(wait, "failing").length() > 0 {
        None
      } else {
        Some(Json::null())
      }
    }
  }
}
