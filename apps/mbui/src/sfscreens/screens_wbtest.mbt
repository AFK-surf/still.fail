// still.fail's screens as sffix shows them for its screenshots (scripts/shots.sh: MBUI_FIXTURE=MODE MBUI_SCRIPT=shot in
// a phone's window), drawn by a Tester instead of a window: over the Mac host's text as it recorded it for the screen
// (screens/text-mac.textrec, scripts/screens.sh rec), the app opened as sffix opens it (@sfapp.fixture_app), drawn when
// the Mac drew its frames (their times kept with its text), to the one its picture is of, which comes no sooner than
// what the screen declares it opens with ends; idle then. What it drew is compared with the screen's reference
// (screen_check) and with the frame the Mac drew for its picture (its hash).

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
/// no sooner than `opening`: the declared length of what the screen opens with), then idle. Fails if the Mac's text lacks what it asked of it,
/// unless the screen is known to differ from the Mac's (`unlike_mac`: what the Tester's fake host answers otherwise).
fn screen(mode : String, opening : Double, unlike_mac? : String = "") -> @ui.Tester raise {
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
    scale=host_scale,
    time=host_start,
    stable=true,
  )
  // drawn when the Mac drew (its section's DRAWHASH times): what turns while shown (a spinner, Ctx::cycle) turns
  // through the frames the Mac's did, to the one its picture is of
  let times = mac_frame_times(text)
  let last = times.last().unwrap_or(0.0)
  if last < opening {
    fail("\{mode}: the Mac took its picture at \{last} ms, before what it opens with ends (\{opening} ms)")
  }
  for at in times {
    if at > t.time() {
      t.frame(ms=at - t.time())
    }
  }
  t.draw()
  t.assert_idle()
  let missing = t.text_missing()
  if missing.length() > 0 && unlike_mac == "" {
    fail(
      "\{mode}: the Mac's text lacks \{missing.length()} (on Mini1: bash apps/mbui/scripts/screens.sh rerecord \{mode}): " +
      missing[:5].to_array().join(", "),
    )
  }
  t
}

///|
/// What `t` drew compared with `mode`'s reference (src/sfscreens/__snapshot__/MODE.dl, its draw list: mbui's
/// drawlist.mbt, what a renderer draws offscreen; UPDATE=1 rewrites it), and
/// its frame with the Mac's: the last frame sffix drew for its picture, kept with its text (the same hash, or the
/// screen is not what the Mac shows: scripts/screens.sh rec MODE again on a Mac, if the app changed it), unless it is
/// known to differ (`unlike_mac`, said). The one place the comparison is made.
fn screen_check(it : @test.Test, t : @ui.Tester, mode : String, unlike_mac? : String = "") -> Unit raise {
  let hash = t.frame_hash().to_string()
  match text_mac(mode) {
    Some((_, h)) if h != hash && unlike_mac == "" =>
      fail(
        "\{mode}: the Mac drew \{h}, the Tester \{hash}: a change to what it draws is recorded in its PR, on Mini1 " +
        "(station_task): bash apps/mbui/scripts/screens.sh rerecord \{mode}",
      )
    Some((_, h)) if h == hash && unlike_mac != "" =>
      fail("\{mode}: drawn as the Mac draws it now: its unlike_mac (\{unlike_mac}) can go")
    _ => ()
  }
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
  it.write(t.drawlist(bytes=true))
  it.snapshot(filename=mode + ".dl")
}

///|
/// `mode`'s screen (`screen`) checked (`screen_check`).
fn check(it : @test.Test, mode : String, opening : Double, unlike_mac? : String = "") -> Unit raise {
  screen_check(it, screen(mode, opening, unlike_mac~), mode, unlike_mac~)
}

// The settings' pages (shots.sh's SETTINGS_PAGES): pushed over Home before the first frame, settings and the page
// together (@sfapp.open_setting), each push nav_push_ms.

