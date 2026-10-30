// A card over what the pointer rests on, as the web's (ember web/src/Peeks.tsx Hover, Hover.css.ts card, cardTile):
// opened once the pointer has rested on it 320 ms, closed 120 ms after it has left both it and the card; under it and
// at its start, 6 away, kept in the window; a small panel (the popover's: 6 in, what it holds 10 in more), 320 wide
// (`tile`: as wide as what it holds, 220 at least); it grows out of its edge from .96 and clear over 160 ms as it comes,
// and goes to .97 and clear over 90 ms (Hover.css.ts enter, exit: a card the pointer left, not one put away by a
// press, so not at once as a menu goes). And an agent's card
// (AgentCard.tsx, AgentCard.css.ts), the same over its picture beside its messages and over its mark in the chat's bar.

///|
/// `key`'s card over the trigger `trigger` (its id) while the pointer rests on it, holding `body`; to a finger, as it
/// holds the trigger, or with `tap` (a trigger that does nothing else) as it taps it (@kit.hover_card). Under it and at
/// its start, or on `side` lined up `along` it (beside the rail's places: their right, their tops); what it holds 10
/// in from its padding, or (`padded` false) at its padding, for rows to lie there (a station's card's ways on). Whether
/// it is open.
pub fn hover(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  tile? : Bool = false,
  tap? : Bool = false,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  padded? : Bool = true,
  body : () -> Unit,
) -> Bool {
  @kit.hover_card(
    c,
    key,
    trigger,
    tap~,
    held=hover_held(key),
    open_delay=hover_open_ms,
    close_delay=hover_close_ms,
    side~,
    along~,
    offset=hover_offset,
    enter=hover_in,
    exit=hover_out,
    look=fn(c, s, body) {
      c.box(style=if tile { hover_tile } else { hover_card }, fn() {
        @sf.small_panel(c, w=Fill(1.0), fn() {
          @sf.within_room(
            c,
            s,
            fn() {
              hover_now.val = Some((key, s.panel))
              body()
              hover_now.val = None
            },
            inner=if padded { hover_inner } else { hover_bare },
          )
        })
        |> ignore
      })
      |> ignore
    },
    body,
  )
}

///|
/// The card whose body is being built (its key, its panel's id); the cards kept open by what was pressed in them,
/// by their keys: what that opened (@sf.last_presented), while it is drawn.
let hover_now : Ref[(String, Int)?] = Ref(None)

///|
let hover_holds : Map[String, Int] = {}

///|
/// Whether card `key` is kept open by what was pressed in it.
fn hover_held(key : String) -> Bool {
  match hover_holds.get(key) {
    Some(serial) if @sf.presented_drawn_of(serial) => true
    Some(_) => {
      hover_holds.remove(key)
      false
    }
    None => false
  }
}

///|
/// Where what is pressed in the card being built opens (`id` pressed): beside the card, at its right, level with what
/// was pressed, so that both show; the card then kept open while it is (hover_hold).
fn hover_beside(c : @ui.Ctx, id : Int) -> @sf.Beside {
  let row = c.rect_of(id)
  let card = match hover_now.val {
    Some((_, panel)) => c.rect_of(panel)
    None => None
  }
  match (card, row) {
    (Some((x, _, w, _)), Some((_, y, _, _))) => At(x + w + hover_offset, y, 0.0, 0.0)
    (_, Some((x, y, w, h))) => At(x, y, w, h)
    _ => Of(id)
  }
}

///|
/// The card being built, where it is drawn (its panel), for a panel opened from it to stand at its right, their tops
/// level (what is pressed itself, where the card is not known).
fn hover_card_rect(c : @ui.Ctx, id : Int) -> @sf.Anchor {
  let card = match hover_now.val {
    Some((_, panel)) => c.rect_of(panel)
    None => None
  }
  match card {
    Some((x, y, w, h)) => At(x, y, w, h)
    None => Of(id)
  }
}

///|
/// The card being built kept open while what was just presented from it is.
fn hover_hold() -> Unit {
  match hover_now.val {
    Some((key, _)) => hover_holds[key] = @sf.last_presented()
    None => ()
  }
}

///|
/// Its delays (Radix's HoverCard as Peeks.tsx sets it), how far from what it is over, how small it starts.
pub let hover_open_ms : Double = 320.0

///|
pub let hover_close_ms : Double = 120.0

