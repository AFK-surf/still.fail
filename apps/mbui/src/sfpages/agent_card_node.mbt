// One of a chat's agents in brief (hover.mbt's agent_card) as nodes of the window's tree, made once in a hover card
// (@sf.hover_card_node): what it shows and how, the same as that; what it reads the same (the chat's agent as the
// chat's view has it, the core's `agentCard` view of it). What is pressed in it opens beside the card (`from`: its
// card, Node(card)), and says whether what it opened is presented now (the card kept open meanwhile: the hover card's
// `held`). Where they differ: its latest lines run on as they change by one way of their box (agent_card_lines_run),
// not each line on a way of its own; what can be done to its context opens beside its figure (usage_tiles_node's),
// not at the card's right.

///|
/// Agent `key` of chat `r` in `v` (agent_card's): what it runs as (its mark, its label, the account it runs on and what
/// is left of it), pressed how it runs, beside the card; where it stands and for how long, a stop for its turn alone
/// while it works; its latest lines, each to its history; what it has going in the background; its figures (its
/// context's to what can be done to it); a quiet line; its jobs and what is wrong (an account that cannot run, to how it
/// runs). `tips`: the window's tips; `from`: what is opened from it stands beside (its card while it is made);
/// `across`: as wide as what holds it (with its station's part, in a tile), not its own 288. Whether what it opened is
/// presented now (followed).
pub fn agent_card_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  key : String,
  tips : @sf.TipLayer,
  from : () -> @view.View?,
  across? : Bool = false,
) -> () -> Bool {
  let station = r.station
  let chat = src.topic("chat", chat_params(r))
  let card_topic = src.topic("agentCard", { "station": Json::string(station), "key": Json::string(key) })
  let a = fn() { agent_json(chat.get().value, key) }
  let s = fn() { field(a(), "session") }
  let card = fn() { card_topic.get().value }
  // (what was last opened from it, while it is presented: the card kept open)
  let opened : @signals.Signal[@sf.Anchor?] = @signals.signal(None, same=fn(x, y) { x == y })
  let held = fn() {
    match opened.get() {
      Some(at) => @sf.presented_from(at)
      None => false
    }
  }
  let history = fn(entry : Int?) { open_page(History(r, key, entry)) }
  // (how it runs, its picker beside the card, their tops level)
  let runs = fn() {
    guard @signals.untracked(from) is Some(c) else { return }
    let at : @sf.Anchor = Node(c)
    open_triple_panel(src, station, "session:" + key, at, saved=@sf.t("web-pages.chat.pickSaved"), side=Right)
    opened.set(Some(at))
  }
  v.box(fn(b) {
    @sf.style_node(b, fn() { if across { agent_card_across } else { agent_card_box } })
    agent_card_head_node(b, a, s, tips, runs)
    agent_card_stands_node(b, src, station, key, a, s, tips)
    // its latest lines, what it does now in the words' colour, running on as they change (agent_card_lines_run)
    b.show(fn() { items(card(), "latest").length() > 0 }, fn(x) {
      x.box(fn(l) {
        @sf.style_node(l, fn() { agent_card_lines })
        let run = agent_card_lines_run(l, fn() { items(card(), "latest") })
        l.each(at_once=true, fn() { items(card(), "latest") }, fn(line) { text(Some(line), "key") }, fn(row, line) {
          let k = text(Some(line.untracked()), "key")
          row.box(fn(n) {
            @sf.style_node(n, fn() { agent_card_line_box })
            run.line(n, k)
            @sf.presses_node(n, fn() { history(line_entry(k)) })
            n.says(By(fn() { Some(@view.said(Button, label=text(Some(line.get()), "text"))) })) |> ignore
            @sf.words_node(n, fn() { text(Some(line.get()), "text") }, fn() {
              if flag(Some(line.get()), "now") || @sf.lit_node(n) {
                agent_card_now
              } else {
                agent_card_line
              }
            })
            |> ignore
          })
          |> ignore
        })
        run.gone(l)
      })
      |> ignore
    })
    // what it has going in the background and its checklist, in a line: to its execution history
    b.show(fn() { text(card(), "workLine") != "" }, fn(x) {
      @sf.style_node(x, fn() { work_line_inset })
      @sf.presses_node(x, fn() { history(None) })
      x.says(By(fn() { Some(@view.said(Button, label=text(card(), "workLine"))) })) |> ignore
      @sf.words_node(x, fn() { text(card(), "workLine") }, fn() {
        if @sf.lit_node(x) {
          work_line_hot
        } else {
          work_line_words
        }
      })
      |> ignore
    })
    // the figures that say most (its context's to what can be done to it)
    b.show(
      fn() {
        card() is Some(Object(_)) &&
        (text(card(), "cost") != "" || field(card(), "cache") is Some(_) || field(card(), "context") is Some(_))
      },
      fn(x) {
        x.pick(fn() { flag(s(), "canCompact") || flag(s(), "canClear") }, fn(y, can) {
          if can {
            usage_tiles_node(
              y,
              card,
              tips,
              context=fn(at) {
                open_context_actions(src, station, key, @signals.untracked(s), at)
                opened.set(Some(at.anchor()))
              },
              busy=fn() { core_doing(src, context_calls, [("station", station), ("key", key)]) },
              compacts=fn() { flag(s(), "canCompact") },
            )
          } else {
            usage_tiles_node(y, card, tips)
          }
        })
      },
    )
    // the rest: a quiet line; its jobs and what is wrong
    let quiet = fn() { [text(card(), "work"), text(card(), "tokens")].filter(fn(q) { q != "" }) }
    b.show(fn() { quiet().length() > 0 }, fn(x) {
      @sf.words_node(x, fn() { quiet().join(" · ") }, fn() { agent_card_quiet }) |> ignore
    })
    b.show(fn() { text(card(), "jobs") != "" || items(card(), "attention").length() > 0 }, fn(x) {
      @sf.style_node(x, fn() { agent_card_notes })
      x.show(fn() { text(card(), "jobs") != "" }, fn(j) {
        agent_card_link_node(j, fn() { text(card(), "jobs") }, fn() { agent_card_action }, fn() { agent_card_action }, fn() {
          (@sfbase.chat_jobs_open.val)(src, r, j.window().0)
        })
      })
      x.each(fn() { Array::makei(items(card(), "attention").length(), fn(i) { i }) }, fn(i) { i }, fn(row, i) {
        let at = i.untracked()
        let one = fn() { items(card(), "attention").get(at) }
        let style = fn() {
          match text(one(), "level") {
            "red" => agent_card_red
            "amber" => agent_card_amber
            _ => agent_card_line
          }
        }
        // (an account that cannot run: to how it runs, to move it to another)
        row.pick(fn() { text(one(), "kind") == "account" }, fn(p, account) {
          if account {
            agent_card_link_node(p, fn() { text(one(), "text") }, style, style, runs)
          } else {
            @sf.words_node(p, fn() { text(one(), "text") }, style) |> ignore
          }
        })
      })
    })
  })
  |> ignore
  held
}

