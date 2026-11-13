// The corner rule (mbui's Tester::corner_faults; mbui's ui/corners.mbt: what
// lies in a rounded container's corner as far from both its edges and concentric with it, the corners of both the
// ladder's) on every screen sffix opens, in the narrowest window of each layout and a wide desktop's, in both of the
// app's languages, over the Tester's own text (the faults a screen has its own, the same on every machine). Each keeps
// to the bar corners_everywhere_known says (the faults it still has): one more fails, and one less until the bar is
// lowered there. A screen not listed has none. scripts/corners.sh shows the same screens in a Mac's text, as
// pictures, what breaks the rule outlined. The same frame of each screen in squeeze_windows is held to its squeeze bar
// too (squeeze_wbtest.mbt), and in Chinese to the contrast rule in the light theme (contrast_wbtest.mbt): a screen is
// opened once for all. (The screens' own tests, screens_wbtest.mbt, hold the phone's screens in the Mac's text to
// corners_known.)

///|
/// The windows: the narrowest of each layout (squeeze_windows: a phone's, a finger's Medium, a desktop's Medium, a
/// tablet's Large) and a wide desktop's (Large, its dialogs and pages at their widest); the desktop's on a Mac (its
/// window's corners 16: what lies in them follows them) and on Windows 11 (8: too square to follow, so standing as
/// alone, as in a square window) (test_window_corner).
let corner_windows : Array[(String, Double, Double, Int, String)] = [
  ("phone", 360.0, 740.0, 2, ""),
  ("touch", 600.0, 900.0, 2, "medium"),
  ("desk", 600.0, 760.0, 0, ""),
  ("desk-win", 600.0, 760.0, 3, ""),
  ("tablet", 840.0, 900.0, 2, "expanded"),
  ("wide", 1280.0, 800.0, 0, ""),
  ("wide-win", 1280.0, 800.0, 3, ""),
]

