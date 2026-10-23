// A card over what the pointer rests on, in the wide frame, as the web's (ember web/src/Peeks.tsx Hover, Hover.css.ts
// card, cardTile): opened once the pointer has rested on it 320 ms, closed 120 ms after it has left both it and the
// card; under it and at its start, 6 away, kept in the window; a small panel (the popover's: 6 in, what it holds 10 in
// more), 320 wide (`tile`: as wide as what it holds, 220 at least); it grows out of its edge from .96 as it comes. And
// what an agent's card holds (AgentCard.tsx, AgentCard.css.ts), the same over its picture beside its messages and over
// its mark in the chat's bar.

///|
/// `key`'s card over the trigger `trigger` (its id) while the pointer rests on it, holding `body`. Whether it is open.
fn wide_hover(c : @ui.Ctx, key : String, trigger : Int, tile? : Bool = false, body : () -> Unit) -> Bool {
  @kit.hover_card(
    c,
    key,
    trigger,
    open_delay=hover_open_ms,
    close_delay=hover_close_ms,
    side=Bottom,
    along=Start,
    offset=hover_offset,
    look=fn(c, st, body) {
      let card = c.box(style=if tile { hover_tile } else { hover_card }, fn() {
        @sf.panel(c, w=Fill(1.0), fn() { c.box(style=hover_inner, body) |> ignore }) |> ignore
      })
      // (growing out of the edge it is on, from .96 of its size: Hover.css.ts enter)
      if st.t < 1.0 {
        let oy = match st.side {
          Top => 1.0
          _ => 0.0
        }
        c.look(card, @ui.look(scale=hover_from + (1.0 - hover_from) * dmax(0.0, st.t), ox=0.0, oy~))
      }
    },
    body,
  )
}

///|
/// Its delays (Radix's HoverCard as Peeks.tsx sets it), how far from what it is over, how small it starts.
let hover_open_ms : Double = 320.0

///|
let hover_close_ms : Double = 120.0

///|
let hover_offset : Double = 6.0

///|
let hover_from : Double = 0.96

///|
/// Its width: 320; a tile's as wide as it holds, 220 at least.
// kept across runs: a value (no field of it changes)
let hover_card : @ui.Style = @ui.style(w=@sf.hover_card_w)

///|
// kept across runs: a value (no field of it changes)
let hover_tile : @ui.Style = @ui.style(min_w=@sf.hover_tile_least)

///|
/// What it holds, 10 in from the panel's padding (controls.css.ts panelCard), 8 apart (Hover.css.ts card).
// kept across runs: a value (no field of it changes)
let hover_inner : @ui.Style = @ui.style(w=Full, p=S2_5, gap=S2)

// ── an agent's card ──────────────────────────────────────────────────────

