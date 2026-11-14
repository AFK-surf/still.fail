// A station's terminals as a made-up core gives them: three on ws1/st1 (one typed into by someone else, one nobody
// looks at, one idle), and a terminal's view: its state, then its screen (vim on a file) and a line after it. The
// pictures of the 终端 part and its page, and their tests, are drawn of these.

///|
/// The `terminals` topic: ws1/st1's three in the terminals' own modes, another station's none; in any other mode not
/// known (a station from before terminals, as a device's host keeps none yet: what the Mac's own run of a mode shows,
/// screens_wbtest's text recorded there).
fn fixture_terminals(station : String, mode : String) -> Json {
  if !["settings-station-terminals", "terminal", "terminal-taken"].contains(mode) {
    return Json::object(Map([("terminals", Json::array([])), ("outdated", Json::boolean(false)), ("open", Json::boolean(false)), ("known", Json::boolean(false))]))
  }
  let some = station == "ws1/st1"
  let item = fn(id : String, by : String, cwd : String, typing : String, looking : Array[String]) -> Json {
    let o : Map[String, Json] = Map([
      ("id", Json::string(id)),
      ("by", Json::string(by)),
      ("at", Json::number(1794650000000.0)),
      ("cwd", Json::string(cwd)),
      ("looking", Json::array(looking.map(Json::string))),
    ])
    if typing != "" {
      o["typing"] = Json::string(typing)
    }
    Json::object(o)
  }
  let terminals : Array[Json] = if some {
    [
      item("term-1", "左子健", "~/still.fail/station", "左子健", ["彭晓"]),
      item("term-2", "左子健", "~/still.fail", "", []),
      item("term-3", "彭晓", "~", "", []),
    ]
  } else {
    []
  }
  Json::object(Map([("terminals", Json::array(terminals)), ("outdated", Json::boolean(false)), ("open", Json::boolean(true)), ("known", Json::boolean(true))]))
}

///|
/// A terminal's screen as the station gives it: vim on the station's main file (its lines as narrow as a phone's
/// window holds).
let fixture_terminal_screen : String = "\u{1b}[2J\u{1b}[H  1 import { Effect } from \"effect\";\r\n  2 import { makeMesh } from \"./mesh.ts\";\r\n  3 import { terminals } from \"./terms.ts\";\r\n  4\r\n  5 const main = Effect.gen(function* () {\r\n  6   const mesh = yield* makeMesh;\r\n  7   yield* terminals(mesh);\r\n  8 });\r\n~\r\n~\r\n NORMAL  src/main.ts          7,3   All"

///|
/// `terminal.view`: who types (the view itself, unless it asked to look, or `term-1`'s someone else), then the screen.
fn fixture_terminal_view(params : Json, on_value : (Json, Bytes?) -> Unit) -> Int {
  let p = Some(params)
  let id = match text(p, "terminal") { "new" => "term-9"; t => t }
  let others = id == "term-1"
  let types = !others && params is Object(o) && o.get("control") is Some(True)
  let state : Map[String, Json] = Map([
    ("phase", Json::string("live")),
    ("id", Json::string(id)),
    ("types", Json::boolean(types)),
    ("looking", Json::array(if others { [Json::string("彭晓")] } else { [] })),
    ("cols", Json::number(80.0)),
    ("rows", Json::number(24.0)),
    ("cwd", Json::string("~/still.fail/station")),
  ])
  state["typing"] = if others { Json::string("左子健") } else if types { Json::string("Ann") } else { Json::null() }
  on_value(Json::object(Map([("state", Json::object(state))])), None)
  on_value(Json::object(Map([("screen", Json::boolean(true))])), Some(@utf8.encode(fixture_terminal_screen)))
  fix_stream_ids.val += 1
  fix_stream_ids.val
}
