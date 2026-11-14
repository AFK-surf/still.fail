// One of a chat's agents in brief (hover.mbt's agent_card) as nodes of the window's tree, made once in a hover card
// (@sf.hover_card_node): what it shows and how, the same as that; what it reads the same (the chat's agent as the
// chat's view has it, the core's `agentCard` view of it). What is pressed in it opens beside the card (`from`: its
// card, Node(card)), and says whether what it opened is presented now (the card kept open meanwhile: the hover card's
// `held`). Where they differ: its latest lines come and go as anything in a column does (View::each), not run on as a
// ticker; what can be done to its context opens beside its figure (usage_tiles_node's), not at the card's right.

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
    // its latest lines, what it does now in the words' colour
    b.show(fn() { items(card(), "latest").length() > 0 }, fn(x) {
      x.box(fn(l) {
        @sf.style_node(l, fn() { agent_card_lines })
        l.each(fn() { items(card(), "latest") }, fn(line) { text(Some(line), "key") }, fn(row, line) {
          let k = text(Some(line.untracked()), "key")
          row.box(fn(n) {
            @sf.style_node(n, fn() { agent_card_line_box })
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
/// it does in its tip; a spinner in its place while asked. The card's, and the head of its history in the side panel.
pub fn agent_card_stop_node(p : @view.View, src : Source, station : String, key : String, tips : @sf.TipLayer) -> Unit {
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
