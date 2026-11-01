// A station's screen over the fixture (APP=sffix MBUI_FIXTURE=screen-…; ember apps/android ScreenViewerTest's shots,
// the same states said the same way): the screen's view opened over the chats, its states and frames (a JPEG of a
// browser's tab: screen_fixture_frame.mbt) as the core would say them, each mode one of the Android test's pictures.
//
//   screen-audio                        live with system audio available (no sound emitted by the fixture)
//   screen-connecting                   nothing said yet
//   screen-live, -live-dark             live, driven, 李雷 also on it (the landscape one: the same, its window sideways)
//   screen-trackpad, -trackpad-command  driven as a trackpad, the pointer moved right; ⌘ held on the keys row
//   screen-full, -full-tools            全屏; its tools opened
//   screen-agent-driving, -dark         an agent drives it, this view only looks (接管)
//   screen-agent-paused                 taken over: the agent waits
//   screen-read-only                    a member who may only look
//   screen-not-drivable                 控制 chosen, the station lacking the grant to take input
//   screen-reconnecting                 the frame kept, its why said over it
//   screen-ended, -dark                 ended by the station, after a frame
//   screen-outdated, -gone, -denied     over, said in the screen's place (denied: the grant it lacks too)
//   screen-gone-said-once, -gone-dark   gone, the core saying the headline's words
//   screen-failed                       the call itself failed
//   screen-clipboard-driving            driving a station that carries the clipboard both ways and takes files
//   screen-clipboard-old-station        driving a station from before the clipboard and files
//   screen-files-going, -done (-dark)   two files sent to its machine: going (the first under a free name), then there
//   screen-center, -stats (-dark)       driving a Windows desktop that changes its scale: 控制中心 open; the view's
//                                       figures open
//   screen-login-fill, -pick (-dark)    driving a tab whose focus is in github.com's password field: 用 1Password
//                                       填入 offered; pressed, its two logins there to pick from

///|
/// The fixture's screen mode ("" none), its dark taken off.
let screen_fix_mode : Ref[String] = Ref("")

///|
/// What the fixture's core says of its screen's view to, as it streams it (screen_fixture_stream): none before.
let screen_fix_heard : Ref[((Json, Bytes?) -> Unit)?] = Ref(None)

///|
/// The fixture's live screen said again with `others` also on it (its state alone changed, as the core says a change of
/// it): nothing where nothing streams.
pub fn screen_fix_others(others : Array[String]) -> Unit {
  match screen_fix_heard.val {
    Some(said) =>
      said({ "state": screen_fix_state("live", true, true, others, "", None, None, None, None, None, None) }, None)
    None => ()
  }
}

