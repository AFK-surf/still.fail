// The made-up workspace's stations that only run tasks (rigs: sfpages station_rig.mbt), as the core's `rigs` topic
// says them and as its `rig.*` calls change them: build-box, the viewer's own, reached, one chat using it and one
// asking; gpu-01, 陈's, open to every chat. settings-stations-tasks: the stations' list with them in it (-outside: on a
// device its person's trusted devices have not approved, where adding one says so; -theirs: Willow added by another
// member, not the viewer's to make one; place-stations-tasks: the stations' place on a
// wide frame, build-box picked); settings-station-tasks: build-box's page;
// -other: gpu-01's; -locked: the workspace in security mode, build-box's code not compared yet.

///|
/// What was changed here: build-box's 免批准, its grant taken back, its request answered, its code compared, and
/// whether the workspace's view lists it at all (taken out).
priv struct RigsFixture {
  mut open : Bool
  mut revoked : Bool
  mut answered : Bool
  mut vouched : Bool
  mut removed : Bool
  /// On a device its person's trusted devices have not approved: adding one is refused, saying so.
  mut outside : Bool
}

///|
let fx_rigs : RigsFixture = { open: false, revoked: false, answered: false, vouched: false, removed: false, outside: false }

///|
/// Whether the fixture's `mode` is one with the made-up rigs in it.
fn rigs_fixture_mode(mode : String) -> Bool {
  mode.has_prefix("settings-stations-tasks") || mode.has_prefix("settings-station-tasks") || mode == "place-stations-tasks"
}

///|
/// As a run starts.
fn rigs_fixture_reset() -> Unit {
  fx_rigs.open = false
  fx_rigs.revoked = false
  fx_rigs.answered = false
  fx_rigs.vouched = false
  fx_rigs.removed = false
  fx_rigs.outside = false
}

///|
/// The made-up rigs as the workspace's view lists them (the settings' row counts them), by the fixture's mode.
fn rigs_fixture_listed(mode : String) -> Json {
  fx_rigs.outside = mode == "settings-stations-tasks-outside"
  if !rigs_fixture_mode(mode) {
    return []
  }
  let out : Array[Json] = []
  if !fx_rigs.removed {
    out.push(obj([("id", str("aa11")), ("name", str("build-box")), ("owner", str("u1"))]))
  }
  out.push(obj([("id", str("bb22")), ("name", str("gpu-01")), ("owner", str("u4"))]))
  Json::array(out)
}

///|
/// The `rigs` topic of the made-up workspace, by the fixture's mode.
fn rigs_fixture_topic(mode : String) -> Json {
  let locked = mode == "settings-station-tasks-locked"
  let rigs : Array[Json] = []
  if true {
    if !fx_rigs.removed {
      let vouched = !locked || fx_rigs.vouched
      rigs.push(
        obj([
          ("id", str("aa11")),
          ("name", str("build-box")),
          ("owner", str("u1")),
          ("ownerEmail", str("lin@example.com")),
          ("ownerName", str("林")),
          ("mine", Json::boolean(true)),
          ("code", str("K7Q-2MX")),
          ("vouched", Json::boolean(vouched)),
          ("reached", Json::boolean(true)),
          ("known", Json::boolean(vouched)),
          ("open", Json::boolean(fx_rigs.open)),
          (
            "grants",
            if fx_rigs.revoked || !vouched {
              []
            } else {
              [
                obj([
                  ("request", str("r-7")),
                  ("station", str("st1")),
                  ("stationName", str("Willow")),
                  ("session", str("s-c1")),
                  ("chat", str("CHAT/1")),
                  ("title", str("修 CI")),
                  ("by", str("zhou@example.com")),
                  ("timeoutKind", str("idle")),
                  ("timeoutSeconds", Json::number(3600.0)),
                  ("exp", Json::number(2.0e9)),
                  ("until", Json::number(1.9e9)),
                ]),
              ]
            },
          ),
          (
            "requests",
            if fx_rigs.answered || !vouched {
              []
            } else {
              [
                obj([
                  ("id", str("r-9")),
                  ("station", str("ws1/st2")),
                  ("session", str("s-c2")),
                  ("chat", str("CHAT/2")),
                  ("title", str("跑一遍发布前的测试")),
                  ("by", str("ana@example.com")),
                  ("reason", str("在 Linux 上跑完整的 station 测试")),
                  ("timeoutKind", str("fixed")),
                  ("timeoutSeconds", Json::number(28800.0)),
                  ("at", Json::number(1.0e9)),
                  ("status", str("pending")),
                ]),
              ]
            },
          ),
        ]),
      )
    }
    rigs.push(
      obj([
        ("id", str("bb22")),
        ("name", str("gpu-01")),
        ("owner", str("u4")),
        ("ownerEmail", str("chen@example.com")),
        ("ownerName", str("陈")),
        ("mine", Json::boolean(false)),
        ("code", str("P4D-9TR")),
        ("vouched", Json::boolean(true)),
        ("reached", Json::boolean(false)),
        ("known", Json::boolean(true)),
        ("open", Json::boolean(true)),
        ("grants", []),
        ("requests", []),
      ]),
    )
  }
  obj([
    ("locked", Json::boolean(locked)),
    ("app", Json::boolean(true)),
    ("personal", str(if mode == "settings-stations-tasks-outside" { "outside" } else { "member" })),
    ("rigs", Json::array(rigs)),
  ])
}