///|
/// The screens: every mode sffix opens (fixture.mbt open_fixture_mode, settings/fixture.mbt fixture_page). The other
/// failure reasons on the player's page are checked against player-failed separately below.
let corner_modes : Array[String] = {
  let modes = [
    // (webdemo: the web's demo workspace, its chats' rows with people's faces, which chat's fixture has none)
    "webdemo", "home", "home-bars", "home-jobs", "home-sheet", "home-news", "new-workspace", "new-workspace-code", "rail-menu", "landing", "landing-invited", "blocked", "place",
    "switcher", "switcher-found", "keys-dialog", "search", "search-jobs", "search-results", "chat", "chat-agent",
    "chat-agent-unsaid", "chat-answering", "chat-attach", "chat-attach-row", "chat-cards", "chat-compose", "chat-download", "chat-failed", "chat-feedback", "chat-image-coming",
    "chat-file-links", "chat-find", "chat-flash", "chat-flash-mine", "chat-flash-notice", "chat-history-side", "chat-info", "chat-job",
    "chat-jobs", "chat-jobs-pop", "chat-jobs-side", "chat-letters", "chat-letters-info", "chat-letters-open",
    "chat-letters-pop", "chat-letters-side", "chat-things", "chat-things-side", "chat-info-pulls", "chat-link-menu", "chat-loading", "chat-login", "chat-long", "chat-md",
    "chat-model-pop", "chat-model-accounts", "chat-need", "chat-peek", "chat-pick", "chat-preview-apk", "chat-preview-audio",
    "chat-preview-code", "chat-preview-csv", "chat-preview-html", "chat-preview-image", "chat-preview-md",
    "chat-preview-none", "chat-preview-pdf", "chat-preview-step", "chat-preview-swipe", "chat-preview-video",
    "chat-publish", "chat-quote", "chat-screens", "chat-sending", "chat-service-side", "chat-station-file", "chat-station-files",
    "chat-station-ref", "chat-station-sheet", "chat-tabs-side", "chat-view-side", "chat-view-side-image", "chat-view-side-video", "chat-view-side-audio", "chat-update", "chat-vault-typed", "chat-viz", "chat-working", "chat-rig",
    // (对话目录: the long chat away from its end, its rail or round button; its outline open; words found in it)
    "chat-outline-away", "chat-outline", "chat-outline-find", "archived",
    "history", "history-details", "drive", "drive-roots", "drive-download", "drive-empty", "drive-loading", "drive-sub", "drive-upload",
    "files", "files-add-folder", "files-clash", "files-columns", "files-list", "files-preview", "files-split", "files-transfers",
    "files-tree", "place-stations", "place-profiles", "reader", "reader-bars", "reader-contents", "reader-layout", "reader-md", "newchat", "newchat-files", "newchat-lend", "share-card", "share-card-dark",
    "newchat-model", "newchat-profiles", "newchat-reading", "newchat-station",
    // (a preset's dialog and its steps further in: 添加目录, the folder picker at a station's home and in a folder of
    // repositories, 从 Git 克隆, a clone under way and one failed among its folders)
    "newchat-preset-new", "newchat-preset-new-add", "newchat-preset-new-browse", "newchat-preset-new-browse-repos",
    "newchat-preset-new-clone", "newchat-preset-new-clones", "player-audio", "player-ended",
    "player-failed", "player-opening", "player-video", "service", "service-restart", "service-sized", "service-stopped", "share-in",
    "share-in-files", "share-in-stations", "lock-checking", "lock-code", "lock-failed", "lock-finding", "lock-nocode",
    "lock-none", "lock-security", "lock-upgrade", "lock-waiting", "lock-wrong", "screen-agent-driving",
    "screen-agent-paused", "screen-clipboard-driving", "screen-clipboard-old-station", "screen-connecting",
    "screen-denied", "screen-ended", "screen-failed", "screen-files-done", "screen-files-going", "screen-full",
    "screen-full-tools", "screen-gone", "screen-keys", "screen-live", "screen-login-fill", "screen-login-pick", "screen-not-drivable", "screen-outdated", "screen-pages", "screen-read-only",
    "screen-reconnecting", "screen-trackpad", "screen-trackpad-command", "screen-user-pages", "screen-user-tabs", "screen-windows", "screen-window", "settings-home", "settings-appearance",
    "settings-me", "settings-me-reading", "settings-workspace", "settings-security", "settings-vault",
    "settings-vault-items", "settings-vault-item", "settings-stations", "settings-station", "settings-station-offline", "settings-station-env", "settings-station-processes",
    "settings-station-mark", "settings-station-lower", "settings-station-versions", "settings-station-updated", "settings-station-network", "settings-station-copies", "settings-station-copies-alone",
    "settings-station-restore", "settings-station-restore-offer", "settings-station-restore-confirm", "settings-station-restore-confirm-long",
    "settings-station-restored", "settings-stations-add",
    "settings-stations-existing", "settings-stations-command", "settings-first-station", "settings-adb", "settings-adb-unpaired", "settings-adb-pairing", "settings-adb-connected", "settings-adb-failed", "settings-adb-chats", "settings-adb-chats-long", "settings-adb-lock-two", "settings-adb-idle", "settings-adb-desk",
    // (a request for the phone waiting on a phone that lacks something; granted, the card under it for each kind of step
    // left: the switch off, Developer options, Wi-Fi, Wireless debugging (refused the app), the pairing dialog, the code,
    // the phone's own prompt; and connected)
    "chat-phone-lacks", "chat-phone-step-off", "chat-phone-step-developer", "chat-phone-step-wifi", "chat-phone-step-wireless",
    "chat-phone-step-refused", "chat-phone-step-code", "chat-phone-linked-unpaired", "chat-phone-linked-unauthorized",
    "chat-phone-linked-connected",
    "settings-profiles", "settings-profiles-monthly", "settings-profiles-fable", "settings-profiles-own3", "settings-profiles-week-fable", "settings-profiles-several",
    "settings-profile", "settings-profile-fable", "settings-profile-own3", "settings-profile-week-fable", "settings-profile-quota", "settings-profile-quota-kinds",
    "settings-profile-lower", "settings-profile-login", "settings-profile-login-failed", "settings-profile-quota-failed", "settings-profile-copy",
    "settings-profile-blocked", "settings-profile-signin", "settings-profile-key", "settings-new-profile",
    // (添加账号 with three stations up to choose from, #6030; a key's form with a region and a protocol to choose)
    "settings-new-profile-stations", "settings-new-profile-key",
    "settings-connects", "settings-connect", "settings-connect-menu", "settings-connect-mode", "settings-connect-run",
    "settings-new-connect", "settings-new-connect-platform", "settings-new-connect-scan", "settings-new-connect-app",
    // (a Comma connect's model step, and the pages of a Comma and a Feishu connect, none of their sessions yet)
    "settings-new-connect-comma", "settings-connect-comma", "settings-connect-feishu",
    "settings-slack-app", "settings-memory", "settings-memory-doc", "settings-usage", "settings-archive", "settings-kept",
    "settings-kept-many", "settings-vault-off", "settings-vault-plain", "settings-vault-waits", "settings-vault-words", "settings-vault-add",
    "settings-vault-editor", "settings-vault-recover", "settings-lock-prompt", "settings-add-people",
    "settings-workspace-mark", "settings-local-fonts", "settings-policy", "settings-policy-text",
    "settings-policy-option", "settings-security-join", "settings-security-off", "settings-security-pending", "settings-stations-tasks", "place-stations-tasks", "settings-station-tasks", "settings-station-tasks-other", "settings-station-tasks-locked", "settings-stations-devices", "place-stations-devices", "settings-station-devices",
    "settings-run", "settings-run-models", "settings-run-accounts", "settings-fonts", "settings-fonts-code",
    "settings-decisions", "settings-completion", "settings-bars", "settings-about", "settings-changelog", "settings-prices",
    "settings-notify-off", "settings-notify-denied",
  ]
  // (and the card to share in each of its other looks: share_looks.mbt)
  for k in @sfpages.share_look_keys()[1:] {
    modes.push("share-card-" + k)
  }
  modes
}

