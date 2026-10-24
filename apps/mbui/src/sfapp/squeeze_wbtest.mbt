// What does not fit, measured (mbui's Tester::squeeze_faults): sffix's screens in the narrowest windows each frame is
// drawn in, in both of the app's languages, over the Tester's own text (CI's: the faults a screen has are its own,
// the same on every machine). Each screen keeps to the bar squeeze_known says for it (the faults it still has): one
// more fails, and one less until the bar is lowered there. A screen not listed has none. scripts/squeeze.sh shows the
// same screens in a Mac's text, as pictures.

///|
/// The windows, each the narrowest of its layout (@sf.layout), and the size classes its host says ("" none): a desktop's
/// laid out Medium (600 across: on the tape its page 480 past the sidebar's edge), a phone's or a tablet's laid out
/// Medium (600, medium in width: an opened fold's inner screen upright) and Large (840, expanded: its page 544 beside
/// the rail and the list), pointed at with a finger, in the phone's theme; a phone's.
let squeeze_windows : Array[(String, Double, Double, Int, String)] = [
  ("desk", 600.0, 760.0, 0, ""),
  ("touch", 600.0, 900.0, 2, "medium"),
  ("tablet", 840.0, 900.0, 2, "expanded"),
  ("phone", 360.0, 740.0, 2, ""),
]

///|
/// The screens, as sffix opens them (fixture.mbt open_fixture_mode).
let squeeze_modes : Array[String] = [
  "home", "chat", "chat-compose", "chat-attach", "chat-quote", "chat-cards", "chat-md", "chat-pick", "chat-info",
  "chat-publish", "chat-agent", "chat-agent-unsaid", "chat-peek", "chat-jobs", "chat-job", "chat-jobs-side", "chat-letters-side",
  "chat-find", "chat-model-pop", "chat-login", "chat-update", "chat-station-files", "chat-preview-image",
  "chat-preview-code", "newchat", "newchat-station", "newchat-model", "newchat-profiles", "place", "files",
  "files-columns", "files-list", "files-preview", "files-transfers", "files-tree", "drive", "drive-sub",
  "drive-upload", "drive-empty", "reader", "decisions", "decisions-text", "history", "history-details",
  "switcher", "keys-dialog", "search", "home-jobs", "service", "settings-home", "settings-appearance", "settings-me",
  "settings-workspace", "settings-security", "settings-vault", "settings-vault-item", "settings-stations",
  "settings-station", "settings-station-env", "settings-station-processes", "settings-profiles", "settings-profile", "settings-profile-models",
  "settings-connects", "settings-connect", "settings-memory", "settings-memory-doc", "settings-usage",
  "settings-archive", "settings-run-models", "settings-run", "settings-decisions", "settings-changelog",
  "settings-new-profile",
]

///|
/// `mode` in window `win` in `lang`, a moment after it opens (what it opens with over): its squeeze faults.
fn squeeze_of(mode : String, win : (String, Double, Double, Int, String), lang : String) -> Array[String] {
  screen_in(mode, win, lang).squeeze_faults()
}

///|
/// `mode` in window `win` (its name, size, platform and the size class its host says, "" none) in `lang`, a moment
/// after it opens (what it opens with over), drawn: the squeeze and corner tests' (corners_wbtest.mbt).
fn screen_in(mode : String, win : (String, Double, Double, Int, String), lang : String) -> @ui.Tester {
  let (_, w, h, platform, width) = win
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
    // (the device's language: the fixture's prefs say none; motion reduced, as a person may have it: what a screen
    // opens with at its end at once and a spinner held, so no frame is drawn between its first and the one measured,
    // none of which ever changed what fits: 576 screens' ten frames each were most of the sfapp run, 2026-10-25)
    env=[("MBUI_LOCALE", lang), ("MBUI_REDUCE_MOTION", "1")],
  )
  if width != "" {
    t.drive("system {\"size_class\":{\"width\":\"\{width}\",\"height\":\"medium\"}}\n") |> ignore
  }
  t.run_for(squeeze_opening)
  t.frame()
  t
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
