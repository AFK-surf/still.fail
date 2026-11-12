// What the app asks the core of the stations (the user, 2026-11-10: 「ui 应该只订阅目前 ui 需要或者可能需要的东西」): a
// list their rows, once whoever reads them; a station's page that station alone; a page that shows one part of every
// station each station's part, never every station whole. Over a made-up core of three stations, each with a profile
// and its archiving, answered as the core answers (the settings' fixture_stations.mbt), what the client sent it.

///|
/// Station `n` (1 to 3) whole, as a made-up core describes it: its profile, how it archives, the models it runs, the
/// second's machine signed in with an account offered as a profile.
fn asked_whole(n : Int) -> Json {
  let name = ["Willow", "Maple", "Birch"][n - 1]
  {
    "station": Json::string("ws1/st\{n}"),
    "id": Json::string("st\{n}"),
    "name": Json::string(name),
    "summary": "空闲",
    "online": true,
    "host": { "identity": "Apple M1 Pro", "meters": [], "details": [{ "label": "主机名", "value": Json::string(name) }] },
    "models": [{ "model": "claude-opus-5-5", "name": "Opus 5.5", "runtimes": ["claude"] }],
    "runtimes": [{ "runtime": "claude", "models": ["claude-opus-5-5"] }],
    "profileGroups": [{ "group": "claude", "title": "Claude 订阅", "profiles": [Json::string("p\{n}")] }],
    "overview": {
      "counts": { "running": 0 },
      "profiles": [{ "id": Json::string("p\{n}"), "name": Json::string("账号 \{n}"), "group": "claude", "groupTitle": "Claude 订阅" }],
      "archiving": { "mode": "idle", "canEdit": true, "lineText": Json::string("空闲就归档 · \{n} 天") },
      // (Maple's machine signed in to Codex with an account no profile uses: offered)
      "machineLogins": if n == 2 {
        [
          {
            "runtime": "codex",
            "installed": true,
            "loggedIn": true,
            "email": "maple@example.com",
            "plan": "plus",
            "planText": "Plus",
            "usable": true,
            "text": "",
            "offered": true,
          },
        ]
      } else {
        []
      },
      "slackApps": [],
    },
  }
}

///|
/// `base` whose workspace ws1 has the three stations of asked_whole, every topic of them answered from them.
fn three_stations(base : Source) -> Source {
  let wholes = Some(Json::array([asked_whole(1), asked_whole(2), asked_whole(3)]))
  {
    ..base,
    topic_read: fn(name, params) {
      let p = Some(Json::object(params))
      match name {
        "stations" =>
          {
            value: match wholes {
              Some(Array(a)) => Some(Json::array(a.map(@settings.station_row)))
              v => v
            },
            error: None,
            version: 1,
          }
        "station" => { value: @settings.station_said(wholes, text(p, "station"), ""), error: None, version: 1 }
        "stationPart" => { value: @settings.station_said(wholes, text(p, "station"), text(p, "part")), error: None, version: 1 }
        // (the profiles' list with the machine logins each station offers, as the core works them out, a row each; one
        // account whole of them)
        "profiles" => {
          let r = base.topic(name, params).get().snapshot()
          { ..r, value: @settings.profiles_rows(@settings.profiles_of_stations(r.value, wholes)) }
        }
        "profile" => {
          let r = base.topic("profiles", { "scope": params.get("scope").unwrap_or(Json::string("")) }).get().snapshot()
          { ..r, value: @settings.profile_said(r.value, params) }
        }
        _ => base.topic(name, params).get().snapshot()
      }
    },
  }
}

///|
/// A phone signed in over the three stations' core answering `ms` late, at rest on Home: every subscription the client
/// sent said in `said` as `<topic> <params>`, its params whole.
fn asked_phone(said : Array[String]) -> @ui.Tester {
  new_run()
  let heard = fn(h : String) {
    guard h.has_prefix("out ") else { return }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => return }
    guard j is Object(m) && m.get("subscribe") is Some(Object(sub)) && sub.get("topic") is Some(String(topic)) else {
      return
    }
    let rest = sub.to_array().filter(fn(kv) { kv.0 != "topic" })
    said.push(topic + " " + Json::object(Map::from_array(rest)).stringify())
  }
  let src = { ..round_trip_again(three_stations(fixture("home")), place_core_soon_ms, heard~), reads_ahead: fn() { true } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  t.draw()
  t.run_for(place_core_soon_ms * 8.0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Of what was said, the subscriptions of topic `topic`.
fn asked_of(said : Array[String], topic : String) -> Array[String] {
  said.filter(fn(s) { s.has_prefix(topic + " ") })
}

///|
test "Home with the bar (小屏) at rest: the stations' rows subscribed once, no station's page nor part" {
  let said : Array[String] = []
  let _ = asked_phone(said)
  assert_eq(asked_of(said, "stations"), ["stations {\"scope\":\"ws1\"}"])
  assert_eq(asked_of(said, "station"), [])
  assert_eq(asked_of(said, "stationPart"), [])
}

///|
test "a station's page open: that station alone subscribed, no other's, no part" {
  let said : Array[String] = []
  let t = asked_phone(said)
  let before = said.length()
  @sfbase.open_page(Setting(@settings.Route::Station("ws1/st2")))
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  let now = said[before:].to_owned()
  assert_eq(asked_of(now, "station"), ["station {\"scope\":\"ws1\",\"station\":\"ws1/st2\"}"])
  assert_eq(asked_of(now, "stationPart"), [])
  assert_true(t.find("Maple") is Some(_), msg="its page shows it")
}

///|
test "权限's archiving open: each station's archiving subscribed by its own row, no station whole" {
  let said : Array[String] = []
  let t = asked_phone(said)
  let before = said.length()
  @sfbase.open_page(Setting(@settings.Route::Archiving))
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  let now = said[before:].to_owned()
  let parts = asked_of(now, "stationPart")
  parts.sort()
  assert_eq(parts, [1, 2, 3].map(fn(n) { "stationPart {\"scope\":\"ws1\",\"station\":\"ws1/st\{n}\",\"part\":\"archiving\"}" }))
  assert_eq(asked_of(now, "station"), [])
  assert_true(t.find("空闲就归档 · 3 天") is Some(_), msg="each row shows its own part")
}

///|
test "the Profile place (小屏): the machine logins offered shown on its first frame, from the profiles' list, no station's part asked" {
  let said : Array[String] = []
  let t = asked_phone(said)
  go_place(t.ctx().moment(), "profiles", [], -1)
  t.draw()
  assert_true(t.find("已在 Maple 上登录") is Some(_), msg="the offer on the place's first frame")
  t.run_for(@ui.move_most_ms)
  t.run_for(place_core_soon_ms * 4.0)
  assert_true(t.find("maple@example.com") is Some(_), msg="the offered login")
  assert_eq(asked_of(said, "stationPart"), [])
}
