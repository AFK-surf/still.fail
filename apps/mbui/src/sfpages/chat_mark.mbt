// A chat's state as a mark in a line (ember web/src/ChatMark.tsx ChatMark `inline`, ChatMark.css.ts chatMarkInline):
// before a row's title in the chats' lists (sidebar.mbt, a finger's and a mouse's alike), on the rail's lists and
// workspaces. Three colours, bright in both themes: yellow at work, blue
// done and not yet read, red to be seen now; a blue ring when something waits on the viewer, a grey one when only on
// others.

///|
/// A chat's mark `tone` (the core's: busy, done, alert, wait, other; anything else none), the row's ground behind it:
/// a dot 8 across done (blue) or to be seen now (red, a soft halo 3 past it), a ring 10 across and 2 thick waiting (on
/// the viewer blue, on others grey), at work yellow spokes stepping round in 10. Its node (0 for none).
pub fn chat_mark(c : @ui.Ctx, tone : String) -> Int {
  let label = match tone {
    "busy" | "done" | "alert" | "wait" | "other" => @sf.t("web-main.chatMark." + tone)
    _ => return 0
  }
  match tone {
    "done" => c.box(style=mark_done, label~, fn() {  })
    "alert" =>
      c.box(style=mark_alert, label~, fn() {
        // (::after: inset -3, the red at 25% over the dot)
        c.layer(fn() { c.box(style=mark_halo, tx=-mark_halo_out, ty=-mark_halo_out, fn() {  }) |> ignore }) |> ignore
      })
    "wait" => c.box(style=mark_wait, label~, fn() {  })
    "other" => c.box(style=mark_other, label~, fn() {  })
    _ => c.box(style=mark_busy, label~, fn() { @sf.spokes(c, mark_busy_side, @sf.mark_yellow) |> ignore })
  }
}

///|
/// How far the alert's halo reaches past its dot, and the spokes' box.
let mark_halo_out : Double = 3.0

///|
let mark_busy_side : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let mark_done : @ui.Style = @ui.style(w=S2, h=S2, radius=Full, bg=@sf.mark_blue)

///|
// kept across runs: a value (no field of it changes)
let mark_alert : @ui.Style = @ui.style(w=S2, h=S2, radius=Full, bg=@sf.mark_red)

///|
// kept across runs: a value (no field of it changes)
let mark_halo : @ui.Style = @ui.style(w=S3_5, h=S3_5, radius=Full, bg=@sf.mark_halo)

///|
// kept across runs: a value (no field of it changes)
let mark_wait : @ui.Style = @ui.style(w=S2_5, h=S2_5, radius=Full, border=B2, border_color=@sf.mark_blue)

///|
// kept across runs: a value (no field of it changes)
let mark_other : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full border=B2 border_color=Subtle")

///|
// kept across runs: a value (no field of it changes)
let mark_busy : @ui.Style = @ui.css("w=S2_5 h=S2_5")

///|
/// A row's mark (ChatMark.tsx ChatMark, its row's `key`): one that comes while the chat is in view (a new message, work
/// begun) pops in (scale 0, 1.3 at 60%, 1: 320 ms, ease-out); one there as the list is first drawn does not.
pub fn row_mark(c : @ui.Ctx, key : String, tone : String) -> Unit {
  let pop = @motion.anim(c, "side/mark-pop/" + key, 1.0, global=true)
  match marks_seen.get(key) {
    Some(was) if was != tone => {
      marks_seen[key] = tone
      if tone != "" && !@ui.reduced_motion() {
        pop.snap(0.0)
        pop.animate(1.0, @motion.tween(mark_pop_ms, ease=CssOut))
      }
    }
    None => marks_seen[key] = tone
    _ => ()
  }
  let mark = chat_mark(c, tone)
  let v = pop.get()
  if mark != 0 && v < 1.0 {
    c.look(mark, @ui.look(scale=pop_scale(v)))
  }
}

///|
/// The mark each chat has had, as its row was last drawn (ChatMark.tsx `shown`).
let marks_seen : Map[String, String] = {}

///|
fn marks_reset() -> Unit {
  marks_seen.clear()
}

///|
/// The pop's length, and its size at `v` of the way (0, 1.3 at 60%, 1).
let mark_pop_ms : Double = 320.0

///|
fn pop_scale(v : Double) -> Double {
  if v < mark_pop_peak_at {
    mark_pop_peak * v / mark_pop_peak_at
  } else {
    mark_pop_peak - (mark_pop_peak - 1.0) * (v - mark_pop_peak_at) / (1.0 - mark_pop_peak_at)
  }
}

///|
let mark_pop_peak : Double = 1.3

///|
let mark_pop_peak_at : Double = 0.6


