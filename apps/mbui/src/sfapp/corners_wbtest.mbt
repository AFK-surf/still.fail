// The corner rule (mbui's Tester::corner_faults; still.fail's docs/ui-panels.md「所有带圆角的东西」「圆角阶梯」: what
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
let corner_modes : Array[String] = [
  // (webdemo: the web's demo workspace, its chats' rows with people's faces, which chat's fixture has none)
  "webdemo", "home", "home-bars", "home-jobs", "home-sheet", "home-news", "rail-menu", "landing", "landing-invited", "blocked", "place",
  "switcher", "switcher-found", "keys-dialog", "search", "search-jobs", "search-results", "chat", "chat-agent",
  "chat-agent-unsaid", "chat-answering", "chat-attach", "chat-attach-row", "chat-cards", "chat-compose", "chat-download", "chat-failed",
  "chat-file-links", "chat-find", "chat-flash", "chat-flash-mine", "chat-history-side", "chat-info", "chat-job",
  "chat-jobs", "chat-jobs-pop", "chat-jobs-side", "chat-letters", "chat-letters-info", "chat-letters-open",
  "chat-letters-pop", "chat-letters-side", "chat-things", "chat-things-side", "chat-info-pulls", "chat-link-menu", "chat-loading", "chat-login", "chat-long", "chat-md",
  "chat-model-pop", "chat-need", "chat-peek", "chat-pick", "chat-preview-apk", "chat-preview-audio",
  "chat-preview-code", "chat-preview-csv", "chat-preview-html", "chat-preview-image", "chat-preview-md",
  "chat-preview-none", "chat-preview-pdf", "chat-preview-step", "chat-preview-swipe", "chat-preview-video",
  "chat-publish", "chat-quote", "chat-screens", "chat-sending", "chat-service-side", "chat-station-file", "chat-station-files",
  "chat-station-ref", "chat-station-sheet", "chat-tabs-side", "chat-update", "chat-vault-typed", "chat-viz", "chat-working", "archived",
  "history", "history-details", "drive", "drive-roots", "drive-download", "drive-empty", "drive-loading", "drive-sub", "drive-upload",
  "files", "files-add-folder", "files-clash", "files-columns", "files-list", "files-preview", "files-split", "files-transfers",
  "files-tree", "place-stations", "place-profiles", "reader", "reader-bars", "reader-contents", "reader-layout", "reader-md", "newchat", "newchat-files", "newchat-lend", "share-card", "share-card-dark", "share-card-poster", "share-card-receipt", "share-card-terminal",
  "newchat-model", "newchat-profiles", "newchat-reading", "newchat-station", "player-audio", "player-ended",
  "player-failed", "player-opening", "player-video", "service", "service-restart", "service-sized", "service-stopped", "share-in",
  "share-in-files", "share-in-stations", "lock-checking", "lock-code", "lock-failed", "lock-finding", "lock-nocode",
  "lock-none", "lock-security", "lock-waiting", "lock-wrong", "screen-agent-driving",
  "screen-agent-paused", "screen-clipboard-driving", "screen-clipboard-old-station", "screen-connecting",
  "screen-denied", "screen-ended", "screen-failed", "screen-files-done", "screen-files-going", "screen-full",
  "screen-full-tools", "screen-gone", "screen-live", "screen-login-fill", "screen-login-pick", "screen-not-drivable", "screen-outdated", "screen-read-only",
  "screen-reconnecting", "screen-trackpad", "screen-trackpad-command", "settings-home", "settings-appearance",
  "settings-me", "settings-me-reading", "settings-workspace", "settings-security", "settings-vault",
  "settings-vault-items", "settings-vault-item", "settings-stations", "settings-station", "settings-station-offline", "settings-station-env", "settings-station-processes",
  "settings-station-mark", "settings-station-lower", "settings-station-versions", "settings-station-network", "settings-stations-add",
  "settings-stations-existing", "settings-stations-command", "settings-first-station", "settings-adb", "settings-adb-unpaired", "settings-adb-pairing", "settings-adb-connected", "settings-adb-failed", "settings-adb-chats", "settings-adb-chats-long",
  "settings-profiles", "settings-profiles-monthly", "settings-profile", "settings-profile-quota",
  "settings-profile-lower", "settings-profile-login", "settings-profile-login-failed", "settings-profile-quota-failed",
  "settings-profile-blocked", "settings-profile-signin", "settings-profile-key", "settings-new-profile",
  "settings-connects", "settings-connect", "settings-connect-menu", "settings-connect-mode", "settings-connect-run",
  "settings-new-connect", "settings-new-connect-platform", "settings-new-connect-scan", "settings-new-connect-app",
  "settings-slack-app", "settings-memory", "settings-memory-doc", "settings-usage", "settings-archive", "settings-kept",
  "settings-kept-many", "settings-vault-off", "settings-vault-plain", "settings-vault-words", "settings-vault-add",
  "settings-vault-editor", "settings-vault-recover", "settings-lock-prompt", "settings-add-people",
  "settings-workspace-mark", "settings-local-fonts", "settings-policy", "settings-policy-text",
  "settings-policy-option", "settings-security-join", "settings-security-off",
  "settings-run", "settings-run-models", "settings-run-accounts", "settings-fonts", "settings-fonts-code",
  "settings-decisions", "settings-completion", "settings-bars", "settings-about", "settings-changelog", "settings-prices",
  "settings-notify-off", "settings-notify-denied",
]