///|
/// A `rig.*` call answered, the made-up rigs changed as the core would say them next; None: not one of them.
fn rigs_fixture_call(name : String, p : Json?) -> Result[Json, Json]? {
  match name {
    "rig.add" if fx_rigs.outside => Some(Err(obj([("code", str("personal_outside")), ("message", str("此设备尚未获批：先在这台设备上发送批准请求，输入你的受信任设备上显示的安全码"))])))
    "rig.add" =>
      Some(
        Ok(
          obj([
            ("token", str("made-up")),
            ("install", str("curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b rig:9d2e6a41c07b")),
            ("installWindows", str("& ([scriptblock]::Create((irm https://still.fail/install.ps1))) 4f7c2a9e1b rig:9d2e6a41c07b")),
            ("command", str("stillfail station enroll https://still.fail 4f7c2a9e1b --rig 9d2e6a41c07b")),
          ]),
        ),
      )
    "rig.setOpen" => {
      fx_rigs.open = flag(p, "open")
      fx_changed()
      Some(Ok(obj([("delivered", Json::boolean(true))])))
    }
    "rig.revoke" if text(p, "request") == "r-7" => {
      fx_rigs.revoked = true
      fx_changed()
      Some(Ok(obj([])))
    }
    "rig.decide" if text(p, "request") == "r-9" => {
      fx_rigs.answered = true
      fx_changed()
      Some(Ok(obj([])))
    }
    "rig.vouch" =>
      if text(p, "code").to_upper() == "K7Q-2MX" {
        fx_rigs.vouched = true
        fx_changed()
        Some(Ok(obj([("vouched", Json::boolean(true))])))
      } else {
        Some(Err(obj([("code", str("rig_wrong_code")), ("message", str("安全码不对：和那台机器上显示的不一样"))])))
      }
    "rig.log" =>
      Some(
        Ok(
          obj([
            (
              "commands",
              [
                obj([("at", Json::number(2.0)), ("station", str("st1")), ("stationName", str("Willow")), ("session", str("s-c1")), ("key", str("k2")), ("name", str("test")), ("command", str("cd station && pnpm test")), ("kind", str("task"))]),
                obj([("at", Json::number(1.0)), ("station", str("st1")), ("stationName", str("Willow")), ("session", str("s-c1")), ("key", str("k1")), ("name", str("deploy")), ("command", str("./deploy.sh staging")), ("kind", str("secret"))]),
              ],
            ),
          ]),
        ),
      )
    // (made a whole station again: no rig any more; a whole one made a rig: answered, the lists as they were)
    "rig.setMode" if text(p, "station") == "aa11" && text(p, "mode") == "full" => {
      fx_rigs.removed = true
      fx_changed()
      Some(Ok(obj([])))
    }
    "rig.setMode" => Some(Ok(obj([])))
    // (asked as the cloud's calls are, with whose account: without it the core refuses)
    "workspace.removeStation" if text(p, "station") == "aa11" && text(p, "account") != "" => {
      fx_rigs.removed = true
      fx_changed()
      Some(Ok(obj([])))
    }
    _ => None
  }
}