///|
/// The fixture's screen, as Android's test has it.
// kept across runs: a value (no field of it changes)
let screen_fix_at : ScreenAt = { station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome", until_gone: false }

///|
/// MBUI_FIXTURE=screen-…: the screen's viewer over the chats.
pub fn open_screen_fixture(mode : String) -> Unit {
  if !mode.has_prefix("screen-") {
    return
  }
  let m = if mode.has_suffix("-dark") {
    mode.view(end_offset=mode.length() - 5).to_owned()
  } else {
    mode
  }
  screen_fix_mode.val = m
  app.nav.push(Screen(screen_fix_at))
  // what the person did there before the picture (ScreenViewerTest's taps)
  let u = screen_ui(screen_key(screen_fix_at.station, screen_fix_at.screen))
  match m {
    "screen-trackpad" | "screen-trackpad-command" => {
      // a finger moved right, slowly (ScreenViewerTest: the pointer near 0.66 of the frame)
      u.pad.x = 0.66
      if m == "screen-trackpad-command" {
        u.held.mods = mod_meta
      }
    }
    "screen-full" => u.full = true
    "screen-full-tools" => {
      u.full = true
      u.tools_open = true
    }
    "screen-center" => u.asked_panel = "center"
    "screen-stats" => u.asked_panel = "net"
    _ => ()
  }
}

///|
/// What the fixture's core says of `screen.view` for the mode: its state, its config and a frame; for an ended mode its
/// answer after.
pub fn screen_fixture_stream(
  params : Json,
  on_value : (Json, Bytes?) -> Unit,
  done : (Result[Json, Json]) -> Unit,
) -> Int {
  ignore(params)
  screen_fix_heard.val = Some(on_value)
  let m = screen_fix_mode.val
  let agent = "Agent「修登录」"
  let drop : Json = { "folder": "/Users/alice/Downloads", "reveal": true }
  let live = fn(
    control : Bool,
    may : Bool,
    others : Array[String],
    controllers : Array[String]?,
    take_over : Bool?,
    line : String?,
    access : Json?,
    clipboard : Array[String]?,
    drop : Json?,
  ) {
    on_value(
      {
        "state": screen_fix_state(
          "live", control, may, others, "", controllers, take_over, line, access, clipboard, drop,
        ),
      },
      None,
    )
    on_value({ "config": { "codec": "jpeg", "width": 1280.0, "height": 720.0 } }, None)
    on_value({ "frame": { "key": true, "ts": 1000.0 } }, Some(screen_fix_jpeg()))
  }
  let over = fn(phase : String, message : String, access : Json?) {
    on_value(
      {
        "state": screen_fix_state(
          phase, true, true, [], message, None, None, None, access, None, None,
        ),
      },
      None,
    )
    done(Ok(Json::null()))
  }
  match m {
    "screen-audio" => {
      live(true, true, [], None, None, None, None, None, None)
      on_value({ "audioConfig": { "codec": "pcm_s16le", "sampleRate": 48000, "channels": 2 } }, None)
    }
    "screen-connecting" => ()
    "screen-live" | "screen-full" | "screen-full-tools" =>
      live(true, true, if m == "screen-live" { ["李雷"] } else { [] }, None, None, None, None, None, None)
    "screen-trackpad" | "screen-trackpad-command" =>
      live(true, true, [], None, None, None, None, None, None)
    "screen-agent-driving" =>
      live(
        false,
        true,
        [agent, "Bob"],
        Some([agent]),
        Some(true),
        Some("只看 · \{agent} 正在控制 · Bob 也在查看"),
        None,
        None,
        None,
      )
    "screen-agent-paused" =>
      live(
        true,
        true,
        [agent, "Bob"],
        Some([]),
        Some(false),
        Some("控制 · \{agent} 已暂停 · Bob 也在查看"),
        None,
        None,
        None,
      )
    "screen-read-only" => live(false, false, ["李雷"], None, None, None, None, None, None)
    "screen-not-drivable" =>
      live(
        false,
        true,
        [],
        None,
        None,
        None,
        Some({
          "capture": true,
          "control": false,
          "message": "在 辅助功能 里打开 stillfail-station",
          "app": "stillfail-station",
        }),
        None,
        None,
      )
    "screen-reconnecting" => {
      live(true, true, ["李雷"], None, None, None, None, None, None)
      on_value(
        {
          "state": screen_fix_state(
            "reconnecting",
            true,
            true,
            ["李雷"],
            "和 station 的连接断了，正在重新连接…",
            None,
            None,
            None,
            None,
            None,
            None,
          ),
        },
        None,
      )
    }
    "screen-ended" => {
      live(true, true, ["李雷"], None, None, None, None, None, None)
      over("ended", "agent 关掉了这个标签页", None)
    }
    "screen-outdated" => over("outdated", "这台 station 的版本还不能共享屏幕，更新后再试", None)
    "screen-gone" => over("gone", "这个标签页已经关了", None)
    "screen-denied" =>
      over(
        "denied",
        "station 现在录不了屏",
        Some({
          "capture": false,
          "control": false,
          "message": "在 系统设置 › 隐私与安全性 › 屏幕录制 里打开 stillfail-station",
          "app": "stillfail-station",
        }),
      )
    "screen-gone-said-once" => over("gone", "此屏幕已不存在", None)
    "screen-failed" => done(Err({ "code": "offline", "message": "station 不在线" }))
    "screen-clipboard-driving" =>
      live(true, true, [], None, None, None, None, Some(["text", "png"]), Some(drop))
    "screen-clipboard-old-station" => live(true, true, [], None, None, None, None, None, None)
    "screen-center" | "screen-stats" => {
      live(true, true, [], None, None, None, None, Some(["text", "png"]), Some(drop))
      let st = match screen_fix_state("live", true, true, [], "", None, None, None, None, Some(["text", "png"]), Some(drop)) {
        Object(m) => m.copy()
        _ => {}
      }
      st["title"] = Json::string("Windows 桌面")
      st["kind"] = Json::string("desktop")
      st["codec"] = Json::string("h264")
      st["width"] = Json::number(1920.0)
      st["height"] = Json::number(1080.0)
      st["scale"] = { "percent": 125.0, "recommended": 150.0, "steps": [100.0, 125.0, 150.0, 175.0] }
      st["latency"] = { "frame": 46.0, "before": 11.0 }
      st["video"] = { "capture": "Windows.Graphics.Capture", "encoder": "NVENC", "hardware": true }
      on_value({ "state": Json::object(st) }, None)
    }
    "screen-login-fill" | "screen-login-pick" => {
      live(true, true, [], None, None, None, None, Some(["text", "png"]), Some(drop))
      let st = match screen_fix_state("live", true, true, [], "", None, None, None, None, Some(["text", "png"]), Some(drop)) {
        Object(m) => m.copy()
        _ => {}
      }
      st["login"] = { "host": "github.com", "field": "password" }
      on_value({ "state": Json::object(st) }, None)
      screen_fix_one_password()
      if m == "screen-login-pick" {
        match screens_open.get(screen_key(screen_fix_at.station, screen_fix_at.screen)) {
          Some(s) => s.fill_start()
          None => ()
        }
      }
    }
    "screen-files-going" | "screen-files-done" => {
      live(true, true, [], None, None, None, None, Some(["text", "png"]), Some(drop))
      screen_fix_drops(m == "screen-files-done")
    }
    _ => ()
  }
  1
}

///|
/// A ScreenViewState as the fixture says it (ScreenViewerTest's `state`).
fn screen_fix_state(
  phase : String,
  control : Bool,
  may : Bool,
  others : Array[String],
  message : String,
  controllers : Array[String]?,
  take_over : Bool?,
  line : String?,
  access : Json?,
  clipboard : Array[String]?,
  drop : Json?,
) -> Json {
  let m : Map[String, Json] = {
    "phase": Json::string(phase),
    "title": Json::string("still.fail — Chrome"),
    "kind": Json::string("browser"),
    "control": Json::boolean(control),
    "may": Json::boolean(may),
    "others": Json::array(others.map(Json::string)),
    "line": Json::string(
      match line {
        Some(l) => l
        None =>
          (if control { "控制" } else { "只看" }) +
          (if others.is_empty() { "" } else { " · " + others.join("、") + "也在看" })
      },
    ),
    "codec": Json::string("jpeg"),
    "width": Json::number(1280.0),
    "height": Json::number(720.0),
  }
  if message != "" {
    m["message"] = Json::string(message)
  }
  match controllers {
    Some(cs) => m["controllers"] = Json::array(cs.map(Json::string))
    None => ()
  }
  match take_over {
    Some(b) => m["takeOver"] = Json::boolean(b)
    None => ()
  }
  match access {
    Some(a) => m["access"] = a
    None => ()
  }
  match clipboard {
    Some(cs) => m["clipboard"] = Json::array(cs.map(Json::string))
    None => ()
  }
  match drop {
    Some(d) => m["drop"] = d
    None => ()
  }
  Json::object(m)
}

///|
/// The two files ScreenViewerTest sends: 季度报告.pdf (1.2 MB, its name taken there: up as 季度报告 (1).pdf, a part of it
/// in) and notes.txt (waiting); or both there.
fn screen_fix_drops(done : Bool) -> Unit {
  let s = screen_sess_of(screen_fix_at.station, screen_fix_at.screen)
  guard s is Some(s) else { return }
  let report = Bytes::make(1_200_000, b'\x01')
  let notes = Bytes::make(4400, b'\x02')
  s.drops.push({
    serial: 1,
    folder: "/Users/alice/Downloads",
    reveal: true,
    bytes: report,
    name: @signals.signal("季度报告 (1).pdf"),
    tried: @sf.LiveArray::from(["季度报告.pdf"]),
    sent: @signals.signal(if done { report.length() } else { 256 * 1024 }),
    state: if done { @signals.signal("done") } else { @signals.signal("going") },
    error: "",
    id: @signals.signal(""),
  })
  s.drops.push({
    serial: 2,
    folder: "/Users/alice/Downloads",
    reveal: true,
    bytes: notes,
    name: @signals.signal("notes.txt"),
    tried: @sf.LiveArray::from([]),
    sent: if done { @signals.signal(notes.length()) } else { @signals.signal(0) },
    state: if done { @signals.signal("done") } else { @signals.signal("waiting") },
    error: "",
    id: @signals.signal(""),
  })
  s.drops_serial = 2
  // (going: the parts go no further, as the test holds its second part)
  s.pumping = !done
}

///|
/// The view of `screen` on `station`, if its page made it.
fn screen_sess_of(station : String, screen : String) -> ScreenSess? {
  screens_open.get(screen_key(station, screen))
}

///|
/// 1Password as the fixture and the tests have it (the Tester's `op`): two logins for github.com (one for gitlab.com), each one's account and password.
fn screen_fix_one_password() -> Unit {
  @ui.fake_op_runs.clear()
  @ui.fake_op.val = Some(fn(args) {
    if args.length() >= 2 && args[0] == "item" && args[1] == "list" {
      (
        0,
        "[{\"id\":\"gh1\",\"title\":\"GitHub\",\"additional_information\":\"zzj\",\"urls\":[{\"href\":\"https://github.com/login\"}]},{\"id\":\"gh2\",\"title\":\"GitHub 工作\",\"additional_information\":\"zzj-work\",\"urls\":[{\"href\":\"github.com\"}]},{\"id\":\"gl\",\"title\":\"GitLab\",\"urls\":[{\"href\":\"https://gitlab.com\"}]}]",
        "",
      )
    } else if args.length() >= 3 && args[0] == "item" && args[1] == "get" {
      let who = if args[2] == "gh1" { "zzj" } else { "zzj-work" }
      (0, "[{\"id\":\"username\",\"label\":\"username\",\"value\":\"\{who}\"},{\"id\":\"password\",\"label\":\"password\",\"purpose\":\"PASSWORD\",\"value\":\"pw-\{who}\"}]", "")
    } else {
      (1, "", "unknown command")
    }
  })
}

///|
/// This device's passkeys as the tests have them (the Tester's): github.com's signs (credential 09 09, its authenticator
/// data, signature and user handle); any other site's none (the person told no passkey of it here).
fn screen_fix_passkeys() -> Unit {
  @ui.fake_passkey_asks.clear()
  @ui.fake_passkey.val = Some(fn(rp, _client, _uv, _ids) {
    if rp == "github.com" {
      "0\u{1f}0909\u{1f}abcdef\u{1f}070707\u{1f}05\u{1f}\u{1f}"
    } else {
      "1\u{1f}\u{1f}\u{1f}\u{1f}\u{1f}NotAllowedError\u{1f}"
    }
  })
}