///|
/// `lang`'s screens in every window, each against its bars: the corners' and, the squeeze's ones, the squeeze's; or
/// (`press_room`, Chinese) a press's room and the light theme's contrast instead. Apart, a sweep each: the two together were
/// one test of 92 s alone on CI against English's 49, the longest of the app part's runs on four runners (2026-10-27).
fn corners_check(lang : String, press_room~ : Bool = false) -> Unit raise {
  let wrong : Array[String] = []
  let gaps : Array[String] = []
  let moves : Array[String] = []
  let rooms : Array[String] = []
  for win in corner_windows {
    let squeezed = squeeze_windows.contains(win.0)
    for mode in corner_modes {
      let at = "\{win.0}-\{lang} \{mode}"
      let t = screen_in(mode, win, lang)
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
        continue
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
    }
  }
  if press_room {
    match rooms_wrong(rooms) {
      Some(w) => wrong.push(w)
      None => ()
    }
    if wrong.length() > 0 {
      fail(wrong.join("\n"))
    }
    return
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
test "corners and squeeze: every screen in every window keeps the corner rule and fits, in Chinese" {
  corners_check("zh")
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
    let after = rest.view(start_offset=i + 7)
    guard after.find(")") is Some(j) else { return out + rest }
    out = out + rest.view(end_offset=i).to_owned() + ")"
    rest = after.view(start_offset=j + 1).to_owned()
  }
  out + rest
}

///|
test "each player failure reason fits without adding a spacing or corner fault" {
  for win in corner_windows {
    for lang in ["zh", "en"] {
      // The player's existing header has a known gap fault on a small screen. These are states of that same page,
      // so compare their actual faults with it rather than counting that same fault once per message.
      let baseline = screen_in("player-failed", win, lang).gap_faults().map(gap_without_nodes)
      for mode in ["player-damaged", "player-unplayable", "player-unsupported"] {
        let t = screen_in(mode, win, lang)
        let at = "\{win.0}-\{lang} \{mode}"
        assert_eq(t.gap_faults().map(gap_without_nodes), baseline, msg=at)
        assert_true(t.corner_faults().is_empty(), msg=at)
        assert_true(t.lit_all_faults().is_empty(), msg=at)
        if squeeze_windows.contains(win.0) {
          assert_true(t.squeeze_faults().is_empty(), msg=at)
        }
      }
    }
  }
}

///|
test "a press's room and the light theme's contrast: every screen in every window, in Chinese" {
  corners_check("zh", press_room=true)
}