// A row's second line from where its chat stands (ember web/src/ChatMark.tsx WaitingText `slot`, ChatMark.css.ts
// leadLine, leadSlot, waitingLead; Sidebar.css.ts navSessionLast): by what the core says leads it (ChatItem's
// state_lead, its card's lead word state_lead_text, what follows state_rest), never read out of the words. A lead said
// as an icon (needs the viewer a bell, done a check, waiting the waiting arc, watching a radar) stands in the title's
// mark's column, centred under it, what follows where the title starts; the two still going move (waiting's dots
// breathe in turn, the radar's dot beats and its arcs light up after it, inner then outer, then rest: every 3.1 s). 奏 ·
// … in ink, its lead word bold; needs the viewer in ink too; anything else as quiet as the last message.

///|
/// The state line `text` (the core's stateText): `lead` what leads it, `lead_text` a card's lead word, `rest` what
/// follows the lead; `alert` (a message that did not go) in red. `slot`: the icon's place's id (`taps` on it go to the
/// row: the row asks for them by it), its tip `key`.
pub fn state_line(
  c : @ui.Ctx,
  key : String,
  slot : Int,
  text : String,
  lead? : String = "",
  lead_text? : String = "",
  rest? : String = "",
  alert? : Bool = false,
) -> Unit {
  let turn = lead == "decision" || lead == "need"
  // (a finger's row's size: mobile/Home.css.ts mLast, 14 on 20)
  let finger = @sf.touch_system()
  let words = if alert {
    if finger { state_alert_touch } else { state_alert }
  } else if turn {
    if finger { state_turn_touch } else { state_turn }
  } else if finger {
    state_quiet_touch
  } else {
    state_quiet
  }
  match lead {
    "need" | "done" | "wait" | "watch" => {
      let label = match lead {
        "watch" => text
        "need" => @sf.t("web-main.chatMark.alert")
        "done" => @sf.t("web-main.status.done")
        _ => @sf.t("web-main.status.waiting")
      }
      let ink = if alert {
        @sf.theme().p.red
      } else if turn {
        @sf.theme().p.text
      } else {
        @sf.theme().p.muted
      }
      // (read out whole: its aria-label)
      c.box(style=state_lead_line, label=text, fn() {
        let b = c.box(style=state_slot, id=slot, fn() { lead_icon(c, lead, ink) })
        // (role="img": its words, the row pressed through it)
        c.semantics(b, Image, id=slot, label~)
        if rest != "" {
          c.text(rest, style=words) |> ignore
        }
      })
      |> ignore
      @sf.tip(c, key + "/lead-tip", slot, label)
    }
    "decision" if lead_text != "" && text.has_prefix(lead_text) =>
      c.box(style=state_row, fn() {
        // (bold with a finger, as the phone's: Home.kt StateLine; 600 with a mouse, ChatMark.css.ts)
        c.text(lead_text, style=words.then(if finger { lead_word_touch } else { lead_word })) |> ignore
        c.text(text.view(start_offset=lead_text.length()).to_owned(), style=words) |> ignore
      })
      |> ignore
    _ => c.text(text, style=words) |> ignore
  }
}

///|
/// The lead's icon, 14 in its 10 wide column (standing 2 out of it each side): a bell, a check; waiting's arc with its
/// three dots breathing one after another; watching's dot beating, its arcs lit after it. Each part that moves is drawn
/// apart, over what stays (leadSlot's copies).
fn lead_icon(c : @ui.Ctx, lead : String, ink : Int64) -> Unit {
  let name = match lead {
    "need" => "bell"
    "done" => "check"
    _ => lead
  }
  c.box(style=state_icon_at, tx=-state_icon_out, fn() {
    match lead {
      "wait" => {
        @sf.icon_parts(c, name, [0], size=state_icon, color=ink) |> ignore
        for k, d in wait_delays {
          let part = c.layer(fn() { @sf.icon_parts(c, name, [k + 1], size=state_icon, color=ink) |> ignore })
          c.look(part, @ui.look(alpha=lead_breathe(lead_phase(c, d))))
        }
      }
      "watch" => {
        let dot = c.layer(fn() { @sf.icon_parts(c, name, [0], size=state_icon, color=ink) |> ignore })
        c.look(dot, @ui.look(scale=lead_beat(lead_phase(c, 0.0))))
        for k, d in watch_delays {
          let arcs = c.layer(fn() { @sf.icon_parts(c, name, [2 * k + 1, 2 * k + 2], size=state_icon, color=ink) |> ignore })
          c.look(arcs, @ui.look(alpha=lead_lit(lead_phase(c, d))))
        }
      }
      _ => @sf.icon(c, name, size=state_icon, color=ink) |> ignore
    }
  })
  |> ignore
}