///|
test "settings-home" (it : @test.Test) {
  check(it, "settings-home", @ui.nav_push_ms)
}

///|
test "settings-home-dark" (it : @test.Test) {
  check(it, "settings-home-dark", @ui.nav_push_ms)
}

///|
test "settings-appearance" (it : @test.Test) {
  check(it, "settings-appearance", @ui.nav_push_ms)
}

///|
test "settings-me" (it : @test.Test) {
  check(it, "settings-me", @ui.nav_push_ms)
}

///|
test "settings-workspace" (it : @test.Test) {
  check(it, "settings-workspace", @ui.nav_push_ms)
}

///|
test "settings-security" (it : @test.Test) {
  check(it, "settings-security", @ui.nav_push_ms)
}

///|
test "settings-vault" (it : @test.Test) {
  check(it, "settings-vault", @ui.nav_push_ms)
}

///|
test "settings-stations" (it : @test.Test) {
  check(it, "settings-stations", @ui.nav_push_ms)
}

///|
test "settings-station" (it : @test.Test) {
  check(it, "settings-station", @ui.nav_push_ms)
}

///|
test "settings-profiles" (it : @test.Test) {
  check(it, "settings-profiles", @ui.nav_push_ms)
}

///|
test "settings-profile" (it : @test.Test) {
  check(it, "settings-profile", @ui.nav_push_ms)
}

///|
test "settings-connects" (it : @test.Test) {
  check(it, "settings-connects", @ui.nav_push_ms)
}

///|
test "settings-memory" (it : @test.Test) {
  check(it, "settings-memory", @ui.nav_push_ms)
}

///|
test "settings-memory-doc" (it : @test.Test) {
  check(it, "settings-memory-doc", @ui.nav_push_ms)
}

///|
test "settings-usage" (it : @test.Test) {
  check(it, "settings-usage", @ui.nav_push_ms)
}

///|
test "settings-archive" (it : @test.Test) {
  check(it, "settings-archive", @ui.nav_push_ms)
}

// Home over the made-up chats, nothing pushed (shots.sh home, its sheet; decide's home-jobs; notify's)

///|
test "home" (it : @test.Test) {
  check(it, "home", nothing_opens)
}

///|
test "home-sheet" (it : @test.Test) {
  check(it, "home-sheet", nothing_opens)
}

///|
test "home-jobs" (it : @test.Test) {
  check(it, "home-jobs", nothing_opens)
}

///|
test "settings-notify-off" (it : @test.Test) {
  check(it, "settings-notify-off", @ui.nav_push_ms)
}

// The first row's chat pushed over Home (shots.sh chat, composer, cards; notify's flash)

///|
test "chat" (it : @test.Test) {
  check(it, "chat", @ui.nav_push_ms)
}

///|
test "chat-loading" (it : @test.Test) {
  check(it, "chat-loading", @ui.nav_push_ms)
}

///|
test "chat-compose" (it : @test.Test) {
  check(it, "chat-compose", @ui.nav_push_ms)
}

///|
test "chat-attach" (it : @test.Test) {
  check(
    it,
    "chat-attach",
    @ui.nav_push_ms,
  )
}

///|
test "chat-quote" (it : @test.Test) {
  check(it, "chat-quote", @ui.nav_push_ms)
}

///|
test "chat-sending" (it : @test.Test) {
  check(
    it,
    "chat-sending",
    @ui.nav_push_ms,
  )
}

///|
test "chat-failed" (it : @test.Test) {
  check(it, "chat-failed", @ui.nav_push_ms)
}

///|
test "chat-cards" (it : @test.Test) {
  check(it, "chat-cards", @ui.nav_push_ms)
}

///|
test "chat-answering" (it : @test.Test) {
  check(it, "chat-answering", @ui.nav_push_ms)
}

///|
test "chat-md" (it : @test.Test) {
  check(it, "chat-md", @ui.nav_push_ms)
}

