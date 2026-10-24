// A new device showing this one's code (Security.kt LockPrompts, pairSheet; the core's `lockPrompts`, views/pair.ts):
// put up over whichever page is open, in any workspace of the person's, and again after something else took its place,
// until it is done or turned away. Nothing here approves it, only the code typed on the new device; turned away (拒绝),
// it is denied (`lockPrompt.deny`) and its code is worth nothing; closed by hand (a tap beside it, back), it is no
// longer shown (`lockPrompt.hide`) and its code still holds: read by then, it is typed on the new device next.

///|
/// The asks turned away or closed here (a device and the code it was shown, `ask_of`): not put up again while the core
/// has yet to drop them. The same device asking again (a new code) is put up again: it was not until the app started
/// again (2026-10-23, 弹窗不弹). What the core dropped is forgotten here too.
let prompts_closed : Array[String] = []

///|
fn ask_of(r : Json) -> String {
  text(Some(r), "device") + " " + text(Some(r), "code")
}

///|
fn lock_prompts_reset() -> Unit {
  prompts_closed.clear()
}

///|
/// The oldest device waiting on this one's code, put up in a sheet when nothing else is (`free`: no sheet of the
/// app's up): call each frame, over the pages.
pub fn lock_prompts(core : Core, free : Bool) -> Unit {
  let prompts = (core.topic)("lockPrompts", Map::new()).value
  let pairing = items(prompts, "pairing")
  if prompts is Some(_) {
    prompts_closed.retain(fn(d) { pairing.iter().any(fn(r) { ask_of(r) == d }) })
  }
  let waiting = pairing.iter().find_first(fn(r) { !prompts_closed.contains(ask_of(r)) })
  match waiting {
    Some(r) if free && !sheet_up() => pair_sheet(core, r)
    _ => ()
  }
}

///|
/// The sheet of a new device asking (Security.kt pairSheet): whose it is and what, where it asks to be let in, the code
/// large, that it is shown only here, 拒绝. Gone by itself once that device is done or turned away elsewhere.
fn pair_sheet(core : Core, r : Json) -> Unit {
  let rv = Some(r)
  let device = text(rv, "device")
  let deny = fn() {
    prompts_closed.push(ask_of(r))
    act(core, tr("web-pages.security.denyDevice"), "lockPrompt.deny", obj([("device", str(device))]))
  }
  let hide = fn() {
    prompts_closed.push(ask_of(r))
    (core.call)("lockPrompt.hide", obj([("device", str(device))]), fn(_) {  })
  }
  let who = match text(rv, "name") {
    "" => text(rv, "email")
    n => n
  }
  open_sheet(0.55, on_close=hide, fn(c, _) {
    // done or turned away on another device: gone here too; asked in one more workspace meanwhile, named too
    let prompts = (core.topic)("lockPrompts", Map::new()).value
    let now = items(prompts, "pairing").iter().find_first(fn(x) { text(Some(x), "device") == device })
    if prompts is Some(_) && now is None {
      close_sheet()
      return
    }
    let shown = match now {
      Some(x) => Some(x)
      None => rv
    }
    sheet_head(c, fill("web-pages.security.pairTitle", [("name", who)]))
    c.box(style=pair_column, fn() {
      c.text(fill("web-pages.security.pairBody", [("device", text(rv, "deviceText"))]), style=pair_body)
      |> ignore
      c.box(style=pair_places, fn() {
        c.text(tr("web-pages.security.promptFor"), style=pair_places_head) |> ignore
        for w in items(shown, "workspaces") {
          c.text(text(Some(w), "name"), style=pair_place) |> ignore
        }
      })
      |> ignore
      mono(c, spaced(text(shown, "code")), size=34.0, weight=600, line=44.0, center=true)
      note(c, tr("web-pages.security.pairNote"))
      c.box(style=pair_deny_room, fn() {
        if wide_button(c, "lock-pair-deny", tr("web-pages.security.pairDeny"), false) {
          close_sheet()
          deny()
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// What the sheet holds, 20 in from its sides, 12 apart (Security.kt:372).
// kept across runs: a value (no field of it changes)
let pair_column : @ui.Style = @ui.css("w=Full px=S5 gap=S3")

///|
/// Whose device it is and what (14 in the muted: Security.kt:373).
// kept across runs: a value (no field of it changes)
let pair_body : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, w=Full)

///|
/// Where it asks to be let in: 申请访问 (13 muted), each workspace's name under it (16 semibold), 4 apart.
// kept across runs: a value (no field of it changes)
let pair_places : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let pair_places_head : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let pair_place : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg)

///|
/// 拒绝, as wide as the sheet, 4 under the note and 16 over the sheet's foot (Security.kt:381).
// kept across runs: a value (no field of it changes)
let pair_deny_room : @ui.Style = @ui.css("w=Full pt=S1 pb=S4")

///|
/// A code's letters a little apart (letterSpacing 5): a thin space between each two.
fn spaced(code : String) -> String {
  let b = StringBuilder()
  let mut first = true
  for ch in code {
    if !first {
      b.write_char('\u{2009}')
    }
    b.write_char(ch)
    first = false
  }
  b.to_string()
}
