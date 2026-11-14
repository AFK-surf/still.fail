// What does not fit once what people, agents and stations wrote is at its longest: the squeeze sweep's screens
// (squeeze_wbtest.mbt; said_modes of them) again, each field the core's schema marks `said` (said_paths.mbt, made by
// the core's scripts/shapes.ts) made long, with a line break and words that break late in it, as an agent's notice, a
// chat's title or a station's error may be. A fixture says what a screen shows; what the outside writes there has no
// length a fixture can promise, so each screen is held to fit it at its longest: what does not, gives way (words cut
// short, a part left out, words wrapped: mbui's ui/squeeze.mbt). The words made long: fixture_said.mbt.

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
      let t = screen_in(mode, win, "zh", said=true, motion_judged=false)
      let faults = t.squeeze_faults()
      faults.append(figures_cut(t))
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
  "settings-workspace", "settings-security", "settings-security-pending", "settings-vault", "settings-vault-items", "settings-vault-item", "settings-stations",
  "settings-station", "settings-station-env", "settings-station-processes", "settings-profiles", "settings-profile",
  "settings-connects", "settings-connect", "settings-memory", "settings-memory-doc", "settings-usage",
  "settings-archive", "settings-run-models", "settings-run", "settings-decisions", "settings-changelog",
  "settings-new-profile",
]

///|
/// What each screen still has squeezed with what people wrote at its longest, by window, language and screen: the bar
/// it may only fall from. A screen not listed has none.
let said_known : Map[String, Int] = Map([])

///|
/// The figures the core writes, each at its widest (widest_paths), that `t` shows cut short: a figure is never cut,
/// though words may be (mbui's squeeze.mbt gives words that way to give): $1,9… says no amount (the owner's 「数字都省
/// 略了我他妈看你妈逼」, 2026-11-14, the agent's tiles at $1,911 and 430.5K, which its fixture's $4.20 never showed).
fn figures_cut(t : @ui.Tester) -> Array[String] {
  let widest : Array[String] = []
  for _, paths in @sffixture.widest_paths {
    for p in paths {
      if !widest.contains(p.1) {
        widest.push(p.1)
      }
    }
  }
  let out = []
  for w in t.words() {
    match w.0.strip_suffix("…") {
      Some(kept) if kept.length() > 0 =>
        for f in widest {
          if f != kept.to_owned() && f.has_prefix(kept) {
            out.push("a figure cut short: \{w.0} of \{f} at (\{w.1}, \{w.2})")
            break
          }
        }
      _ => ()
    }
  }
  out
}

///|
test "said_stretch: a figure made what leaf makes of it, the rest as it was" {
  let v : Json = { "cost": "$4.20", "note": "x" }
  let out = said_stretch(v, ["cost"][:], leaf=fn(s) { if s == "" { s } else { "$8,888" } })
  let expected : Json = { "cost": "$8,888", "note": "x" }
  assert_eq(out, expected)
}

///|
/// Each printable ASCII letter's advance in ems (U+0020 to U+007E), the widest of the faces the app's words are set in
/// on a device: what still.fail offers (LXGW WenKai, Inter, Noto Sans SC) and the systems' (SF, Roboto, Arial),
/// read from their hmtx (2026-11-14; LXGW WenKai 1.530 Regular, SF at wght 400, Arial, Noto Sans CJK SC Regular, Inter
/// 4.0 at wght 400, Roboto 2.138 Regular). The fake host's half an em is narrower than every one of them for a
/// figure: a digit 0.6 and more, `%` 0.8 to 0.98, `$` 0.6 to 0.64.
let real_latin : FixedArray[Double] = [
  0.350, 0.350, 0.474, 0.633, 0.642, 0.982, 0.700, 0.350, 0.365, 0.365, 0.501, 0.662, 0.350, 0.460, 0.350, 0.413, 0.631,
  0.600, 0.610, 0.618, 0.646, 0.608, 0.620, 0.600, 0.619, 0.620, 0.350, 0.350, 0.662, 0.662, 0.662, 0.600, 1.015, 0.690,
  0.667, 0.730, 0.728, 0.667, 0.611, 0.778, 0.743, 0.304, 0.571, 0.672, 0.565, 0.903, 0.753, 0.778, 0.667, 0.778, 0.722,
  0.667, 0.646, 0.744, 0.690, 0.985, 0.682, 0.679, 0.629, 0.365, 0.411, 0.365, 0.604, 0.559, 0.606, 0.575, 0.618, 0.571,
  0.620, 0.583, 0.370, 0.613, 0.607, 0.275, 0.301, 0.552, 0.284, 0.926, 0.610, 0.606, 0.620, 0.620, 0.430, 0.528, 0.377,
  0.607, 0.562, 0.818, 0.546, 0.562, 0.552, 0.426, 0.350, 0.426, 0.680,
]

///|
/// The same at weight 600 and more: LXGW WenKai 1.530 Medium (its heaviest), SF and Inter at wght 700, Arial Bold,
/// Roboto Bold.
let real_latin_bold : FixedArray[Double] = [
  0.350, 0.350, 0.551, 0.649, 0.655, 1.016, 0.722, 0.350, 0.382, 0.382, 0.559, 0.679, 0.350, 0.468, 0.350, 0.388, 0.674,
  0.600, 0.629, 0.646, 0.676, 0.639, 0.652, 0.600, 0.651, 0.652, 0.350, 0.350, 0.679, 0.679, 0.679, 0.611, 1.016, 0.747,
  0.722, 0.740, 0.728, 0.667, 0.611, 0.778, 0.747, 0.304, 0.584, 0.722, 0.611, 0.932, 0.762, 0.778, 0.667, 0.778, 0.722,
  0.667, 0.667, 0.732, 0.747, 1.038, 0.738, 0.731, 0.664, 0.382, 0.422, 0.382, 0.647, 0.576, 0.500, 0.581, 0.630, 0.588,
  0.630, 0.596, 0.398, 0.632, 0.623, 0.278, 0.301, 0.580, 0.278, 0.913, 0.623, 0.613, 0.630, 0.630, 0.430, 0.560, 0.366,
  0.623, 0.600, 0.850, 0.580, 0.602, 0.573, 0.469, 0.372, 0.469, 0.679,
]

///|
/// The figures again, each at its widest, measured as the widest real face measures them (real_latin): the agent's
/// tiles fitted `$1,911` in the fake host's half ems and cut it short on a phone set in LXGW WenKai (the owner's
/// screenshot, 2026-11-14), each digit 0.6 of an em there.
test "figures: none cut short at its widest, measured as a real face measures it" {
  let wrong : Array[String] = []
  for win in corner_windows {
    if !squeeze_windows.contains(win.0) {
      continue
    }
    for mode in said_modes {
      let t = screen_in(mode, win, "zh", said=true, latin=Some((real_latin, real_latin_bold)), motion_judged=false)
      // (cut with the words still whole in the draw list, as an old view's words are where they say nothing of it: the
      // squeeze's fault naming the figure; a device's host draws them cut, `$1,9…`)
      let cut = figures_cut(t) +
        t
        .squeeze_faults()
        .filter(fn(f) { @sffixture.widest_paths.values().any(fn(ps) { ps.iter().any(fn(p) { f.contains(p.1) }) }) })
      if cut.length() > 0 {
        wrong.push("\{win.0}-zh \{mode}:\n  " + cut.join("\n  "))
      }
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}
