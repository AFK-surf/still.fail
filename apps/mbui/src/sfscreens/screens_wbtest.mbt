// still.fail's screens as sffix shows them for its screenshots (scripts/shots.sh: MBUI_FIXTURE=MODE MBUI_SCRIPT=shot in
// a phone's window), drawn by a Tester instead of a window: over the Mac host's text as it recorded it for the screen
// (screens/text-mac.textrec, scripts/screens.sh rec), the app opened as sffix opens it (@sfapp.fixture_app), drawn when
// the Mac drew its frames (their times kept with its text), to the one its picture is of, which comes no sooner than
// what the screen declares it opens with ends; idle then, its corners by the rule (screen_check). What it draws is
// not compared with mbui's own drawing of it (a reference kept, the Mac's frame): what it is checked against is
// Android's still.fail, the original.

///|
/// The clock 16 ms before the host's first frame: a stable run's frames are on a clock of their own from 0
/// (mbui's mac_app.m), the Tester's first 16 ms after its `time`.
let host_start : Double = -16.0

///|
/// The screenshots' window (scripts/shots.sh: MBUI_WIN=390x844), at the scale the Mac recorded its text in (Mini1's
/// display, 1 pixel a point; the goldens' 390 × 844).
let window_w : Double = 390.0

///|
let window_h : Double = 844.0

///|
let host_scale : Double = 1.0

///|
/// What a screen shown as it is from the first frame opens with: nothing (drawn at its start).
let nothing_opens : Double = 0.0

///|
/// `mode`'s section of the Mac's text (screens/text-mac.textrec, embedded as text_mac_kept: moon.pkg's pre-build):
/// its TEXTREC lines (Tester::new's `text`) and the hash of the last frame sffix drew (its picture's).
fn text_mac(mode : String) -> (String, String)? {
  let head = "# " + mode + " "
  let lines = []
  let mut hash = ""
  let mut inside = false
  for v in text_mac_kept.split("\n") {
    if v.has_prefix("# ") {
      inside = v.has_prefix(head)
      if inside {
        // # MODE FRAME TIME WIDTH HEIGHT SCALE HASH STABLE
        hash = v.split(" ").map(fn(p) { p.to_owned() }).to_array().get(7).unwrap_or("")
      }
    } else if inside {
      lines.push(v.to_owned())
    }
  }
  if lines.length() == 0 {
    None
  } else {
    Some((lines.join("\n"), hash))
  }
}

///|
/// The times of the frames the Mac drew for a screen (its section's DRAWHASH lines), oldest first.
fn mac_frame_times(section : String) -> Array[Double] {
  let out = []
  for v in section.split("\n") {
    guard v.has_prefix("DRAWHASH ") else { continue }
    let parts = v.split(" ").map(fn(p) { p.to_owned() }).to_array()
    match (try Some(@json.parse(parts.get(2).unwrap_or(""))) catch { _ => None }) {
      Some(Number(d, ..)) => out.push(d)
      _ => ()
    }
  }
  out
}