///|
/// The icon (14), and how far it stands out of its 10 wide column on each side.
let state_icon : Double = 14.0

///|
let state_icon_out : Double = 2.0

///|
/// The loop's length (3.1 s) and each part's delay in it: waiting's dots 0, .3 s, .6 s; watching's arcs .18 s, .42 s
/// (its dot at once).
let lead_loop_ms : Double = 3100.0

///|
// kept across runs: a table, never written
let wait_delays : Array[Double] = [0.0, 300.0, 600.0]

///|
// kept across runs: a table, never written
let watch_delays : Array[Double] = [180.0, 420.0]

///|
/// Where a part `delay` late is in its loop now (0 to 1); with motion reduced, at its rest (0: what each is between
/// beats).
fn lead_phase(c : @ui.Ctx, delay : Double) -> Double {
  if @ui.reduced_motion() {
    return 0.0
  }
  let f = c.cycle(lead_loop_ms) - delay / lead_loop_ms
  f - f.floor()
}

///|
/// A keyframe track at `f` (0 to 1): its stops (where, what), each step eased by `ease`.
fn keyframes(f : Double, stops : Array[(Double, Double)], ease : @ui.Ease) -> Double {
  for i in 1..<stops.length() {
    let (a, va) = stops[i - 1]
    let (b, vb) = stops[i]
    if f <= b {
      let t = if b > a { (f - a) / (b - a) } else { 1.0 }
      return va + (vb - va) * ease.at(t)
    }
  }
  stops[stops.length() - 1].1
}

///|
/// Waiting's dots (keyframes.css.ts leadBreathe, ease-in-out): .35, 1 at 23%, .35 from 52% on.
fn lead_breathe(f : Double) -> Double {
  keyframes(f, breathe_stops, InOut)
}

///|
// kept across runs: a table, never written
let breathe_stops : Array[(Double, Double)] = [(0.0, 0.35), (0.23, 1.0), (0.52, 0.35), (1.0, 0.35)]

///|
/// Watching's dot (leadBeat, ease-out): its size 1, 1.35 at 8%, 1 from 22% on.
fn lead_beat(f : Double) -> Double {
  keyframes(f, beat_stops, CssOut)
}

///|
// kept across runs: a table, never written
let beat_stops : Array[(Double, Double)] = [(0.0, 1.0), (0.08, 1.35), (0.22, 1.0), (1.0, 1.0)]

///|
/// Watching's arcs (leadLit, ease-out): .3, 1 at 10%, .3 from 32% on.
fn lead_lit(f : Double) -> Double {
  keyframes(f, lit_stops, CssOut)
}

///|
// kept across runs: a table, never written
let lit_stops : Array[(Double, Double)] = [(0.0, 0.3), (0.1, 1.0), (0.32, 0.3), (1.0, 0.3)]

///|
/// A row's second line's words (Sidebar.css.ts navSessionLast: 12 on 18, as long as there is room): quiet, in ink
/// when it is the viewer's turn, in red when a message did not go.
// kept across runs: a value (no field of it changes)
let state_quiet : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let state_turn : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, leading=L5, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let state_alert : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, leading=L5, wrap=false, w=Full)

///|
/// The same on a finger's row (mobile/Home.css.ts mLast: 14 on 20).
// kept across runs: a value (no field of it changes)
let state_quiet_touch : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, leading=L6, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let state_turn_touch : @ui.TextStyle = @ui.text_style(size=Base, color=Fg, leading=L6, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let state_alert_touch : @ui.TextStyle = @ui.text_style(size=Base, color=Danger, leading=L6, wrap=false, w=Full)

///|
/// The line led by an icon (leadLine): the icon's column, then what follows where the title starts (the head's gap,
/// 6: navSessionMeta's --lead-gap).
// kept across runs: a value (no field of it changes)
let state_lead_line : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
/// The title's mark's column: 10 wide, 14 high (leadSlot).
// kept across runs: a value (no field of it changes)
let state_slot : @ui.Style = @ui.css("w=S2_5 h=S3_5")

///|
// kept across runs: a value (no field of it changes)
let state_icon_at : @ui.Style = @ui.css("w=S3_5 h=S3_5")

///|
// kept across runs: a value (no field of it changes)
let state_row : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// A card's lead word (奏): a mouse's 600 (ChatMark.css.ts waitingLead), a finger's bold (Home.kt StateLine).
// kept across runs: a value (no field of it changes)
let lead_word : @ui.TextStyle = @ui.text_style(weight=Semibold, w=Hug)

///|
// kept across runs: a value (no field of it changes)
let lead_word_touch : @ui.TextStyle = @ui.text_style(weight=Bold, w=Hug)