///|
test "chat-pick" (it : @test.Test) {
  check(
    it,
    "chat-pick",
    @ui.nav_push_ms,
  )
}

///|
test "chat-link-menu" (it : @test.Test) {
  check(it, "chat-link-menu", @ui.nav_push_ms)
}

///|
test "chat-flash" (it : @test.Test) {
  check(
    it,
    "chat-flash",
    @ui.nav_push_ms,
  )
}

///|
test "chat-flash-mine" (it : @test.Test) {
  check(it, "chat-flash-mine", @ui.nav_push_ms)
}

// The drive's pages pushed over Home (shots.sh DRIVE_MODES)

///|
test "files" (it : @test.Test) {
  check(it, "files", @ui.nav_push_ms)
}

///|
test "drive" (it : @test.Test) {
  check(it, "drive", @ui.nav_push_ms)
}

///|
test "drive-sub" (it : @test.Test) {
  check(it, "drive-sub", @ui.nav_push_ms)
}

///|
test "drive-chosen" (it : @test.Test) {
  check(it, "drive-chosen", @ui.nav_push_ms)
}

///|
test "drive-entry" (it : @test.Test) {
  check(it, "drive-entry", @ui.nav_push_ms)
}

///|
test "drive-upload" (it : @test.Test) {
  check(it, "drive-upload", @ui.nav_push_ms)
}

///|
test "drive-download" (it : @test.Test) {
  check(it, "drive-download", @ui.nav_push_ms)
}

///|
test "drive-empty" (it : @test.Test) {
  check(it, "drive-empty", @ui.nav_push_ms)
}

///|
test "reader" (it : @test.Test) {
  check(it, "reader", @ui.nav_push_ms)
}

///|
test "reader-bars" (it : @test.Test) {
  check(it, "reader-bars", @ui.nav_push_ms)
}

///|
test "reader-contents" (it : @test.Test) {
  check(it, "reader-contents", @ui.nav_push_ms)
}

///|
test "reader-layout" (it : @test.Test) {
  check(it, "reader-layout", @ui.nav_push_ms)
}

///|
test "reader-md" (it : @test.Test) {
  check(it, "reader-md", @ui.nav_push_ms)
}

///|
test "chat-station-files" (it : @test.Test) {
  check(it, "chat-station-files", @ui.nav_push_ms)
}

///|
test "chat-station-ref" (it : @test.Test) {
  check(it, "chat-station-ref", @ui.nav_push_ms)
}

///|
test "chat-station-file" (it : @test.Test) {
  check(it, "chat-station-file", @ui.nav_push_ms)
}

///|
test "chat-station-sheet" (it : @test.Test) {
  check(it, "chat-station-sheet", @ui.nav_push_ms)
}

// The 奏 page, a chat's history; a chat's sheets over the chat pushed (shots.sh DECIDE)

///|
test "decisions" (it : @test.Test) {
  check(it, "decisions", @ui.nav_push_ms)
}

///|
test "decisions-text" (it : @test.Test) {
  check(it, "decisions-text", @ui.nav_push_ms)
}

///|
test "decisions-idle" (it : @test.Test) {
  check(it, "decisions-idle", @ui.nav_push_ms)
}

///|
test "history" (it : @test.Test) {
  check(it, "history", @ui.nav_push_ms)
}

///|
test "history-details" (it : @test.Test) {
  check(it, "history-details", @ui.nav_push_ms)
}

///|
test "chat-info" (it : @test.Test) {
  check(it, "chat-info", @ui.nav_push_ms)
}

///|
test "chat-agent" (it : @test.Test) {
  check(it, "chat-agent", @ui.nav_push_ms)
}

///|
test "chat-jobs" (it : @test.Test) {
  check(it, "chat-jobs", @ui.nav_push_ms)
}

///|
test "chat-job" (it : @test.Test) {
  check(it, "chat-job", @ui.nav_push_ms)
}