///|
let hover_offset : Double = 6.0

///|
// kept across runs: a value (no field of it changes)
let hover_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.96, spec=@motion.tween(160.0, ease=Out), ground_first=true)

///|
// kept across runs: a value (no field of it changes)
let hover_out : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, spec=@motion.tween(hover_out_ms, ease=Leave), ground_first=true)

///|
/// How long a card takes to go (hover_out).
let hover_out_ms : Double = 90.0

///|
/// Its width: 320; a tile's as wide as it holds, 220 at least, 420 at most (Hover.css.ts cardTile).
// kept across runs: a value (no field of it changes)
let hover_card : @ui.Style = @ui.style(w=@sf.hover_card_w)

///|
// kept across runs: a value (no field of it changes)
let hover_tile : @ui.Style = @ui.style(min_w=@sf.hover_tile_least, max_w=@sf.hover_tile_most)

///|
/// What it holds, 10 in from the panel's padding (controls.css.ts panelCard), 8 apart (Hover.css.ts card).
// kept across runs: a value (no field of it changes)
let hover_inner : @ui.Style = @ui.css("w=Full p=S2_5 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let hover_bare : @ui.Style = @ui.css("w=Full")

// ── an agent's card ──────────────────────────────────────────────────────

///|
/// One of the chat's agents in brief (AgentCard.tsx), `a` as chat `r`'s view has it: what it runs as, one thing (its
/// mark, its label, the account it runs on with what is left of it); where it stands and for how long, a stop for it
/// alone at its end while it works; its latest three lines; what it has going in the background and its checklist in a
/// line (agent_work_line); the figures that say most (UsageTiles); the rest in a quiet line; its jobs and what is
/// wrong. What the core says of it (the `agentCard` view) as it comes; the rest from the chat's agent at once.
/// What it says leads to where it is seen to: what it runs as (and an account that cannot run) to how it runs, its
/// lines to its execution history (at a line's entry), its context's figure to what can be done to it, its jobs to
/// the chat's. `across`: as wide as what holds it (with its station's card in a tile's, as wide as the wider), not its own
/// 288.
pub fn agent_card(c : @ui.Ctx, src : Source, r : ChatRef, a : Json, across? : Bool = false) -> Unit {
  let station = r.station
  let t = @sf.theme()
  let av = Some(a)
  let s = field(av, "session")
  let key = text(s, "key")
  let card = (src.topic)("agentCard", { "station": Json::string(station), "key": Json::string(key) }).value
  let status = text(av, "status")
  let working = status == "running" || status == "queued"
  let history = fn(entry : Int?) { open_page(History(r, key, entry)) }
  // how it runs, its picker beside what was pressed
  let runs = fn(id : Int) {
    open_triple_panel(src, station, "session:" + key, hover_card_rect(c, id), saved=@sf.t("web-pages.chat.pickSaved"), side=Right)
    hover_hold()
  }
  // its account, what is left of it
  let account = match field(av, "account") {
    Some(Object(_)) as x => x
    _ => field(av, "profile")
  }
  let quota = field(field(av, "account"), "quota")
  let windows = if text(quota, "state") == "ok" { items(quota, "windows") } else { [] }
  c.box(style=if across { agent_card_across } else { agent_card_box }, fn() {
    // what it runs as, one thing: its mark (28), its label (its model) on its line and under it the account it runs
    // on, what is left of it at that line's end; to how it runs (its model and its account are of that)
    let who = c.id("agent-card/runs")
    if c.clicked(who) {
      runs(who)
    }
    let w = c.box(style=agent_card_head, id=who, fn() {
      agent_mark(
        c,
        text(field(s, "maker"), "id"),
        text(s, "runtime"),
        text(av, "badge"),
        side=agent_card_mark,
        said=text(s, "badgeText"),
        ground=@sf.panel_ground(),
        // (in its ground's top left corner, 10 in: concentric with it there)
        corner=InnerOr(@sf.small_radius),
      )
      c.box(style=agent_card_who, fn() {
        c.text(text(s, "agentText"), style=agent_card_label) |> ignore
        if account is Some(_) || windows.length() > 0 {
          c.box(style=agent_card_account, fn() {
            c.box(style=agent_card_name_room, fn() {
              c.text(text(account, "name"), style=agent_card_line) |> ignore
            })
            |> ignore
            // each with what is left of it over it while it is pointed at (the chips' own tips), 4 apart
            if windows.length() > 0 {
              @sf.quota_chips(c, quota, small=true, marked=windows.length() > 1, gap=agent_card_chips_gap.px(), key="agent-card/quota")
            }
          })
          |> ignore
        }
      })
      |> ignore
    })
    c.semantics(w, Button, id=who, label=text(s, "agentText"))
    // where it stands, after a dot in its tone, and for how long (three lines at most); a stop at its end while it
    // works, what stopping is of (its working said short then: 进行中, 排队中)
    c.box(style=agent_card_stands, fn() {
      c.box(style=agent_card_status, fn() {
        c.box(style=agent_card_dot_room, fn() {
          c.box(style=agent_card_dot.then(@ui.style(bg=tone_token(text(s, "tone")))), fn() {  }) |> ignore
        })
        |> ignore
        let since = agent_waited(c, src, av)
        let runs = [@ui.span(text(s, "statusText"))]
        if since != "" {
          runs.push(@ui.span(" · " + since, color=t.p.muted))
        }
        c.rich(runs, style=agent_card_words) |> ignore
      })
      |> ignore
      if working {
        agent_card_stop(c, src, station, key)
      }
    })
    |> ignore
    // its latest lines, what it does now in the words' colour, running on as they change
    let latest = items(card, "latest")
    if latest.length() > 0 {
      agent_card_latest(c, latest, history)
    }
    // what it has going in the background and its checklist, in a line: to its execution history
    let work = c.id("agent-card/work")
    if c.clicked(work) {
      history(None)
    }
    agent_work_line(c, card, work, inset=true)
    if card is Some(Object(_)) {
      let compacts = flag(s, "canCompact")
      let entry : ContextEntry? = if compacts || flag(s, "canClear") {
        let busy = core_doing(src, context_calls, [("station", station), ("key", key)])
        Some({
          open: fn() {
            open_context_actions(src, station, key, s, hover_beside(c, context_tile_id(c)))
            hover_hold()
          },
          busy,
          compacts,
        })
      } else {
        None
      }
      usage_tiles(c, card, entry?=entry)
    }
    let quiet = [text(card, "work"), text(card, "tokens")].filter(fn(x) { x != "" })
    let attention = items(card, "attention")
    // the rest: a quiet line; its jobs and what is wrong
    if quiet.length() > 0 {
      c.text(quiet.join(" · "), style=agent_card_quiet) |> ignore
    }
    if text(card, "jobs") != "" || attention.length() > 0 {
      c.box(style=agent_card_notes, fn() {
        if text(card, "jobs") != "" {
          let id = c.id("agent-card/jobs")
          if c.clicked(id) {
            (@sfbase.chat_jobs_asked.val)(c, src, r)
          }
          agent_card_link(c, id, text(card, "jobs"), agent_card_line)
        }
        for i, x in attention {
          let level = text(Some(x), "level")
          let style = if level == "red" {
            agent_card_red
          } else if level == "amber" {
            agent_card_amber
          } else {
            agent_card_line
          }
          // an account that cannot run: to how it runs, to move it to another
          if text(Some(x), "kind") == "account" {
            let id = c.id("agent-card/attention/" + i.to_string())
            if c.clicked(id) {
              runs(id)
            }
            agent_card_link(c, id, text(Some(x), "text"), style, hot=style)
          } else {
            c.text(text(Some(x), "text"), style~) |> ignore
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// For how long it has stood where it does (AgentCard.tsx: Waited, Elapsed): waiting as long as it has (of at most),
/// else at work since its turn began; nothing else.
fn agent_waited(c : @ui.Ctx, src : Source, a : Json?) -> String {
  let now = (src.now)()
  let wait = field(a, "wait")
  match wait {
    Some(Object(_)) => {
      let from = number(wait, "since")
      match opt_number(wait, "seconds") {
        Some(sec) if sec > 0.0 => {
          // at its most it stands still
          if now - from < sec * second_ms {
            each_second(c, now - from)
          }
          let ran = if now < from + sec * second_ms { now - from } else { sec * second_ms }
          elapsed(ran) + " / " + elapsed(sec * second_ms)
        }
        _ => {
          each_second(c, now - from)
          elapsed(now - from)
        }
      }
    }
    _ =>
      match opt_number(a, "since") {
        Some(from) if from > 0.0 => {
          each_second(c, now - from)
          elapsed(now - from)
        }
        _ => ""
      }
  }
}

///|
/// An agent's card's latest lines, a line each, oldest first (AgentCard.tsx's list), running on as they change
/// (useLinesMotion): none resized, nor the list; those that stay go from where they were to where they are, carrying
/// on from wherever they had got to; a new one comes with them from beyond the edge, and one gone leaves with them, as
/// a copy; with none staying, new and gone fade in place. As they are the first time the card shows them.
fn agent_card_latest(c : @ui.Ctx, latest : Array[Json], history : (Int?) -> Unit) -> Unit {
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
      // each to where its history has it (what it does now: its newest), in the words' colour on hover
      if c.clicked(id) {
        history(line_entry(k))
      }
      let n = c.box(style=agent_card_line_box, id~, fn() {
        c.text(text(Some(l), "text"), style=if now || c.lit(id) { agent_card_now } else { agent_card_line }) |> ignore
      })
      c.semantics(n, Button, id~, label=text(Some(l), "text"))
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
  // (plain: what the build that shows these lines kept of them the frame before, read and written by it alone)
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
fn hover_reset() -> Unit {
  ran_lines.clear()
  hover_now.val = None
  hover_holds.clear()
}

///|
/// How long they take to run on, and how (AgentCard.tsx LINES_MS, LINES_EASE).
pub let lines_ms : Double = 240.0

///|
// kept across runs: a value (no field of it changes)
let lines_ease : @ui.Ease = Out

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
  let skey = "stop/" + station + "/" + key
  let busy = doing(skey)
  let id = c.id("agent-card/stop")
  if !busy && c.clicked(id) {
    act(
      src,
      @sf.t("web-pages.chat.stop"),
      skey,
      "session.stop",
      { "station": Json::string(station), "key": Json::string(key) },
      done=@sf.t("web-pages.chat.stopAsked"),
    )
  }
  c.box(style=agent_card_stop_pill, id~, fn() {
    if busy {
      @sf.spinner(c, size=11.0) |> ignore
    } else {
      @sf.icon(c, "stop", size=11.0, color=@sf.theme().p.red) |> ignore
    }
    c.text(@sf.t("web-pages.chat.stopTurn"), style=agent_card_stop_words) |> ignore
  })
  |> ignore
}

///|
/// The transcript entry of one of its latest lines, by its key (AgentCardLine): none for what it does now.
fn line_entry(key : String) -> Int? {
  if key == "now" {
    return None
  }
  let n = @string.parse_int(key[:]) catch { _ => return None }
  Some(n)
}

///|
/// Words of the card that lead somewhere (`id` pressed): in `style`, in `hot` on hover (muted ones the words' ink).
fn agent_card_link(c : @ui.Ctx, id : Int, words : String, style : @ui.TextStyle, hot? : @ui.TextStyle = agent_card_now) -> Unit {
  let b = c.box(style=agent_card_link_box, id~, fn() {
    c.text(words, style=if c.lit(id) { hot } else { style }) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
}

///|
/// What is under way of what can be done to a context.
// kept across runs: a value (no element of it changes)
let context_calls : Array[String] = ["session.compact", "session.clear"]

///|
/// What can be done to agent `key`'s context on `station` (useContextActions; `s` its session as its chat's view has
/// it), a menu beside `from`: 压缩上下文 at once, 清空上下文 (in red) asked first; neither while one is under way.
pub fn open_context_actions(src : Source, station : String, key : String, s : Json?, from : @sf.Beside) -> Unit {
  let params : Json = { "station": Json::string(station), "key": Json::string(key) }
  let busy = core_doing(src, context_calls, [("station", station), ("key", key)])
  let items : Array[@sf.MenuItem?] = []
  if flag(s, "canCompact") {
    items.push(
      Some(
        @sf.menu_item_of(
          @sf.t("web-pages.chat.compact"),
          fn() { act(src, @sf.t("web-pages.chat.compact"), "", "session.compact", params) },
          icon="shrink",
          disabled=busy,
        ),
      ),
    )
  }
  if flag(s, "canClear") {
    items.push(
      Some(
        @sf.menu_item_of(
          @sf.t("web-pages.chat.clear"),
          fn() {
            // asked as the web asks it (ChatPage.tsx: Confirm)
            @sf.confirm(
              @sf.t("web-pages.chat.clearConfirm"),
              @sf.t("web-pages.chat.clearBody"),
              @sf.t("web-pages.chat.clear"),
              danger=true,
              fn() { act(src, @sf.t("web-pages.chat.clear"), "", "session.clear", params) },
            )
          },
          icon="refresh",
          danger=true,
          disabled=busy,
        ),
      ),
    )
  }
  if items.length() > 0 {
    @sf.menu(items, from~)
  }
}

///|
/// What can be done to an agent's context from its tile (AgentCard.tsx ContextEntry: its execution history's details):
/// its menu opened, something under way, whether it can be compacted.
pub(all) struct ContextEntry {
  open : () -> Unit
  busy : Bool
  compacts : Bool
}

///|
/// The id of the context's tile that opens what can be done to it (its menu's anchor).
pub fn context_tile_id(c : @ui.Ctx) -> Int {
  c.id("agent/context-tile")
}

///|
/// The figures that say most of what an agent used (AgentCard.tsx UsageTiles), each large over its name, side by
/// side: what it cost, the cache's hit rate, how full its context is (in its level's colour, how much of how much on
/// hover). With `entry`, its context's tile opens what can be done to it, its name ending in › (that it can be
/// compacted said once it is filling up), a spinner while something is under way. None before it has made a call.
pub fn usage_tiles(c : @ui.Ctx, card : Json?, entry? : ContextEntry) -> Unit {
  let cost = text(card, "cost")
  let cache = field(card, "cache")
  let context = field(card, "context")
  if cost == "" && cache is None && context is None {
    return
  }
  let tile = fn(id : Int, figure : String, name : () -> Unit, level : String) -> Int {
    c.box(style=if id != 0 { agent_card_tile_button } else { agent_card_tile }, id~, fn() {
      c.text(figure, style=if level == "red" {
        agent_card_figure_red
      } else if level == "amber" {
        agent_card_figure_amber
      } else {
        agent_card_figure
      })
      |> ignore
      name()
    })
  }
  let named = fn(words : String) { fn() { c.text(words, style=agent_card_tile_name) |> ignore } }
  c.box(style=agent_card_tiles_row, fn() {
    if cost != "" {
      tile(0, cost, named(@sf.t("web-main.chat.agentCard.cost")), "") |> ignore
    }
    match cache {
      Some(Object(_)) => tile(0, text(cache, "text"), named(@sf.t("web-main.chat.agentCard.cache")), "") |> ignore
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
        let level = if unknown { "" } else { text(context, "level") }
        match entry {
          Some(e) => {
            let id = context_tile_id(c)
            if !e.busy && c.clicked(id) {
              (e.open)()
            }
            let filling = e.compacts && (level == "amber" || level == "red")
            let b = tile(
              id,
              figure,
              fn() {
                c.box(style=agent_card_tile_more, fn() {
                  c.text(
                    if filling {
                      @sf.t("web-mobile.agent.contextCompactable")
                    } else {
                      @sf.t("web-main.chat.agentCard.context")
                    },
                    style=agent_card_tile_name,
                  )
                  |> ignore
                  if e.busy {
                    @sf.spinner(c, size=11.0) |> ignore
                  } else {
                    @sf.icon(c, "chevron-right", size=11.0, color=@sf.theme().p.muted) |> ignore
                  }
                })
                |> ignore
              },
              level,
            )
            c.semantics(b, Button, id~, label=@sf.t("web-pages.chat.contextActions"))
          }
          None => {
            let id = if unknown { 0 } else { c.id("agent-card/context") }
            if unknown {
              tile(0, figure, named(@sf.t("web-main.chat.agentCard.context")), level) |> ignore
            } else {
              c.box(style=agent_card_tile_room, id~, fn() {
                tile(0, figure, named(@sf.t("web-main.chat.agentCard.context")), level) |> ignore
              })
              |> ignore
              @sf.tip(c, "agent-card/context", id, text(context, "text"))
            }
          }
        }
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
let agent_card_across : @ui.Style = @ui.style(w=Full, min_w=@sf.agent_card_w, gap=S2)

///|
/// Its head: a small panel's row (presenters' small_panel_row_in), its ground under the hand, concentric with the
/// card's corners.
// kept across runs: a value (no field of it changes)
let agent_card_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStart p=S2_5 radius=Inner hovered{bg=Hover}")
  .then(@ui.style(mt=@sf.room_of(-agent_card_head_out), mx=@sf.room_of(-agent_card_head_out)))

///|
/// How far its head reaches out past the card's words (hover_inner's 10) to be a small panel's row, its ground under
/// the hand at the panel's padding (6 from its edges), its words text_in in from it, where they were.
let agent_card_head_out : Double = @sf.text_in

///|
/// Its label and its account's line under it: what its mark leaves of the head.
// kept across runs: a value (no field of it changes)
let agent_card_who : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its label on its mark's line, 28 (L7: its mark's side; the mark in the card's corner, by its first line as a
/// two-line item's).
// kept across runs: a value (no field of it changes)
let agent_card_label : @ui.TextStyle = agent_card_name.then(@ui.text_style(leading=L7))

///|
/// Its name and its account's room: what is left of the row.
// kept across runs: a value (no field of it changes)
let agent_card_name_room : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its name: the card's words (13), 500, cut at its end.
// kept across runs: a value (no field of it changes)
let agent_card_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// Where it stands and its stop, on one line: its words what the stop leaves.
// kept across runs: a value (no field of it changes)
let agent_card_stands : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
/// Where it stands: 14 in, its dot (6, in its tone) at the first line's middle.
// kept across runs: a value (no field of it changes)
let agent_card_status : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=AStart, pl=S0_5)

///|
// kept across runs: a value (no field of it changes)
let agent_card_dot_room : @ui.Style = @ui.css("pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let agent_card_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let agent_card_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full, max_lines=3)

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
let agent_card_line_box : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let agent_card_gone_box : @ui.Style = @ui.css("w=Full pl=S3_5")

///|
// kept across runs: a value (no field of it changes)
let agent_card_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_now : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_red : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_amber : @ui.TextStyle = @ui.text_style(size=Meta, color=WarnInk, wrap=false)

///|
/// The figures, side by side, 6 apart; each 7 by 9 in, 8 round, on the hover's ground: the figure 16 in 600 over its
/// name (11, muted).
// kept across runs: a value (no field of it changes)
let agent_card_tiles_row : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let agent_card_tile : @ui.Style = @ui.style(w=@sf.grow, py=@sf.files_row_end, px=S2, gap=SPx, radius=Lg, bg=Hover)

///|
/// The context's tile when something can be done to it: the pointer's ground over its own on hover, its name ending
/// in › 2 after.
// kept across runs: a value (no field of it changes)
let agent_card_tile_button : @ui.Style = agent_card_tile.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let agent_card_tile_more : @ui.Style = @ui.css("row gap=SPx align=ACenter")

///|
/// The context's tile with its tip, sharing the row as the others do.
// kept across runs: a value (no field of it changes)
let agent_card_tile_room : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let agent_card_figure : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_figure_red : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_figure_amber : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=WarnInk, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let agent_card_tile_name : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// What is left of its account, its windows 4 apart.
// kept across runs: a value (no field of it changes)
let agent_card_chips_gap : @ui.Space = S1

///|
/// Its account (12) under its label, what is left of it at that line's end, 8 apart: the head's last line, what is
/// left (capsules) in its ground's bottom right corner as far from both its edges as makes them concentric with it
/// (@sf.capsule_in), out past the head's padding (text_in) to there, its words on their foot.
// kept across runs: a value (no field of it changes)
let agent_card_account : @ui.Style = @ui.css("row w=Full gap=S2 align=AEnd").then(
  @ui.style(mb=@sf.room_of(agent_card_chips_in), mr=@sf.room_of(agent_card_chips_in)),
)

///|
let agent_card_chips_in : Double = @sf.capsule_in(@sf.row_corner, @sf.fill_chip_small_h) - @sf.text_in

///|
/// Words that lead somewhere: their whole line.
// kept across runs: a value (no field of it changes)
let agent_card_link_box : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let agent_card_quiet : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let agent_card_notes : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its stop: a pill 24 high, 10 in, 5 between its mark and words, on the red's ground.
// kept across runs: a value (no field of it changes)
let agent_card_stop_pill : @ui.Style = @ui.css(
  #|row h=S6 px=S2_5 gap=S1_25 radius=Full align=ACenter bg=DangerBg hovered{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let agent_card_stop_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Danger, wrap=false)