///|
/// Its head in `p` (agent_card's): its mark (28) in the head's ground's top left corner, its label on its line and the
/// account it runs on under it with what is left of it; a small panel's row, pressed how it runs (`runs`).
fn agent_card_head_node(
  p : @view.View,
  a : () -> Json?,
  s : () -> Json?,
  tips : @sf.TipLayer,
  runs : () -> Unit,
) -> Unit {
  let account = fn() {
    match field(a(), "account") {
      Some(Object(_)) as x => x
      _ => field(a(), "profile")
    }
  }
  let quota = fn() { field(field(a(), "account"), "quota") }
  let windows = fn() { if text(quota(), "state") == "ok" { items(quota(), "windows") } else { [] } }
  p.box(fn(h) {
    // (its corners concentric with the card's, its ground the small panel's row's: agent_card_head's Inner)
    @sf.style_node(h, fn() { agent_card_head.then(agent_card_head_round) })
    @sf.presses_node(h, runs)
    h.says(By(fn() { Some(@view.said(Button, label=text(s(), "agentText"))) })) |> ignore
    agent_card_mark_node(h, a, s)
    h.box(fn(w) {
      @sf.style_node(w, fn() { agent_card_who }, in_row=true)
      @sf.words_node(w, fn() { text(s(), "agentText") }, fn() { agent_card_label }) |> ignore
      w.show(fn() { account() is Some(_) || windows().length() > 0 }, fn(x) {
        // (beside its account's name where the line has the room for both whole; else under it, at the line's end)
        x.box(fn(ways) {
          @sf.style_node(ways, fn() { agent_card_account_ways })
          ways.one_of(Is(true)) |> ignore
          let chips = fn(c : @view.View) {
            c.show(fn() { windows().length() > 0 }, fn(q) {
              q.pick(fn() { windows().length() > 1 }, fn(m, marked) {
                @sf.quota_chips_node(m, quota, small=true, marked~, gap=agent_card_chips_gap.px(), tips~, tips_within=true)
              })
            })
          }
          ways.box(fn(o) {
            @sf.style_node(o, fn() { agent_card_account }, in_row=true)
            o.box(fn(n) {
              @sf.style_node(n, fn() { agent_card_name_room }, in_row=true)
              @sf.words_node(n, fn() { text(account(), "name") }, fn() { agent_card_line }) |> ignore
            })
            |> ignore
            chips(o)
          })
          |> ignore
          ways.box(fn(o) {
            @sf.style_node(o, fn() { agent_card_account_under }, in_row=true)
            o.box(fn(n) {
              @sf.style_node(n, fn() { agent_card_line_box })
              // (as wide as its words, cut only where the card is narrower: Ctx::text's w=Cut)
              n.lines_up(Is(Some(Start))) |> ignore
              @sf.words_node(n, fn() { text(account(), "name") }, fn() { agent_card_line_cut }) |> ignore
            })
            |> ignore
            chips(o)
          })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// Its head's corners: concentric with the card's where it reaches out to the card's padding (the small panel's
/// row's: r_menu less the panel's padding).
// kept across runs: a value (no field of it changes)
let agent_card_head_round : @ui.Style = @ui.style(radius=@sf.row_radius)

///|
/// Its mark (agent_mark's, 28): its model's maker on a tile of the neutral ground, round as a block within its head's
/// corner (InnerOr: the ladder's small block's), its badge at its corner ringed in the panel's ground.
fn agent_card_mark_node(p : @view.View, a : () -> Json?, s : () -> Json?) -> Unit {
  let side = agent_card_mark
  p.box(fn(t) {
    @sf.style_node(t, fn() { agent_tile.then(agent_card_mark_tile) }, in_row=true)
    t.shrink(Is(0.0)) |> ignore
    t.says(By(fn() {
      match text(s(), "badgeText") {
        "" => None
        said => Some(@view.said(Image, label=said))
      }
    }))
    |> ignore
    t.pick(fn() { (text(field(s(), "maker"), "id"), text(s(), "runtime")) }, fn(m, k) {
      @sf.maker_mark_node(m, k.0, k.1, (side * agent_logo_of).round()) |> ignore
    })
    // (over the tile, as large as it: the badge at its corner)
    t.pick(fn() { text(a(), "badge") }, fn(b, badge) {
      b.over(Is(true)).width(Is(Some(side))).height(Is(Some(side))) |> ignore
      agent_badge_ground_node(b, badge, side, fn() { @sf.panel_ground() })
    })
  })
  |> ignore
}

///|
/// Its mark's tile: 28 across, round as the ladder's small block.
// kept across runs: a value (no field of it changes)
let agent_card_mark_tile : @ui.Style = @ui.style(w=Fixed(agent_card_mark), h=Fixed(agent_card_mark), radius=@sf.small_radius)

///|
/// The badge at the corner of an agent's mark `side` across (agent_badge's, as nodes) in `v`, ringed in `ground`: a dot
/// blue waiting on a person, red failed; yellow spokes at work; none else.
fn agent_badge_ground_node(v : @view.View, badge : String, side : Double, ground : () -> Int64) -> Unit {
  let k = dmin(side / agent_badge_full, 1.0)
  match badge {
    "block" | "failed" => {
      let d = agent_badge_d * k
      let at = side - d + agent_badge_past * k
      let ring = agent_badge_ring * k
      v.box(fn(r) {
        r
        .over(Is(true))
        .width(Is(Some(d)))
        .height(Is(Some(d)))
        .offset(Is((at, at)))
        .radius(Is(d / 2.0))
        .padding(Is((ring, ring, ring, ring)))
        .ground(By(ground))
        |> ignore
        r.box(fn(dot) {
          let ink = if badge == "block" { @sf.mark_blue } else { @sf.mark_red }
          dot.grow(Is(1.0)).radius(Is(d / 2.0)).ground(By(fn() { @ui.tree_theme().color(ink) })) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    "run" => {
      let d = agent_spokes * k
      let at = side - d + agent_spokes_past * k
      v.box(fn(r) {
        r.over(Is(true)).width(Is(Some(d))).height(Is(Some(d))).offset(Is((at, at))) |> ignore
        @sf.spokes_node(r, d, fn() { @sf.mark_yellow }) |> ignore
      })
      |> ignore
    }
    _ => ()
  }
}

///|
/// Where it stands in `p` (agent_card's): a dot in its tone, its words and for how long (agent_waited's, each whole
/// second as it is shown), three lines at most; a stop at their first line's end while it works.
fn agent_card_stands_node(
  p : @view.View,
  src : Source,
  station : String,
  key : String,
  a : () -> Json?,
  s : () -> Json?,
  tips : @sf.TipLayer,
) -> Unit {
  let status = fn() { text(a(), "status") }
  let working = fn() { status() == "running" || status() == "queued" }
  p.box(fn(row) {
    @sf.style_node(row, fn() { agent_card_stands })
    row.box(fn(st) {
      @sf.style_node(st, fn() { agent_card_status }, in_row=true)
      st.box(fn(d) {
        @sf.style_node(d, fn() { agent_card_dot_room })
        d.box(fn(dot) {
          @sf.style_node(dot, fn() { agent_card_dot.then(@ui.style(bg=tone_token(text(s(), "tone")))) })
        })
        |> ignore
      })
      |> ignore
      let tick = agent_card_seconds(st, src, fn() { agent_wait_of(a()) })
      st.box(fn(w) {
        w
        .words_runs(By(fn() {
          tick() |> ignore
          let since = agent_waited_words((src.now)(), a())
          let t = @sf.theme()
          let runs = [@ui.span(text(s(), "statusText"))]
          if since != "" {
            runs.push(@ui.span(" · " + since, color=t.p.muted))
          }
          runs
        }))
        .words_look(By(fn() { @ui.style_words(agent_card_words) }))
        .ink(By(fn() { @ui.style_ink(agent_card_words) }))
        |> ignore
        @sf.style_node(w, fn() { agent_card_words_room }, in_row=true)
      })
      |> ignore
    })
    |> ignore
    row.show(working, fn(x) { agent_card_stop_node(x, src, station, key, tips) })
  })
  |> ignore
}

///|
/// Its words' room in where it stands: what the dot leaves (agent_card_words' w=Full).
// kept across runs: a value (no field of it changes)
let agent_card_words_room : @ui.Style = @ui.css("w=Full")

///|
/// Since when it stands where it does and for how long at most (agent_waited's): waiting, from when (of at most so
/// long); else at work since its turn began; none else.
fn agent_wait_of(a : Json?) -> (Double, Double?)? {
  let wait = field(a, "wait")
  match wait {
    Some(Object(_)) =>
      Some(
        (
          number(wait, "since"),
          match opt_number(wait, "seconds") {
            Some(sec) if sec > 0.0 => Some(sec * second_ms)
            _ => None
          },
        ),
      )
    _ =>
      match opt_number(a, "since") {
        Some(from) if from > 0.0 => Some((from, None))
        _ => None
      }
  }
}

///|
/// For how long it has stood where it does at `now` (agent_waited's words): waiting as long as it has (of at most),
/// else at work since its turn began; nothing else.
fn agent_waited_words(now : Double, a : Json?) -> String {
  match agent_wait_of(a) {
    Some((from, Some(most))) => {
      let ran = if now < from + most { now - from } else { most }
      elapsed(ran) + " / " + elapsed(most)
    }
    Some((from, None)) => elapsed(now - from)
    None => ""
  }
}

///|
/// A clock in `v` for how long it has stood where it does (`since`: from when, at most how long), read again each whole
/// second from then (steps_seconds', on the page's time), till its most; begun again as `since` says another.
fn agent_card_seconds(v : @view.View, src : Source, since : () -> (Double, Double?)?) -> () -> Int {
  let tick : @signals.Signal[Int] = @signals.signal(0)
  let stop : Ref[() -> Unit] = Ref(fn() {  })
  fn plan(from : Double, most : Double?) -> Unit {
    let gone = (src.now)() - from
    if most is Some(m) && gone >= m {
      return
    }
    let into = if gone > 0.0 { gone - (gone / second_ms).floor() * second_ms } else { gone }
    stop.val = v.at_moment(v.logic_at() + second_ms - into, later=true, fn() {
      tick.set(tick.untracked() + 1)
      plan(from, most)
    })
  }

  v.reacts(since, fn(k) {
    (stop.val)()
    stop.val = fn() {  }
    match k {
      Some((from, most)) => plan(from, most)
      None => ()
    }
  })
  fn() { tick.get() }
}

///|
/// Stopping its turn, for it alone (agent_card_stop's) in `p`: its icon in the red on the red's ground, a circle, what
/// it does in its tip; a spinner in its place while asked.
fn agent_card_stop_node(p : @view.View, src : Source, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let skey = "stop/" + station + "/" + key
  let label = fn() { @sf.t("web-pages.chat.stopTurn") }
  p.box(fn(b) {
    @sf.style_node(b, fn() { agent_card_stop_box }, in_row=true)
    @sf.presses_node(b, fn() {
      if !doing(skey) {
        act(
          src,
          @sf.t("web-pages.chat.stop"),
          skey,
          "session.stop",
          { "station": Json::string(station), "key": Json::string(key) },
          done=@sf.t("web-pages.chat.stopAsked"),
        )
      }
    })
    b.says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    @sf.tip_node(tips, b, label) |> ignore
    b.pick(fn() { doing(skey) }, fn(i, busy) {
      if busy {
        @sf.spinner_node(i, size=agent_card_stop_icon) |> ignore
      } else {
        @sf.icon_node(i, "stop", agent_card_stop_icon, By(fn() { @sf.theme().p.red })) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// Words of the card that lead somewhere (agent_card_link's) in `p`: in `style`, in `hot` under the hand; `press`.
fn agent_card_link_node(
  p : @view.View,
  words : () -> String,
  style : () -> @ui.TextStyle,
  hot : () -> @ui.TextStyle,
  press : () -> Unit,
) -> Unit {
  p.box(fn(b) {
    @sf.style_node(b, fn() { agent_card_link_box })
    @sf.presses_node(b, press)
    b.says(By(fn() { Some(@view.said(Button, label=words())) })) |> ignore
    @sf.words_node(b, words, fn() { if @sf.lit_node(b) { hot() } else { style() } }) |> ignore
  })
  |> ignore
}

///|
/// How an agent's card's latest lines run on as they change while it shows (as nodes: its lines' box, made once, the
/// lines its each's, there at once, each drawn off where it is laid by one way of the box): those that stay go from
/// where they were drawn to where they are laid, carrying on from wherever they had got to, a new one coming with them
/// from beyond the last and fading in, one gone leaving with them as a copy over the box, fading out, the box cutting
/// what runs past its edges; with none staying, new and gone fade in place. Nothing resized: the box is as tall as its
/// lines, the copies over it taking no room. Its cause the lines' keys changed from some to others; as the box is made
/// (the card opened, or come into sight) or its first lines come, they are as they are, nothing moving.
priv struct LinesRun {
  /// (how far the lines still have to run, as a share of `steps`: 1 as they set out, 0 at rest)
  way : @motion.Way
  /// (how many lines they run on by, from where they were drawn as the way set out)
  steps : @signals.Signal[Double]
  /// (the lines come by a change, each fading in by its way; those that stay keep theirs)
  fades : @signals.Signal[Map[String, @motion.Way]]
  /// (the copies of those gone, leaving)
  gone : @signals.Signal[Array[LinesGone]]
}

///|
/// A line gone, leaving as a copy over its box: its key, words and whether it was what the agent does now; where it is
/// drawn at rest of the run (in lines from the box's top: `base` plus how far the run still has to go); its fading.
priv struct LinesGone {
  key : String
  words : String
  now : Bool
  base : Double
  fade : @motion.Way
}

///|
/// The run of the lines `latest` gives in their box `l`, set off by each change of their keys at its moment.
fn agent_card_lines_run(l : @view.View, latest : () -> Array[Json]) -> LinesRun {
  let run : LinesRun = {
    way: @motion.Way::new(0.0),
    steps: @signals.signal(0.0),
    fades: @signals.signal(Map([]), same=fn(_, _) { false }),
    gone: @signals.signal([], same=fn(_, _) { false }),
  }
  // (the lines as they were last: their keys, words and whether each is what it does now)
  let was : Ref[Array[(String, String, Bool)]] = Ref([])
  let said = fn() {
    latest().map(fn(x) { (text(Some(x), "key"), text(Some(x), "text"), flag(Some(x), "now")) })
  }
  l.reacts(fn() { said().map(fn(s) { s.0 }) }, fn(keys) {
    let before = was.val
    was.val = @signals.untracked(said)
    let old = before.map(fn(s) { s.0 })
    // (as the box is made, its first lines come, or with the same lines: as they are)
    if old.length() == 0 || old == keys {
      return
    }
    let at = l.cause_at()
    let ix = fn(ks : Array[String], k : String) -> Int { ks.search(k).unwrap_or(-1) }
    // (how far they run on: as far as the first that stays moved; and how far they still had to go)
    let shift = match keys.iter().find_first(fn(k) { ix(old, k) >= 0 }) {
      Some(k) => (ix(old, k) - ix(keys, k)).to_double()
      None => 0.0
    }
    let still = run.way.value_at(at) * run.steps.untracked()
    let spec = @motion.tween(lines_ms, ease=lines_ease)
    let fades : Map[String, @motion.Way] = Map([])
    for k in keys {
      match (ix(old, k), run.fades.untracked().get(k)) {
        (j, Some(f)) if j >= 0 => fades[k] = f
        (j, _) if j >= 0 => ()
        _ => {
          let f = @motion.Way::new(0.0)
          f.go(1.0, spec, at~)
          fades[k] = f
        }
      }
    }
    // (the copies still leaving go on from where they are drawn; one more for each gone now, where it was drawn)
    let gone = run.gone
      .untracked()
      .filter(fn(g) { ix(keys, g.key) < 0 })
      .map(fn(g) { { ..g, base: g.base - shift } })
    for j, s in before {
      if ix(keys, s.0) < 0 && !gone.iter().any(fn(g) { g.key == s.0 }) {
        let fade = @motion.Way::new(1.0)
        fade.go(0.0, spec, at~)
        gone.push({ key: s.0, words: s.1, now: s.2, base: j.to_double() - shift, fade })
      }
    }
    run.steps.set(shift + still)
    run.way.put(1.0)
    run.way.go(0.0, spec, at~)
    run.fades.set(fades)
    run.gone.set(gone)
    // (the copies let go as they have faded)
    l.at_moment(run.way.end(), fn() {
      let now = l.logic_at()
      run.gone.set(run.gone.untracked().filter(fn(g) { g.fade.goes_at(now) }))
    })
    |> ignore
  })
  run
}

///|
/// Line `k`'s node `n` drawn off where it is laid by how far the lines still have to run (a line apart: its height and
/// the gap), as faint as its fading has it.
fn LinesRun::line(self : LinesRun, n : @view.View, k : String) -> Unit {
  let gap = agent_card_lines_gap.px()
  n.moved_by(
    fn(_, h, t) {
      self.way.said()
      (0.0, self.way.value_at(t) * self.steps.get() * (h + gap))
    },
    fn(_, _) {
      self.way.said()
      self.way.end()
    },
  )
  |> ignore
  n.alpha(By(fn() {
    match self.fades.get().get(k) {
      Some(f) => {
        f.said()
        f.value_at(n.drawn_while(fn(t) { f.goes_at(t) }))
      }
      None => 1.0
    }
  }))
  |> ignore
}

///|
/// The copies of the lines gone, over their box `l` (none taking room or a press), each drawn where it was and leaving
/// with the others as far as they run, fading out.
fn LinesRun::gone(self : LinesRun, l : @view.View) -> Unit {
  let gap = agent_card_lines_gap.px()
  l.box(fn(o) {
    o.over(Is(true)).presses(Is(false)) |> ignore
    @sf.style_node(o, fn() { agent_card_gone_lines })
    o.each(at_once=true, fn() { self.gone.get().map(fn(g) { g.key }) }, fn(k) { k }, fn(row, key) {
      let k = key.untracked()
      let copy = fn() { self.gone.get().iter().find_first(fn(g) { g.key == k }) }
      row.box(fn(n) {
        @sf.style_node(n, fn() { agent_card_line_box })
        // (laid in its turn among the copies; drawn where its run has it)
        n.moved_by(
          fn(_, h, t) {
            self.way.said()
            let gs = self.gone.get()
            let m = gs.search_by(fn(g) { g.key == k }).unwrap_or(0).to_double()
            let base = match copy() {
              Some(g) => g.base
              None => m
            }
            (0.0, (base + self.way.value_at(t) * self.steps.get() - m) * (h + gap))
          },
          fn(_, _) {
            self.way.said()
            self.way.end()
          },
        )
        |> ignore
        n.alpha(By(fn() {
          match copy() {
            Some(g) => {
              g.fade.said()
              g.fade.value_at(n.drawn_while(fn(t) { g.fade.goes_at(t) }))
            }
            None => 0.0
          }
        }))
        |> ignore
        @sf.words_node(
          n,
          fn() {
            match copy() {
              Some(g) => g.words
              None => ""
            }
          },
          fn() {
            match copy() {
              Some(g) if g.now => agent_card_now
              _ => agent_card_line
            }
          },
        )
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// The copies' box over the lines': as their box lays them out, from its inside (agent_card_lines' padding and gap).
// kept across runs: a value (no field of it changes)
let agent_card_gone_lines : @ui.Style = @ui.style(w=Full, pl=S3_5, gap=agent_card_lines_gap)
