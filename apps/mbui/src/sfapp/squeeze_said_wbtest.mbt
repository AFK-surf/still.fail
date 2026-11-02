// What does not fit once what people, agents and stations wrote is at its longest: the squeeze sweep's screens
// (squeeze_wbtest.mbt; said_modes of them) again, each field the core's schema marks `said` (said_paths.mbt, made by
// the core's scripts/shapes.ts) made long, with a line break and words that break late in it, as an agent's notice, a
// chat's title or a station's error may be. A fixture says what a screen shows; what the outside writes there has no
// length a fixture can promise, so each screen is held to fit it at its longest: what does not, gives way (words cut
// short, a part left out, words wrapped: mbui's docs/style.md, Short of room). The words made long: fixture_said.mbt.

///|
test "said_stretch: the words at a path at their longest, each item of a list or a map, none left none, the rest as it was" {
  let v : Json = {
    "jobs": [{ "id": "j1", "name": "盯 CI" }, { "id": "j2", "name": "" }],
    "by": { "a": { "name": "林" } },
    "note": "在线",
  }
  let out = said_stretch(said_stretch(v, ["jobs", "*", "name"][:]), ["by", "*", "name"][:])
  let expected : Json = {
    "jobs": [{ "id": "j1", "name": Json::string("盯 CI" + said_more) }, { "id": "j2", "name": "" }],
    "by": { "a": { "name": Json::string("林" + said_more) } },
    "note": "在线",
  }
  assert_eq(out, expected)
  // (a path that is not there: as it was)
  assert_eq(said_stretch(v, ["gone", "name"][:]), v)
}

///|
test "squeeze: every screen fits what people, agents and stations wrote in it at its longest" {
  let wrong : Array[String] = []
  for win in corner_windows {
    if !squeeze_windows.contains(win.0) {
      continue
    }
    for mode in said_modes {
      let at = "\{win.0}-zh \{mode}"
      let t = screen_in(mode, win, "zh", said=true)
      let faults = t.squeeze_faults()
      let known = said_known.get(at).unwrap_or(0)
      if faults.length() != known {
        wrong.push(
          "\{at}, said at its longest: \{faults.length()} squeezed, \{known} known (" +
          (if faults.length() < known {
            "fewer: its bar comes down in said_known"
          } else {
            "more than its bar: give what does not fit a way to give (words cut, Ctx::box drop, a line of its own)"
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
/// The screens measured with what was said at its longest, as sffix opens them (fixture.mbt open_fixture_mode): the
/// squeeze sweep's until 2026-10-26, when that took every screen the corner test opens (corner_modes).
let said_modes : Array[String] = [
  "home", "chat", "chat-compose", "chat-attach", "chat-quote", "chat-cards", "chat-md", "chat-pick", "chat-info",
  "chat-publish", "chat-agent", "chat-agent-unsaid", "chat-peek", "chat-jobs", "chat-job", "chat-jobs-side", "chat-letters-side", "chat-things", "chat-things-side",
  "chat-find", "chat-model-pop", "chat-login", "chat-update", "chat-working", "chat-station-files", "chat-preview-image",
  "chat-preview-code", "newchat", "newchat-station", "newchat-model", "newchat-profiles", "place", "files",
  "files-columns", "files-list", "files-preview", "files-transfers", "files-tree", "drive", "drive-roots", "drive-sub",
  "drive-upload", "drive-empty", "reader", "history", "history-details",
  "switcher", "keys-dialog", "search", "search-results", "home-jobs", "service", "settings-home", "settings-appearance", "settings-me",
  "settings-workspace", "settings-security", "settings-vault", "settings-vault-items", "settings-vault-item", "settings-stations",
  "settings-station", "settings-station-env", "settings-station-processes", "settings-profiles", "settings-profile",
  "settings-connects", "settings-connect", "settings-memory", "settings-memory-doc", "settings-usage",
  "settings-archive", "settings-run-models", "settings-run", "settings-decisions", "settings-changelog",
  "settings-new-profile",
]

///|
/// What each screen still has squeezed with what people wrote at its longest, by window, language and screen: the bar
/// it may only fall from. A screen not listed has none.
let said_known : Map[String, Int] = Map::new()