///|
/// `lang`'s screens in every window, each against its bars: the corners' and, the squeeze's ones, the squeeze's; and
/// (`press_room`, Chinese) a press's room and the light theme's contrast too, on the same screen opened once. (Apart, a
/// sweep each, Chinese's screens were opened twice: of a sweep's 1939 screens, opening them was some seven tenths of
/// its time, the checks the rest, none of them long (27 ms each at the median, 0.3 s the longest), 2026-11-05.)
fn corners_check(lang : String, press_room~ : Bool = false) -> Unit raise {
  let wrong : Array[String] = []
  let gaps : Array[String] = []
  let moves : Array[String] = []
  let rooms : Array[String] = []
  for win in corner_windows {
    let squeezed = squeeze_windows.contains(win.0)
    for mode in corner_modes {
      let at = "\{win.0}-\{lang} \{mode}"
      let t = screen_in(mode, win, lang, motion_judged=false)
      if press_room {
        // (a press's room, at rest and with what shows only under the hand shown: rooms_known_wbtest.mbt; and the
        // contrast's, in the light theme, once: contrast_wbtest.mbt)
        for f in t.room_faults() {
          rooms.push("\{at}: \{f}")
        }
        for f in t.hover_only_faults() {
          rooms.push("\{at}: \{f}")
        }
        match contrast_wrong("\{win.0}-light \{mode}", t.contrast_faults()) {
          Some(w) => wrong.push(w)
          None => ()
        }
      }
      let faults = t.corner_faults()
      for f in t.gap_faults() {
        gaps.push("\{at}: \{f}")
      }
      // (the squeeze's on the screen at rest, before what shows only under the hand is shown)
      let squeeze = if squeezed { squeeze_wrong(at, t.squeeze_faults()) } else { None }
      // and what it shows only under the hand (Ctx::lit_shown, hand_shown: a row's 归档), all of it at once, each fault
      // once
      for f in t.lit_all_faults() {
        if !faults.contains(f) {
          faults.push(f)
        }
      }
      // and with every thing the hand lights lit at once, and all it shows shown: none another size, none moved, no
      // words otherwise (the hand changes a thing's ground and ink alone: Tester::hand_moves)
      for f in t.hand_moves() {
        moves.push("\{at}: \{f}")
      }
      let known = corners_everywhere_known.get(at).unwrap_or(0)
      if faults.length() != known {
        wrong.push(
          "\{at}: \{faults.length()} corners break the rule, \{known} known (" +
          (if faults.length() < known {
            "fewer: its bar comes down in corners_known_wbtest.mbt"
          } else {
            "more than its bar: stand it where it is concentric, or round its container by the ladder's"
          }) +
          ")\n  " +
          faults.join("\n  "),
        )
      }
      if squeeze is Some(w) {
        wrong.push(w)
      }
      // (words a box with its height said does not hold, mbui's Tester::fixed_outgrown, against its bar)
      match outgrown_wrong(at, t.fixed_outgrown(), corners_outgrown_known, "corners_known_wbtest.mbt") {
        Some(w) => wrong.push(w)
        None => ()
      }
    }
  }
  if press_room {
    match rooms_wrong(rooms) {
      Some(w) => wrong.push(w)
      None => ()
    }
  }
  match gaps_wrong(lang, gaps) {
    Some(w) => wrong.push(w)
    None => ()
  }
  if moves.length() > 0 {
    wrong.push(
      "\{moves.length()} things the hand changes the size or place of, or the words' look (its hot style another than " +
      "its rest one's ink: say it as the rest one's .then(@ui.text_style(color=…)); what shows under it kept to the " +
      "room of what it is in):\n  " +
      moves.join("\n  "),
    )
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}

///|
test "corners and squeeze, a press's room and the light theme's contrast: every screen in every window, in Chinese" {
  corners_check("zh", press_room=true)
}

///|
test "corners and squeeze: every screen in every window keeps the corner rule and fits, in English" {
  corners_check("en")
}

///|
/// A fault's node numbers differ when a player card has no button. The boxes and what they hold must still match.
fn gap_without_nodes(s : String) -> String {
  let mut rest = s
  let mut out = ""
  while rest.find(", node ") is Some(i) {
    let after = rest.exact_view(start=i + 7)
    guard after.find(")") is Some(j) else { return out + rest }
    out = out + rest.exact_view(end=i).to_owned() + ")"
    rest = after.exact_view(start=j + 1).to_owned()
  }
  out + rest
}

///|
test "each player failure reason fits without adding a spacing or corner fault" {
  for win in corner_windows {
    for lang in ["zh", "en"] {
      // The player's existing header has a known gap fault on a small screen. These are states of that same page,
      // so compare their actual faults with it rather than counting that same fault once per message.
      // (and its corners with it: the player-failed screen's own, known to corners_everywhere_known, the rail's on the
      // tape)
      let failed = screen_in("player-failed", win, lang)
      let baseline = failed.gap_faults().map(gap_without_nodes)
      let corners = failed.corner_faults().map(gap_without_nodes)
      let lit = failed.lit_all_faults().map(gap_without_nodes)
      for mode in ["player-damaged", "player-unplayable", "player-unsupported"] {
        let t = screen_in(mode, win, lang)
        let at = "\{win.0}-\{lang} \{mode}"
        assert_eq(t.gap_faults().map(gap_without_nodes), baseline, msg=at)
        assert_eq(t.corner_faults().map(gap_without_nodes), corners, msg=at)
        assert_eq(t.lit_all_faults().map(gap_without_nodes), lit, msg=at)
        if squeeze_windows.contains(win.0) {
          assert_true(t.squeeze_faults().is_empty(), msg=at)
        }
      }
    }
  }
}

///|
/// What is wrong of `faults`, the words a box with its height said does not hold on screen `at` (mbui's
/// Tester::fixed_outgrown), against its bar in `known` (kept in `file`): none where they are as many as it says; else
/// how many, the bar, and each.
fn outgrown_wrong(at : String, faults : Array[String], known : Map[String, Int], file : String) -> String? {
  let bar = known.get(at).unwrap_or(0)
  if faults.length() == bar {
    return None
  }
  Some(
    "\{at}: \{faults.length()} words a box with its height said does not hold, \{bar} known (" +
    (if faults.length() < bar {
      "fewer: its bar comes down in \{file}"
    } else {
      "more than its bar: the box grown by its words (a least, min_h, or its height worked out of their line at " +
      "the system's size of words)"
    }) +
    ")\n  " +
    faults.join("\n  "),
  )
}