///|
/// One of the chat's agents in brief (AgentCard.tsx): its mark and label, a stop for it alone while it works; where it
/// stands and for how long; its latest three lines; the figures that say most (cost, the cache's hit rate, how full its
/// context is); its account with what is left of it; the rest in a quiet line; its jobs and what is wrong. What the
/// core says of it (the `agentCard` view) as it comes; the rest from the chat's agent at once.
fn agent_card(c : @ui.Ctx, src : Source, r : ChatRef, agent : Agent) -> Unit {
  let t = @sf.theme()
  let key = agent.key
  let a = agent_json((src.topic)("chat", chat_params(r)).value, key)
  guard a is Some(_) else { return }
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let s = field(a, "session")
  let status = text(a, "status")
  let working = status == "running" || status == "queued"
  c.box(style=agent_card_box, fn() {
    // its mark (28) and label, a stop while it works
    c.box(style=agent_card_head, fn() {
      model_mark(c, agent, agent_card_mark)
      c.box(style=letters_grow, fn() { c.text(text(s, "agentText"), style=agent_card_name) |> ignore }) |> ignore
      if working {
        agent_card_stop(c, src, r.station, key)
      }
    })
    |> ignore
    // where it stands, after a dot in its tone, and for how long (three lines at most)
    c.box(style=agent_card_status, fn() {
      c.box(style=agent_card_dot_room, fn() {
        c.box(style=agent_card_dot.then(@ui.style(bg=tone_token(text(s, "tone")))), fn() {  }) |> ignore
      })
      |> ignore
      let since = agent_since(c, src, a)
      let runs = [@ui.span(text(s, "statusText"))]
      if since != "" {
        runs.push(@ui.span(" · " + since, color=t.p.muted))
      }
      c.rich(runs, style=agent_card_words) |> ignore
    })
    |> ignore
    // its latest lines, what it does now in the words' colour, running on as they change
    let latest = items(card, "latest")
    if latest.length() > 0 {
      agent_card_latest(c, latest)
    }
    agent_card_tiles(c, card)
    // its account, what is left of it to its right
    let account = match field(a, "account") {
      Some(Object(_)) as x => x
      _ => field(a, "profile")
    }
    let quota = field(field(a, "account"), "quota")
    let windows = if text(quota, "state") == "ok" { items(quota, "windows") } else { [] }
    if account is Some(_) || windows.length() > 0 {
      c.box(style=agent_card_account, fn() {
        c.box(style=letters_grow, fn() { c.text(text(account, "name"), style=agent_card_line) |> ignore }) |> ignore
        // each with what is left of it over it while it is pointed at, 4 apart
        if windows.length() > 0 {
          quota_chips(c, quota, small=true, gap=agent_card_chips_gap.px(), tip=fn(id, w) {
            let left = count(Some(w), "left").to_string()
            let label = text(Some(w), "label")
            let said = if label == "" {
              fill("web-main.quota.leftAlone", [("left", left)])
            } else {
              fill("web-main.quota.left", [("label", label), ("left", left)])
            }
            let refills = text(Some(w), "refills")
            wide_tip(c, "agent-card/quota/" + text(Some(w), "mark"), id, if refills == "" { said } else { said + "\n" + refills })
          })
        }
      })
      |> ignore
    }
    // the rest: a quiet line; its jobs and what is wrong
    let quiet = [text(card, "work"), text(card, "tokens")].filter(fn(x) { x != "" })
    if quiet.length() > 0 {
      c.text(quiet.join(" · "), style=agent_card_quiet) |> ignore
    }
    let attention = items(card, "attention")
    if text(card, "jobs") != "" || attention.length() > 0 {
      c.box(style=agent_card_notes, fn() {
        if text(card, "jobs") != "" {
          c.text(text(card, "jobs"), style=agent_card_line) |> ignore
        }
        for x in attention {
          let level = text(Some(x), "level")
          c.text(text(Some(x), "text"), style=if level == "red" {
            agent_card_red
          } else if level == "amber" {
            agent_card_amber
          } else {
            agent_card_line
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// An agent's card's latest lines, a line each, oldest first (AgentCard.tsx's list), running on as they change
/// (useLinesMotion): none resized, nor the list; those that stay go from where they were to where they are, carrying
/// on from wherever they had got to; a new one comes with them from beyond the edge, and one gone leaves with them, as
/// a copy; with none staying, new and gone fade in place. As they are the first time the card shows them.
fn agent_card_latest(c : @ui.Ctx, latest : Array[Json]) -> Unit {
  let keys = latest.map(fn(l) { text(Some(l), "key") })
  let frame = c.frame_number()
  let lid = c.id("agent-card/lines")
  let ran = match ran_lines.get(lid) {
    // drawn the frame before (or in this one's earlier build): what they were then
    Some(r) if r.frame >= frame - 1 => r
    _ => {
      let r = { keys: keys.copy(), words: {}, frame, pitch: 0.0, gone: [] }
      ran_lines[lid] = r
      // (as they are: none on its way from an opening before)
      for k in keys {
        line_y(c, k).snap(0.0)
        line_faint(c, k).snap(1.0)
      }
      r
    }
  }
  ran.frame = frame
  let spec = @motion.tween(lines_ms, ease=lines_ease)
  if ran.keys != keys {
    let before = ran.keys
    let at = fn(ks : Array[String], k : String) -> Int { ks.search(k).unwrap_or(-1) }
    // how far they ran on (the first that stays says): what comes and what goes moves as far
    let shift = match keys.iter().find_first(fn(k) { at(before, k) >= 0 }) {
      Some(k) => (at(before, k) - at(keys, k)).to_double() * ran.pitch
      None => 0.0
    }
    for i, k in keys {
      let y = line_y(c, k)
      let faint = line_faint(c, k)
      let j = at(before, k)
      // from where it was drawn (its place then, and how far it still was from it), as faint as it was
      let (from, f) = if j >= 0 { ((j - i).to_double() * ran.pitch + y.get(), faint.get()) } else { (shift, 0.0) }
      if from.abs() < 0.5 && f == 1.0 {
        continue
      }
      y.snap(from)
      y.animate(0.0, spec)
      faint.snap(f)
      faint.animate(1.0, spec)
    }
    // one gone: a copy of it where it was drawn, leaving as far as the others ran on
    for j, k in before {
      if at(keys, k) >= 0 {
        continue
      }
      let (y, f) = (line_y(c, k).get(), line_faint(c, k).get())
      let (words, now) = ran.words.get(k).unwrap_or(("", false))
      ran.gone.push({ key: k, words, now, top: j.to_double() * ran.pitch })
      let gy = gone_y(c, k)
      gy.snap(y)
      gy.animate(y - shift, spec)
      let gf = gone_faint(c, k)
      gf.snap(f)
      gf.animate(0.0, spec)
    }
    ran.keys = keys.copy()
  }
  // the copies gone out of sight let go
  ran.gone.retain(fn(g) { gone_faint(c, g.key).get() > 0.0 })
  c.box(style=agent_card_lines, fn() {
    for l in latest {
      let k = text(Some(l), "key")
      let now = flag(Some(l), "now")
      ran.words[k] = (text(Some(l), "text"), now)
      let id = c.id("agent-card/line/" + k)
      let n = c.box(style=agent_card_line_box, id~, taps=false, fn() {
        c.text(text(Some(l), "text"), style=if now { agent_card_now } else { agent_card_line }) |> ignore
      })
      let (y, f) = (line_y(c, k).get(), line_faint(c, k).get())
      if y != 0.0 || f != 1.0 {
        c.look(n, @ui.look(dy=y, alpha=f))
      }
      // how far apart they are as laid out: the steps of the next change
      match c.laid_size(id) {
        Some((_, h)) if h > 0.0 => ran.pitch = h + agent_card_lines_gap.px()
        _ => ()
      }
    }
    if ran.gone.length() > 0 {
      c.layer(fn() {
        for g in ran.gone {
          let n = c.box(style=agent_card_gone_box, fn() {
            c.text(g.words, style=if g.now { agent_card_now } else { agent_card_line }) |> ignore
          })
          c.look(n, @ui.look(dy=g.top + gone_y(c, g.key).get(), alpha=gone_faint(c, g.key).get()))
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The lines of an agent's card as last drawn (useLinesMotion's `was`), by its list: their keys in order, their
/// words, the frame they were drawn in (one not drawn the frame before is the card opened again: none moves), how far
/// apart they are, the copies of those gone, leaving.
priv struct RanLines {
  mut keys : Array[String]
  words : Map[String, (String, Bool)]
  mut frame : Int
  mut pitch : Double
  gone : Array[GoneLine]
}

///|
priv struct GoneLine {
  key : String
  words : String
  now : Bool
  top : Double
}

///|
let ran_lines : Map[Int, RanLines] = {}

///|
/// How long they take to run on, and how (AgentCard.tsx LINES_MS, LINES_EASE).
let lines_ms : Double = 240.0

///|
// kept across runs: a value (no field of it changes)
let lines_ease : @motion.Ease = Bezier(0.2, 0.7, 0.2, 1.0)

///|
/// A line's way from where it was drawn to its place, and how faint it is on it; a gone one's copy's.
fn line_y(c : @ui.Ctx, key : String) -> @motion.Anim {
  @motion.anim(c, "agent-card/line-y/" + key, 0.0)
}

///|
fn line_faint(c : @ui.Ctx, key : String) -> @motion.Anim {
  @motion.anim(c, "agent-card/line-faint/" + key, 1.0)
}

///|
fn gone_y(c : @ui.Ctx, key : String) -> @motion.Anim {
  @motion.anim(c, "agent-card/gone-y/" + key, 0.0)
}

///|
fn gone_faint(c : @ui.Ctx, key : String) -> @motion.Anim {
  @motion.anim(c, "agent-card/gone-faint/" + key, 0.0)
}

///|
/// Its mark's side (AgentCard.tsx AgentMark size).
let agent_card_mark : Double = 28.0

///|
/// A tone's colour as a style says it (AgentCard.css.ts status's dot: accent, green, blue, red, amber; else subtle).
fn tone_token(tone : String) -> @ui.Color {
  match tone {
    "accent" => Accent
    "green" => Positive
    "blue" => Link
    "red" => Danger
    "amber" | "warn" => Warn
    _ => Subtle
  }
}

///|
/// Stopping its turn, for it alone (AgentCard.css.ts stop): a pill 24 high, 10 in, the red's ground, its words 12.
fn agent_card_stop(c : @ui.Ctx, src : Source, station : String, key : String) -> Unit {
  let t = @sf.theme()
  let skey = "stop/" + station + "/" + key
  let busy = doing(skey)
  let id = c.id("agent-card/stop")
  c.cursor(id, Hand)
  if c.clicked(id) && !busy {
    act(
      src,
      tr("web-pages.chat.stop"),
      skey,
      "session.stop",
      { "station": Json::string(station), "key": Json::string(key) },
      done=tr("web-pages.chat.stopAsked"),
    )
  }
  c.box(style=agent_card_stop_pill, id~, fn() {
    if busy {
      @sf.spinner(c, size=11.0) |> ignore
    } else {
      @sf.icon(c, "stop", size=11.0, color=t.p.red) |> ignore
    }
    c.text(tr("web-pages.chat.stopTurn"), style=agent_card_stop_words) |> ignore
  })
  |> ignore
}

///|
/// The figures that say most (AgentCard.tsx UsageTiles), each large over its name, side by side: what it cost, the
/// cache's hit rate, how full its context is (in its level's colour). None before it has made a call.
fn agent_card_tiles(c : @ui.Ctx, card : Json?) -> Unit {
  let cost = text(card, "cost")
  let cache = field(card, "cache")
  let context = field(card, "context")
  if cost == "" && cache is None && context is None {
    return
  }
  let tile = fn(figure : String, name : String, level : String) {
    c.box(style=agent_card_tile, fn() {
      c.text(figure, style=if level == "red" {
        agent_card_figure_red
      } else if level == "amber" {
        agent_card_figure_amber
      } else {
        agent_card_figure
      })
      |> ignore
      c.text(name, style=agent_card_tile_name) |> ignore
    })
    |> ignore
  }
  c.box(style=agent_card_tiles_row, fn() {
    if cost != "" {
      tile(cost, tr("web-main.chat.agentCard.cost"), "")
    }
    match cache {
      Some(Object(_)) => tile(text(cache, "text"), tr("web-main.chat.agentCard.cache"), "")
      _ => ()
    }
    match context {
      Some(Object(_)) => {
        let unknown = flag(context, "unknown")
        let figure = if unknown {
          text(context, "text")
        } else {
          number(context, "percent").round().to_int().to_string() + "%"
        }
        tile(figure, tr("web-main.chat.agentCard.context"), if unknown { "" } else { text(context, "level") })
      }
      _ => ()
    }
  })
  |> ignore
}

///|
/// The card (agentCard: 288 wide), its parts 8 apart; its head's mark and name 10 apart.
// kept across runs: a value (no field of it changes)
let agent_card_box : @ui.Style = @ui.style(w=@sf.agent_card_w, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let agent_card_head : @ui.Style = @ui.style(row=true, w=Full, gap=S2_5, align=ACenter)

///|
/// Its name: the card's words (13), 500, cut at its end.
// kept across runs: a value (no field of it changes)
let agent_card_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
/// Where it stands: 14 in, its dot (6, in its tone) at the first line's middle.
// kept across runs: a value (no field of it changes)
let agent_card_status : @ui.Style = @ui.style(row=true, w=Full, gap=S1_5, align=AStart, pl=S0_5)

///|
// kept across runs: a value (no field of it changes)
let agent_card_dot_room : @ui.Style = @ui.style(pt=S1_5)

///|
// kept across runs: a value (no field of it changes)
let agent_card_dot : @ui.Style = @ui.style(w=S1_5, h=S1_5, radius=Full)

///|
// kept across runs: a value (no field of it changes)
let agent_card_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, w=Full, max_lines=3)

///|
/// Its latest lines: 14 in, 2 apart, 12, muted; what it does now in the words' colour; each one line.
// kept across runs: a value (no field of it changes)
let agent_card_lines : @ui.Style = @ui.style(w=Full, pl=S3_5, gap=agent_card_lines_gap, clip=true)

///|
// kept across runs: a value (no field of it changes)
let agent_card_lines_gap : @ui.Space = S0_5

///|
/// A line: as wide as the list, cut at its end; a gone one's copy over the list, at its padding.
// kept across runs: a value (no field of it changes)
let agent_card_line_box : @ui.Style = @ui.style(w=Full)

///|
// kept across runs: a value (no field of it changes)
let agent_card_gone_box : @ui.Style = @ui.style(w=Full, pl=S3_5)

///|
// kept across runs: a value (no field of it changes)
let agent_card_line : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_now : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_red : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_amber : @ui.TextStyle = @ui.text_style(size=Xs, color=Warn, wrap=false)

///|
/// The figures, side by side, 6 apart; each 7 by 9 in, 8 round, on the hover's ground: the figure 16 in 600 over its
/// name (11, muted).
// kept across runs: a value (no field of it changes)
let agent_card_tiles_row : @ui.Style = @ui.style(row=true, w=Full, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let agent_card_tile : @ui.Style = @ui.style(w=@sf.grow, py=@sf.files_row_end, px=S2, gap=SPx, radius=Lg, bg=Hover)

///|
// kept across runs: a value (no field of it changes)
let agent_card_figure : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_figure_red : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_figure_amber : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Warn, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_tile_name : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false)

///|
/// What is left of its account, its windows 4 apart.
// kept across runs: a value (no field of it changes)
let agent_card_chips_gap : @ui.Space = S1

///|
/// Its account (12), what is left of it to its right, 8 apart.
// kept across runs: a value (no field of it changes)
let agent_card_account : @ui.Style = @ui.style(row=true, w=Full, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let agent_card_quiet : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let agent_card_notes : @ui.Style = @ui.style(w=Full, gap=S0_5)

///|
/// Its stop: a pill 24 high, 10 in, 5 between its mark and words, on the red's ground.
// kept across runs: a value (no field of it changes)
let agent_card_stop_pill : @ui.Style = @ui.style(
  row=true,
  h=S6,
  px=S2_5,
  gap=S1_25,
  radius=Full,
  align=ACenter,
  bg=DangerBg,
  hovered=@ui.patch(bg=A(Danger, O20)),
)

///|
// kept across runs: a value (no field of it changes)
let agent_card_stop_words : @ui.TextStyle = @ui.text_style(size=Xs, weight=Medium, color=Danger, wrap=false)
