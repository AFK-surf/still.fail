// A new device showing this one's code (pairSheet; the core's `lockPrompts`, views/pair.ts):
// put up over whichever page is open, in any workspace of the person's, once (the library's panel: what is put up
// after it stands over it), until it is done or turned away. Nothing here approves it, only the code typed on the new device; turned away (拒绝),
// it is denied (`lockPrompt.deny`) and its code is worth nothing; closed by hand (a tap beside it, back), it is no
// longer shown (`lockPrompt.hide`) and its code still holds: read by then, it is typed on the new device next.

///|
/// The asks put up here (a device and the code it was shown, `ask_of`), then turned away or closed: not put up again while the core
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
  let prompts = (core.topic)("lockPrompts", Map([])).get().value
  let pairing = items(prompts, "pairing")
  if prompts is Some(_) {
    prompts_closed.retain(fn(d) { pairing.iter().any(fn(r) { ask_of(r) == d }) })
  }
  let waiting = pairing.iter().find_first(fn(r) { !prompts_closed.contains(ask_of(r)) })
  match waiting {
    Some(r) if free && !@sf.presenting() => pair_sheet(core, r)
    _ => ()
  }
}

///|
/// The sheet of a new device asking: whose it is and what, where it asks to be let in, the code
/// large, that it is shown only here, 拒绝. Gone by itself once that device is done or turned away elsewhere. What it
/// holds is nodes of the window's tree, made once as it opens (@sf.panel_nodes).
fn pair_sheet(core : Core, r : Json) -> Unit {
  let rv = Some(r)
  let device = text(rv, "device")
  // (put up once: closed by hand or by the core's drop alike, not again)
  prompts_closed.push(ask_of(r))
  let deny = fn() {
    act(core, tr("web-pages.security.denyDevice"), "lockPrompt.deny", obj([("device", str(device))]))
  }
  let hide = fn() {
    (core.call)("lockPrompt.hide", obj([("device", str(device))]), answer_unread)
  }
  let who = match text(rv, "name") {
    "" => text(rv, "email")
    n => n
  }
  @sf.panel_nodes(fill("web-pages.security.pairTitle", [("name", who)]), from=Unanchored, gone=hide, fn(v, close) {
    // done or turned away on another device: gone here too, as the core says so; asked in one more workspace
    // meanwhile, named too (what it shows bound to the ask as the core holds it now, as it was put up till then)
    let now = fn() { prompt_now(core, "pairing", fn(x) { text(Some(x), "device") == device }) }
    prompt_goes(v, now, close)
    let shown = fn() -> Json? {
      match now() {
        Some(Some(x)) => Some(x)
        _ => rv
      }
    }
    let places = fn() { items(shown(), "workspaces") }
    v.box(fn(col) {
      @sf.style_node(col, fn() { pair_column })
      @sf.words_node(col, fn() { fill("web-pages.security.pairBody", [("device", text(rv, "deviceText"))]) }, fn() { pair_body }) |> ignore
      // (asked into the person's own lock, no workspace's: said so)
      col.show(fn() { places().is_empty() }, fn(p) {
        @sf.words_node(p, fn() { tr("web-pages.security.pairPersonal") }, fn() { pair_places_head }) |> ignore
      })
      col.show(fn() { !places().is_empty() }, fn(p) {
        @sf.style_node(p, fn() { pair_places })
        @sf.words_node(p, fn() { tr("web-pages.security.promptFor") }, fn() { pair_places_head }) |> ignore
        p.each(places, fn(w) { text(Some(w), "id") }, fn(line, w) {
          let wv = fn() { Some(w.get()) }
          // its mark before its name, its letter where it has none
          @sf.style_node(line, fn() { pair_place_line })
          @sf.workspace_badge_node(line, fn() { text(wv(), "name") }, fn() { text(wv(), "emoji") }, fn() { text(wv(), "icon") }, pair_place_mark)
          @sf.words_node(line, fn() { text(wv(), "name") }, fn() { pair_place }) |> ignore
        })
      })
      // the code, large, in the code face, in the middle
      col.box(fn(mid) {
        @sf.style_node(mid, fn() { centre_column })
        mid.box(fn(m) {
          m
          .words_runs(By(fn() { [@ui.span(spaced(text(shown(), "code")), mono=true)] }), look=pair_code_look)
          .ink(By(fn() { @sf.theme().p.text }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // until when it holds (gone from here then)
      col.show(fn() { text(shown(), "untilText") != "" }, fn(u) {
        @sf.words_node(u, fn() { text(shown(), "untilText") }, fn() { pair_until }) |> ignore
      })
      @sf.words_node(col, fn() { tr("web-pages.security.pairNote") }, fn() { @sf.note.then(@sf.full_words) }) |> ignore
      col.box(fn(room) {
        @sf.style_node(room, fn() { pair_deny_room })
        @sf.wide_button_node(
          room,
          fn() { tr("web-pages.security.pairDeny") },
          fn() {
            close()
            deny()
          },
          false,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// What the panel holds, 12 apart.
// kept across runs: a value (no field of it changes)
let pair_column : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// Whose device it is and what.
// kept across runs: a value (no field of it changes)
let pair_body : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// Where it asks to be let in: 申请访问 (13 muted), each workspace's name under it (16 semibold), 4 apart.
// kept across runs: a value (no field of it changes)
let pair_places : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let pair_places_head : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let pair_place : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg)

///|
/// A workspace asked into: its mark 8 before its name, as tall as its words.
// kept across runs: a value (no field of it changes)
let pair_place_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
let pair_place_mark : Double = 20.0

///|
/// The code: 34 semibold in the code face, 44 a line, on one line (mono's, as it was said: size=34, weight=600, line=44).
// kept across runs: a value (no field of it changes)
let pair_code_look : @view.WordsLook = {
  size: 34.0,
  weight: 600,
  line: 44.0,
  wrap: false,
  tracking: @view.letters_own,
  balance: false,
  max_lines: 0,
}

///|
/// Until when the code holds, under it (13 muted, centred).
// kept across runs: a value (no field of it changes)
let pair_until : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)

///|
/// 拒绝, as wide as the sheet, 4 under the note and 16 over the sheet's foot.
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