///|
/// `mode` as sffix opens it, in a Tester over the Mac's text for it, drawn when the Mac drew (to its picture's frame,
/// no sooner than `opening`: the declared length of what the screen opens with), then idle. Fails if the Mac's text
/// lacks what it asked of it.
fn screen(mode : String, opening : Double) -> @ui.Tester raise {
  let text = match text_mac(mode) {
    Some((text, _)) => text
    None => fail("\{mode}: no text of the Mac's recorded (scripts/screens.sh rec \{mode})")
  }
  // (the app made as sffix makes it at its first frame, the Tester's fake host in place: what it hands over then, a
  // made-up file's picture, is the Tester's to keep, not dropped as the Tester begins)
  let src : Ref[@sfapp.Source?] = Ref::new(None)
  let t = @ui.Tester::new(
    fn(c) {
      let s = match src.val {
        Some(s) => s
        None => {
          let s = @sfapp.fixture_app(mode)
          src.val = Some(s)
          s
        }
      }
      @sfapp.view(c, s)
    },
    w=window_w,
    h=window_h,
    text~,
    // (what its host said of its views before its first frame, said before the Tester's: Tester::new's `run`)
    run=text,
    scale=host_scale,
    time=host_start,
    stable=true,
  )
  // drawn when the Mac drew (its section's DRAWHASH times): what turns while shown (a spinner, Ctx::cycle) turns
  // through the frames the Mac's did, to the one its picture is of; what its host said of its views (a player's
  // state, a video's frames: VIEWSAID) said again where it said it
  let times = mac_frame_times(text)
  let last = times.last().unwrap_or(0.0)
  if last < opening {
    fail("\{mode}: the Mac took its picture at \{last} ms, before what it opens with ends (\{opening} ms)")
  }
  let mut framed = false
  for v in text.split("\n") {
    if v.has_prefix("VIEWSAID ") {
      if framed {
        ignore(t.view_said(v.view(start_offset=9).to_owned()))
      }
      continue
    }
    guard v.has_prefix("DRAWHASH ") else { continue }
    // (its first frame the Tester's own, drawn as it was made; each after it one of the Mac's, at its time)
    if !framed {
      framed = true
      continue
    }
    let at = match (try Some(@json.parse(v.split(" ").to_array().get(2).map(fn(p) { p.to_owned() }).unwrap_or(""))) catch { _ => None }) {
      Some(Number(d, ..)) => d
      _ => continue
    }
    t.frame_at(at)
  }
  // (compared at the Mac's last frame, nothing drawn after it: that nothing goes on asking for frames is checked once
  // it is compared, screen_check)
  let missing = t.text_missing()
  if missing.length() > 0 {
    fail(
      "\{mode}: the Mac's text lacks \{missing.length()} (on Mini1: bash apps/mbui/scripts/screens.sh rec \{mode}): " +
      missing[:5].to_array().join(", "),
    )
  }
  t
}

///|
/// `t`'s screen checked: its corners by the rule (as many breaking it as corners_known says, the bar only falling),
/// then idle.
fn screen_check(t : @ui.Tester, mode : String) -> Unit raise {
  let faults = t.corner_faults()
  let known = corners_known.get(mode).unwrap_or(0)
  if faults.length() != known {
    let line = if faults.length() == 0 {
      "its line taken out"
    } else {
      "its line made \"\{mode}\": \{faults.length()},"
    }
    fail(
      "\{mode}: \{faults.length()} corners break the rule, \{known} known: " +
      (if faults.length() < known {
        "fewer, the bar comes down: src/sfscreens/corners_known_wbtest.mbt, \{line}"
      } else {
        "more than its bar (src/sfscreens/corners_known_wbtest.mbt): fix them, the bar only falls"
      }) +
      "\n" +
      faults.join("\n"),
    )
  }
  t.assert_idle()
}

///|
/// `mode`'s screen (`screen`) checked (`screen_check`).
fn check(mode : String, opening : Double) -> Unit raise {
  screen_check(screen(mode, opening), mode)
}

// The settings' pages (shots.sh's SETTINGS_PAGES): pushed over Home before the first frame, settings and the page
// together (@sfapp.open_setting), each push nav_push_ms.

///|
test "settings-home" {
  check("settings-home", @ui.nav_push_ms)
}

///|
test "settings-home-dark" {
  check("settings-home-dark", @ui.nav_push_ms)
}

///|
test "settings-appearance" {
  check("settings-appearance", @ui.nav_push_ms)
}

///|
test "settings-me" {
  check("settings-me", @ui.nav_push_ms)
}

///|
test "settings-workspace" {
  check("settings-workspace", @ui.nav_push_ms)
}

///|
test "settings-security" {
  check("settings-security", @ui.nav_push_ms)
}

///|
test "settings-vault" {
  check("settings-vault", @ui.nav_push_ms)
}

///|
test "settings-stations" {
  check("settings-stations", @ui.nav_push_ms)
}

///|
test "settings-station" {
  check("settings-station", @ui.nav_push_ms)
}

///|
test "settings-profiles" {
  check("settings-profiles", @ui.nav_push_ms)
}

///|
test "settings-profile" {
  check("settings-profile", @ui.nav_push_ms)
}