// A new chat risen over Home, its sheets; the bar's panel; a place (shots.sh newchat)

///|
test "newchat" (it : @test.Test) {
  check(it, "newchat", @ui.nav_rise_ms)
}

///|
test "newchat-station" (it : @test.Test) {
  check(it, "newchat-station", @ui.nav_rise_ms)
}

///|
test "newchat-model" (it : @test.Test) {
  check(it, "newchat-model", @ui.nav_rise_ms)
}

///|
test "home-bars" (it : @test.Test) {
  check(it, "home-bars", nothing_opens)
}

///|
test "place" (it : @test.Test) {
  check(it, "place", nothing_opens)
}

// A chat's file in the preview (shots.sh preview)

///|
test "chat-preview-image" (it : @test.Test) {
  check(it, "chat-preview-image", @ui.nav_push_ms)
}

///|
test "chat-preview-pdf" (it : @test.Test) {
  check(
    it,
    "chat-preview-pdf",
    @ui.nav_push_ms,
  )
}

///|
test "chat-preview-video" (it : @test.Test) {
  check(
    it,
    "chat-preview-video",
    @ui.nav_push_ms,
    unlike_mac="its video's frames: the fake host has them at once, the Mac is still reading them",
  )
}

///|
test "chat-preview-audio" (it : @test.Test) {
  check(it, "chat-preview-audio", @ui.nav_push_ms)
}

///|
test "chat-preview-html" (it : @test.Test) {
  check(it, "chat-preview-html", @ui.nav_push_ms)
}

///|
test "chat-preview-code" (it : @test.Test) {
  check(it, "chat-preview-code", @ui.nav_push_ms)
}

///|
test "chat-preview-md" (it : @test.Test) {
  check(it, "chat-preview-md", @ui.nav_push_ms)
}

///|
test "chat-preview-csv" (it : @test.Test) {
  check(it, "chat-preview-csv", @ui.nav_push_ms)
}

///|
test "chat-preview-none" (it : @test.Test) {
  check(it, "chat-preview-none", @ui.nav_push_ms)
}

///|
test "chat-preview-step" (it : @test.Test) {
  check(it, "chat-preview-step", @ui.nav_push_ms)
}

///|
test "chat-preview-swipe" (it : @test.Test) {
  check(it, "chat-preview-swipe", @ui.nav_push_ms)
}

// The player, a web service's page, what another app shares in (shots.sh player, service, share)

///|
test "player-video" (it : @test.Test) {
  check(it, "player-video", @ui.nav_push_ms)
}

///|
test "player-audio" (it : @test.Test) {
  check(
    it,
    "player-audio",
    @ui.nav_push_ms,
  )
}

///|
test "player-ended" (it : @test.Test) {
  check(it, "player-ended", @ui.nav_push_ms)
}

///|
test "player-opening" (it : @test.Test) {
  check(
    it,
    "player-opening",
    @ui.nav_push_ms,
    unlike_mac="its player's state: the fake host's player knows the length the Mac is still reading",
  )
}

///|
test "service" (it : @test.Test) {
  check(it, "service", @ui.nav_push_ms)
}

///|
test "service-sized" (it : @test.Test) {
  check(it, "service-sized", @ui.nav_push_ms)
}

///|
test "service-restart" (it : @test.Test) {
  check(it, "service-restart", @ui.nav_push_ms)
}

///|
test "service-stopped" (it : @test.Test) {
  check(it, "service-stopped", @ui.nav_push_ms)
}

///|
test "share-in" (it : @test.Test) {
  check(it, "share-in", nothing_opens)
}

///|
test "share-in-stations" (it : @test.Test) {
  check(it, "share-in-stations", nothing_opens)
}

///|
test "share-in-files" (it : @test.Test) {
  check(
    it,
    "share-in-files",
    nothing_opens,
  )
}
