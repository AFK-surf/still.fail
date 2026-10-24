// The corner rule (mbui's Tester::corner_faults; still.fail's docs/ui-panels.md「所有带圆角的东西」「圆角阶梯」: what
// lies in a rounded container's corner as far from both its edges and concentric with it, the corners of both the
// ladder's) on every screen sffix opens, in the narrowest window of each layout and a wide desktop's, in both of the
// app's languages, over the Tester's own text (the faults a screen has its own, the same on every machine). Each keeps
// to the bar corners_everywhere_known says (the faults it still has): one more fails, and one less until the bar is
// lowered there. A screen not listed has none. scripts/corners.sh shows the same screens in a Mac's text, as
// pictures, what breaks the rule outlined. The same frame of each screen in squeeze_windows and squeeze_modes is held to
// its squeeze bar too (squeeze_wbtest.mbt): a screen is opened once for both. (The screens' own tests, screens_wbtest.mbt, hold the phone's screens in
// the Mac's text to corners_known.)

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
/// The screens: every mode sffix opens (fixture.mbt open_fixture_mode, settings/fixture.mbt fixture_page).
let corner_modes : Array[String] = [
  "home", "home-bars", "home-jobs", "home-sheet", "home-news", "landing", "landing-invited", "blocked", "place",
  "switcher", "switcher-found", "keys-dialog", "search", "search-jobs", "search-results", "chat", "chat-agent",
  "chat-agent-unsaid", "chat-answering", "chat-attach", "chat-attach-row", "chat-cards", "chat-compose", "chat-download", "chat-failed",
  "chat-file-links", "chat-find", "chat-flash", "chat-flash-mine", "chat-history-side", "chat-info", "chat-job",
  "chat-jobs", "chat-jobs-pop", "chat-jobs-side", "chat-letters", "chat-letters-info", "chat-letters-open",
  "chat-letters-pop", "chat-letters-side", "chat-link-menu", "chat-loading", "chat-login", "chat-long", "chat-md",
  "chat-model-pop", "chat-need", "chat-peek", "chat-pick", "chat-preview-apk", "chat-preview-audio",
  "chat-preview-code", "chat-preview-csv", "chat-preview-html", "chat-preview-image", "chat-preview-md",
  "chat-preview-none", "chat-preview-pdf", "chat-preview-step", "chat-preview-swipe", "chat-preview-video",
  "chat-publish", "chat-quote", "chat-screens", "chat-sending", "chat-station-file", "chat-station-files",
  "chat-station-ref", "chat-station-sheet", "chat-update", "chat-viz", "decisions", "decisions-idle", "decisions-text",
  "history", "history-details", "drive", "drive-download", "drive-empty", "drive-loading", "drive-sub", "drive-upload",
  "files", "files-clash", "files-columns", "files-list", "files-preview", "files-split", "files-transfers",
  "files-tree", "reader", "reader-bars", "reader-contents", "reader-layout", "reader-md", "newchat", "newchat-files",
  "newchat-model", "newchat-profiles", "newchat-reading", "newchat-station", "player-audio", "player-ended",
  "player-opening", "player-video", "service", "service-restart", "service-sized", "service-stopped", "share-in",
  "share-in-files", "share-in-stations", "lock-checking", "lock-code", "lock-failed", "lock-finding", "lock-nocode",
  "lock-none", "lock-refused", "lock-security", "lock-waiting", "lock-wrong", "screen-agent-driving",
  "screen-agent-paused", "screen-clipboard-driving", "screen-clipboard-old-station", "screen-connecting",
  "screen-denied", "screen-ended", "screen-failed", "screen-files-done", "screen-files-going", "screen-full",
  "screen-full-tools", "screen-gone", "screen-live", "screen-not-drivable", "screen-outdated", "screen-read-only",
  "screen-reconnecting", "screen-trackpad", "screen-trackpad-command", "settings-home", "settings-appearance",
  "settings-me", "settings-me-reading", "settings-workspace", "settings-security", "settings-vault",
  "settings-vault-item", "settings-stations", "settings-station", "settings-station-offline", "settings-station-env", "settings-station-processes",
  "settings-station-mark", "settings-station-lower", "settings-station-versions", "settings-stations-add",
  "settings-stations-existing", "settings-stations-command", "settings-first-station", "settings-adb",
  "settings-profiles", "settings-profile", "settings-profile-quota", "settings-profile-models", "settings-profile-menu",
  "settings-profile-lower", "settings-profile-login", "settings-profile-login-failed", "settings-profile-quota-failed",
  "settings-profile-blocked", "settings-profile-signin", "settings-profile-key", "settings-new-profile",
  "settings-connects", "settings-connect", "settings-connect-menu", "settings-connect-mode", "settings-connect-run",
  "settings-new-connect", "settings-new-connect-platform", "settings-new-connect-scan", "settings-new-connect-app",
  "settings-slack-app", "settings-memory", "settings-memory-doc", "settings-usage", "settings-archive", "settings-kept",
  "settings-kept-many", "settings-vault-off", "settings-vault-plain", "settings-vault-words", "settings-vault-add",
  "settings-vault-editor", "settings-vault-recover", "settings-lock-prompt", "settings-add-people",
  "settings-workspace-mark", "settings-local-fonts", "settings-policy", "settings-policy-text",
  "settings-policy-option", "settings-security-confirm", "settings-security-join", "settings-security-off",
  "settings-run", "settings-run-models", "settings-run-accounts", "settings-fonts", "settings-fonts-code",
  "settings-decisions", "settings-completion", "settings-bars", "settings-changelog", "settings-prices",
  "settings-notify-off", "settings-notify-denied",
]

///|
/// `lang`'s screens in every window, each against its bars: the corners' and, the squeeze's ones, the squeeze's.
fn corners_check(lang : String) -> Unit raise {
  let wrong : Array[String] = []
  for win in corner_windows {
    let squeezed = squeeze_windows.contains(win.0)
    for mode in corner_modes {
      let at = "\{win.0}-\{lang} \{mode}"
      let t = screen_in(mode, win, lang)
      let faults = t.corner_faults()
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
      if squeezed && squeeze_modes.contains(mode) {
        if squeeze_wrong(at, t.squeeze_faults()) is Some(w) {
          wrong.push(w)
        }
      }
    }
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