///|
test "settings-connects" {
  check("settings-connects", @ui.nav_push_ms)
}

///|
test "settings-memory" {
  check("settings-memory", @ui.nav_push_ms)
}

///|
test "settings-memory-doc" {
  check("settings-memory-doc", @ui.nav_push_ms)
}

///|
test "settings-usage" {
  check("settings-usage", @ui.nav_push_ms)
}

///|
test "settings-archive" {
  check("settings-archive", @ui.nav_push_ms)
}

// Home over the made-up chats, nothing pushed (shots.sh home, its sheet; decide's home-jobs; notify's)

///|
test "home" {
  check("home", nothing_opens)
}

///|
test "landing" {
  check("landing", @ui.nav_push_ms)
}

///|
test "landing-invited" {
  check("landing-invited", @ui.nav_push_ms)
}

///|
test "blocked" {
  check("blocked", @ui.nav_push_ms)
}

///|
test "home-sheet" {
  check("home-sheet", nothing_opens)
}

///|
test "home-jobs" {
  check("home-jobs", nothing_opens)
}

///|
test "settings-notify-off" {
  check("settings-notify-off", @ui.nav_push_ms)
}

// The first row's chat pushed over Home (shots.sh chat, composer, cards; notify's flash)

///|
test "chat" {
  check("chat", @ui.nav_push_ms)
}

///|
test "chat-loading" {
  check("chat-loading", @ui.nav_push_ms)
}

///|
test "chat-compose" {
  check("chat-compose", @ui.nav_push_ms)
}

///|
test "chat-attach" {
  check(
    "chat-attach",
    @ui.nav_push_ms,
  )
}

///|
test "chat-quote" {
  check("chat-quote", @ui.nav_push_ms)
}

///|
test "chat-sending" {
  check(
    "chat-sending",
    @ui.nav_push_ms,
  )
}

///|
test "chat-failed" {
  check("chat-failed", @ui.nav_push_ms)
}

///|
test "chat-cards" {
  check("chat-cards", @ui.nav_push_ms)
}

///|
test "chat-answering" {
  check("chat-answering", @ui.nav_push_ms)
}

///|
test "chat-md" {
  check("chat-md", @ui.nav_push_ms)
}

///|
test "chat-pick" {
  check(
    "chat-pick",
    @ui.nav_push_ms,
  )
}

///|
test "chat-link-menu" {
  check("chat-link-menu", @ui.nav_push_ms)
}

///|
test "chat-update" {
  check("chat-update", @ui.nav_push_ms)
}

///|
test "chat-flash" {
  check(
    "chat-flash",
    @ui.nav_push_ms,
  )
}

///|
test "chat-flash-mine" {
  check("chat-flash-mine", @ui.nav_push_ms)
}

// The drive's pages pushed over Home (shots.sh DRIVE_MODES)

///|
test "files" {
  check("files", @ui.nav_push_ms)
}

///|
test "drive" {
  check("drive", @ui.nav_push_ms)
}

///|
test "drive-sub" {
  check("drive-sub", @ui.nav_push_ms)
}

///|
test "drive-chosen" {
  check("drive-chosen", @ui.nav_push_ms)
}

///|
test "drive-entry" {
  check("drive-entry", @ui.nav_push_ms)
}

///|
test "drive-upload" {
  check("drive-upload", @ui.nav_push_ms)
}

///|
test "drive-download" {
  check("drive-download", @ui.nav_push_ms)
}

///|
test "drive-empty" {
  check("drive-empty", @ui.nav_push_ms)
}

///|
test "reader" {
  check("reader", @ui.nav_push_ms)
}

///|
test "reader-bars" {
  check("reader-bars", @ui.nav_push_ms)
}

///|
test "reader-contents" {
  check("reader-contents", @ui.nav_push_ms)
}

///|
test "reader-layout" {
  check("reader-layout", @ui.nav_push_ms)
}

///|
test "reader-md" {
  check("reader-md", @ui.nav_push_ms)
}

///|
test "chat-station-files" {
  check("chat-station-files", @ui.nav_push_ms)
}

///|
test "chat-station-ref" {
  check("chat-station-ref", @ui.nav_push_ms)
}

