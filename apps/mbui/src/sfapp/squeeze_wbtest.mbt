// What does not fit, measured (mbui's Tester::squeeze_faults): sffix's screens in the narrowest windows each frame is
// drawn in, in both of the app's languages, over the Tester's own text (CI's: the faults a screen has are its own,
// the same on every machine). Each screen keeps to the bar squeeze_known says for it (the faults it still has): one
// more fails, and one less until the bar is lowered there. A screen not listed has none. scripts/squeeze.sh shows the
// same screens in a Mac's text, as pictures.

///|
/// The windows: the desktop's narrowest (its page 405 beside the rail and the list), an opened fold's inner screen
/// pointed at with a finger (the wide frame by its size classes: 696 across), a tablet's with the least beside the
/// list its page has there (656: 360, @sfdesk.page_beside_least), the narrowest tablet's the wide frame is drawn on
/// (600 across: the list folded to the rail for the page's room), a phone's.
let squeeze_windows : Array[(String, Double, Double, Int, Bool)] = [
  ("desk", 701.0, 760.0, 0, false),
  ("touch", 696.0, 768.0, 2, true),
  ("least", 656.0, 900.0, 2, true),
  ("tablet", 600.0, 900.0, 2, true),
  ("phone", 360.0, 740.0, 2, false),
]

///|
/// The screens, as sffix opens them (fixture.mbt open_fixture_mode).
let squeeze_modes : Array[String] = [
  "home", "chat", "chat-compose", "chat-attach", "chat-quote", "chat-cards", "chat-md", "chat-pick", "chat-info",
  "chat-publish", "chat-agent", "chat-peek", "chat-jobs", "chat-job", "chat-jobs-side", "chat-letters-side",
  "chat-find", "chat-model-pop", "chat-login", "chat-update", "chat-station-files", "chat-preview-image",
  "chat-preview-code", "newchat", "newchat-station", "newchat-model", "newchat-profiles", "place", "files",
  "files-columns", "files-list", "files-preview", "files-transfers", "files-tree", "drive", "drive-sub", "drive-chosen",
  "drive-entry", "drive-upload", "drive-empty", "reader", "decisions", "decisions-text", "history", "history-details",
  "switcher", "keys-dialog", "search", "home-jobs", "service", "settings-home", "settings-appearance", "settings-me",
  "settings-workspace", "settings-security", "settings-vault", "settings-vault-item", "settings-stations",
  "settings-station", "settings-station-env", "settings-profiles", "settings-profile", "settings-profile-models",
  "settings-connects", "settings-connect", "settings-memory", "settings-memory-doc", "settings-usage",
  "settings-archive", "settings-run-models", "settings-run", "settings-decisions", "settings-changelog",
  "settings-new-profile",
]

///|
/// `mode` in window `win` in `lang`, a moment after it opens (what it opens with over): its squeeze faults.
fn squeeze_of(mode : String, win : (String, Double, Double, Int, Bool), lang : String) -> Array[String] {
  let (_, w, h, platform, touch) = win
  let src : Ref[Source?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      let s = match src.val {
        Some(s) => s
        None => {
          let s = fixture_app(mode)
          src.val = Some(s)
          s
        }
      }
      view(c, s)
    },
    w~,
    h~,
    platform~,
    // (the device's language: the fixture's prefs say none)
    env=[("MBUI_LOCALE", lang)],
  )
  if touch {
    t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n") |> ignore
  }
  t.run_for(squeeze_opening)
  t.frame()
  t.squeeze_faults()
}

///|
/// How long after it opens a screen is looked at: what it opens with (a page pushed, a sheet up) over.
let squeeze_opening : Double = 1000.0

///|
/// `lang`'s screens in every window, each against its bar.
fn squeeze_check(lang : String) -> Unit raise {
  let wrong : Array[String] = []
  for win in squeeze_windows {
    for mode in squeeze_modes {
      let at = "\{win.0}-\{lang} \{mode}"
      let faults = squeeze_of(mode, win, lang)
      let known = squeeze_known.get(at).unwrap_or(0)
      if faults.length() != known {
        wrong.push(
          "\{at}: \{faults.length()} squeezed, \{known} known (" +
          (if faults.length() < known {
            "fewer: its bar comes down in squeeze_known_wbtest.mbt"
          } else {
            "more than its bar: give what does not fit a way to give (Ctx::box drop, words cut, a line of its own)"
          }) +
          ")\n  " +
          faults.join("\n  "),
        )
      }
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}

///|
test "squeeze: no screen squeezed past its bar, in Chinese" {
  squeeze_check("zh")
}

///|
test "squeeze: no screen squeezed past its bar, in English" {
  squeeze_check("en")
}