///|
test "chat-station-file" {
  check("chat-station-file", @ui.nav_push_ms)
}

///|
test "chat-station-sheet" {
  check("chat-station-sheet", @ui.nav_push_ms)
}

// The 奏 page, a chat's history; a chat's sheets over the chat pushed (shots.sh DECIDE)

///|
test "decisions" {
  check("decisions", @ui.nav_push_ms)
}

///|
test "decisions-text" {
  check("decisions-text", @ui.nav_push_ms)
}

///|
test "decisions-idle" {
  check("decisions-idle", @ui.nav_push_ms)
}

///|
test "history" {
  check("history", @ui.nav_push_ms)
}

///|
test "history-details" {
  check("history-details", @ui.nav_push_ms)
}

///|
test "chat-info" {
  check("chat-info", @ui.nav_push_ms)
}

///|
test "chat-publish" {
  check("chat-publish", @ui.nav_push_ms)
}

///|
test "chat-agent" {
  check("chat-agent", @ui.nav_push_ms)
}

///|
test "chat-peek" {
  check("chat-peek", @ui.nav_push_ms)
}

///|
test "chat-jobs" {
  check("chat-jobs", @ui.nav_push_ms)
}

///|
test "chat-job" {
  check("chat-job", @ui.nav_push_ms)
}

// A new chat risen over Home, its sheets; the bar's panel; a place (shots.sh newchat)

///|
test "newchat" {
  check("newchat", @ui.nav_rise_ms)
}

///|
test "newchat-station" {
  check("newchat-station", @ui.nav_rise_ms)
}

///|
test "newchat-model" {
  check("newchat-model", @ui.nav_rise_ms)
}

///|
test "home-bars" {
  check("home-bars", nothing_opens)
}

///|
test "place" {
  check("place", nothing_opens)
}

// A chat's file in the preview (shots.sh preview)

///|
test "chat-preview-image" {
  check("chat-preview-image", @ui.nav_push_ms)
}

///|
test "chat-preview-pdf" {
  check(
    "chat-preview-pdf",
    @ui.nav_push_ms,
  )
}

///|
test "chat-preview-video" {
  check("chat-preview-video", @ui.nav_push_ms)
}

///|
test "chat-preview-audio" {
  check("chat-preview-audio", @ui.nav_push_ms)
}

///|
test "chat-preview-html" {
  check("chat-preview-html", @ui.nav_push_ms)
}

///|
test "chat-preview-code" {
  check("chat-preview-code", @ui.nav_push_ms)
}

///|
test "chat-preview-md" {
  check("chat-preview-md", @ui.nav_push_ms)
}

///|
test "chat-preview-csv" {
  check("chat-preview-csv", @ui.nav_push_ms)
}

///|
test "chat-preview-none" {
  check("chat-preview-none", @ui.nav_push_ms)
}

///|
test "chat-preview-step" {
  check("chat-preview-step", @ui.nav_push_ms)
}

///|
test "chat-preview-swipe" {
  check("chat-preview-swipe", @ui.nav_push_ms)
}

// The player, a web service's page, what another app shares in (shots.sh player, service, share)

///|
test "player-video" {
  check("player-video", @ui.nav_push_ms)
}

///|
test "player-audio" {
  check(
    "player-audio",
    @ui.nav_push_ms,
  )
}

///|
test "player-ended" {
  check("player-ended", @ui.nav_push_ms)
}

///|
test "player-opening" {
  check("player-opening", @ui.nav_push_ms)
}

///|
test "service" {
  check("service", @ui.nav_push_ms)
}

///|
test "service-sized" {
  check("service-sized", @ui.nav_push_ms)
}

///|
test "service-restart" {
  check("service-restart", @ui.nav_push_ms)
}

///|
test "service-stopped" {
  check("service-stopped", @ui.nav_push_ms)
}

///|
test "share-in" {
  check("share-in", nothing_opens)
}

///|
test "share-in-stations" {
  check("share-in-stations", nothing_opens)
}

///|
test "share-in-files" {
  check(
    "share-in-files",
    nothing_opens,
  )
}
