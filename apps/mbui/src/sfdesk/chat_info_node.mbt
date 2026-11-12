// What a chat's info says on 中屏 and 大屏 (ChatInfoBody; chat_page.mbt's chat_info till 2026-11-12) as nodes of the
// window's tree, made once as the panel the bar's 对话信息 presents opens (chat_pops_node), each part bound to what it
// is made of: what it is (where it came from if not here, who started it, who else takes part, when it was made and last
// written in), who works in it (its agents), the chats its agents made, what is in it (its pull requests, what else was
// said, the stations' files beside it, what its agents and other chats' wrote each other). Laid out as the old view's
// was, by the same styles. Pressed, a row does what it opens and the panel closes (`done`).

///|
/// Chat `r`'s info in `v` (the presented panel's body): its view as it is now (`view`), its pictures asked for on the
/// page's time (`stint`); `done` closes it.
fn chat_info_node(v : @view.View, src : Source, r : ChatRef, view : () -> ChatView?, stint : () -> Int, done : () -> Unit) -> Unit {
  let chat = fn() { src.topic("chat", chat_params(r)).get().value }
  let tips = match @sf.panel_tips_of(v) {
    Some(t) => t
    None => @sf.TipLayer::new(fn() { None })
  }
  // (each part made again as what it is made of says otherwise: what it is, its agents, the chats they made, what is
  // in it)
  v.pick(fn() { info_facts_said(chat(), view()) }, fn(f, _) {
    info_facts_node(f, src, @signals.untracked(chat), @signals.untracked(view), tips, stint, done)
  })
  v.pick(fn() { items(chat(), "agents") }, fn(a, agents) { info_agents_node(a, agents) })
  v.pick(
    fn() {
      match view() {
        Some(cv) if cv.opened.length() > 0 => Some((cv.opened_text, cv.opened.map(fn(o) { (o.chat.station, o.chat.session) })))
        _ => None
      }
    },
    fn(o, said) {
      guard said is Some((words, _)) else { return }
      o.box(fn(g) {
        @sf.style_node(g, fn() { info_tools(false) })
        // (beside the panel, to its left: the panel stands at the window's end; pointed at, it opens)
        @sf.submenu_row_node(
          g,
          fn() { words },
          fn() {
            match @signals.untracked(view) {
              Some(cv) => @sfpages.opened_items(cv.opened, then=done)
              None => []
            }
          },
          icon=fn() { "spawned" },
          side=Left,
        )
      })
      |> ignore
    },
  )
  v.pick(fn() { info_things_said(src, r, chat(), view()) }, fn(g, said) {
    info_things_node(g, src, r, said, done)
  })
}

///|
/// What the info's facts are made of (info_facts_node's): where it came from, its thread, who opened it, its people, and
/// whether the system's bars are on.
fn info_facts_said(chat : Json?, view : ChatView?) -> (String, Bool, Json?, (ChatRef, String, Bool, String)?, Array[(String, String, String)], Bool) {
  let thread = field(chat, "thread")
  let feishu = text(thread, "surface").has_prefix("feishu:") || text(chat, "feishuUrl") != ""
  let (opener, people) = match view {
    Some(cv) => (cv.opener.map(fn(o) { (o.chat, o.text, o.archived, o.note) }), cv.people.map(fn(p) { (p.id, p.display, p.picture) }))
    None => (None, [])
  }
  (text(chat, "place"), feishu, thread, opener, people, @sf.native_on())
}

///|
/// The info's facts in `f` (chat_info's first group): in a column of their labels, as wide as the widest in this
/// language, 80 at least, each its words after it.
fn info_facts_node(
  f : @view.View,
  src : Source,
  chat : Json?,
  view : ChatView?,
  tips : @sf.TipLayer,
  stint : () -> Int,
  done : () -> Unit,
) -> Unit {
  guard view is Some(v) else { return }
  let thread = field(chat, "thread")
  let th = opt_number(thread, "id")
  let labels = ["from", "started", "people", "created", "lastMessage"].map(fn(k) { @sf.t("web-pages.chat.info." + k) })
  // (its labels in a column 80 wide, or as wide as the widest of them in this language: words of a length known,
  // whole, measured again as the system's size of words changes)
  let label_w = fn() {
    f.words_redone() |> ignore
    let size = @sf.theme().t.ui * f.words_scale()
    labels.fold(init=info_label_w, fn(m, l) { dmax(m, @ui.text_advance(l, size~).ceil()) })
  }
  f.box(fn(facts) {
    // (its first fact's words as far under the panel's top as a menu's first item's: the fact's row taller than its
    // line, centred in it)
    let over = fn() { @sf.menu_row_over - (info_fact_h - @sf.theme().t.ui_line) / 2.0 }
    @sf.style_node(facts, fn() { info_facts.then(@ui.style(pt=@sf.room_of(over()))) })
    let fact = fn(label : String, value : (@view.View) -> Unit) {
      facts.box(fn(row) {
        @sf.style_node(row, fn() { info_fact })
        row.box(fn(l) {
          l.width(By(fn() { Some(label_w()) })).shrink(Is(0.0)) |> ignore
          @sf.words_node(l, fn() { label }, fn() { info_muted }) |> ignore
        })
        |> ignore
        value(row)
      })
      |> ignore
    }
    // (where it came from only when that is not here: a still.fail chat's says nothing)
    match text(chat, "place") {
      "" => ()
      place =>
        fact(@sf.t("web-pages.chat.info.from"), fn(row) {
          let feishu = text(thread, "surface").has_prefix("feishu:") || text(chat, "feishuUrl") != ""
          row.box(fn(i) {
            @sf.style_node(i, fn() { info_inline }, in_row=true)
            @sf.drawable_node(i, if feishu { "feishu" } else { "slack" }, 13.0) |> ignore
            let through = if feishu { @sf.t("web-pages.connect.feishu.name") } else { "Slack" }
            @sf.words_node(i, fn() { through + " · " + place }, fn() { info_words }) |> ignore
          })
          |> ignore
        })
    }
    guard th is Some(_) else { return }
    let creator = match text(field(field(thread, "creator"), "shown"), "display") {
      "" => text(field(thread, "creator"), "name")
      d => d
    }
    fact(@sf.t("web-pages.chat.info.started"), fn(row) {
      match v.opener {
        // made by another chat's agent: that chat, its mark before its title (已归档 after one in the archive); pressed,
        // it opens
        Some(o) =>
          row.box(fn(b) {
            @sf.style_node(b, fn() { info_inline }, in_row=true)
            b.says(Is(Some(@view.said(Link, label=o.text)))) |> ignore
            @sf.presses_node(b, fn() {
              done()
              open_page(Chat(o.chat))
            })
            @sf.icon_node(b, "spawned", 14.0, By(fn() { if @sf.lit_node(b) { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
            @sf.words_node(b, fn() { o.chat.title }, fn() { if @sf.lit_node(b) { info_words_hot } else { info_words } }) |> ignore
            if o.archived {
              @sf.words_node(b, fn() { o.note }, fn() { info_quiet }) |> ignore
            }
            @sf.tip_node(tips, b, fn() { o.text }, repeats=true) |> ignore
          })
          |> ignore
        None if creator == "" => @sf.words_node(row, fn() { @sf.t("web-pages.chat.info.unknown") }, fn() { info_muted }) |> ignore
        // their face before their name, as the people's are
        None =>
          row.box(fn(i) {
            @sf.style_node(i, fn() { info_inline }, in_row=true)
            match field(thread, "creator") {
              Some(Object(_) as p) => wide_people(i, src, [@sfbase.person_of(p)], 1, tips, stint)
              _ => ()
            }
            @sf.words_node(i, fn() { creator }, fn() { info_words }) |> ignore
          })
          |> ignore
      }
    })
    // (who takes part only when that is more than who started it)
    let creator_id = text(field(thread, "creator"), "id")
    let only_starter = v.people.length() == 0 ||
      (v.people.length() == 1 && creator_id != "" && v.people[0].id == creator_id)
    if !only_starter {
      fact(@sf.t("web-pages.chat.info.people"), fn(row) {
        // (beside the system's tabs, no pointer to rest on them for their names: each its face and its name, the people
        // out of the chat's bar there, rail_native.mbt; the user 2026-10-27)
        if @sf.native_on() {
          row.box(fn(list) {
            @sf.style_node(list, fn() { info_people_list }, in_row=true)
            for p in v.people {
              list.box(fn(i) {
                @sf.style_node(i, fn() { info_inline })
                wide_people(i, src, [p], 1, tips, stint)
                @sf.words_node(i, fn() { p.display }, fn() { info_words }) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
          return
        }
        row.box(fn(i) {
          @sf.style_node(i, fn() { info_inline }, in_row=true)
          wide_people(i, src, v.people, 8, tips, stint)
          @sf.words_node(i, fn() { @sf.t("web-pages.workspace.people", args=[("n", v.people.length().to_string())]) }, fn() {
            info_words
          })
          |> ignore
        })
        |> ignore
      })
    }
    fact(@sf.t("web-pages.chat.info.created"), fn(row) { info_time_node(row, tips, field(field(thread, "time"), "createdAt")) })
    let last = field(field(field(thread, "lastMessage"), "time"), "createdAt")
    if last is Some(Object(_)) {
      fact(@sf.t("web-pages.chat.info.lastMessage"), fn(row) { info_time_node(row, tips, last) })
    }
  })
  |> ignore
}

///|
/// A time as the core says it (info_time's, ui.tsx Time) in `row`: how long ago, the date in its tip as the pointer
/// rests on it.
fn info_time_node(row : @view.View, tips : @sf.TipLayer, stamp : Json?) -> Unit {
  row.box(fn(b) {
    @sf.words_node(b, fn() { text(stamp, "ago") }, fn() { info_words }) |> ignore
    @sf.tip_node(tips, b, fn() { text(stamp, "full") }, within=true) |> ignore
  })
  |> ignore
}

///|
/// Who works in it (info_agents's) in `a`, under who and when (the user, 2026-10-30: 信息和排布不是很合理): each agent's
/// mark (its badge on the panel's ground) and label over its line.
fn info_agents_node(a : @view.View, agents : Array[Json]) -> Unit {
  guard agents.length() > 0 else { return }
  a.box(fn(list) {
    @sf.style_node(list, fn() { info_agents })
    for one in agents {
      let av = Some(one)
      let s = field(av, "session")
      let connect = field(av, "connect")
      list.box(fn(ag) {
        @sf.style_node(ag, fn() { info_agent })
        ag.box(fn(head) {
          @sf.style_node(head, fn() { info_agent_head })
          @sfpages.agent_mark_node(
            head,
            fn() { text(field(s, "maker"), "id") },
            fn() { text(s, "runtime") },
            info_mark_side,
            badge=text(av, "badge"),
            ground=@sf.panel_ground,
          )
          @sf.words_node(head, fn() { text(s, "agentText") }, fn() { info_words }) |> ignore
        })
        |> ignore
        let parts = []
        if connect is Some(Object(_)) {
          parts.push(text(connect, "name"))
        }
        parts.push(text(s, "processText"))
        parts.push(@sf.t("web-pages.chat.lastActive", args=[("time", text(field(field(s, "time"), "lastActiveAt"), "ago"))]))
        ag.box(fn(line) {
          @sf.style_node(line, fn() { info_agent_line })
          @sf.words_node(line, fn() { parts.join(" · ") }, fn() { info_quiet }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// What is in the chat as the info names it (info_things_node's): its pull requests, how much else was said in it,
/// whether its stations lend their files beside it, how many letters, and whether the system's bars are on.
fn info_things_said(src : Source, r : ChatRef, chat : Json?, view : ChatView?) -> (Array[Json], Int, Bool, Int, Bool) {
  let (said, pulls) = match opt_number(field(chat, "thread"), "id") {
    Some(id) => @sfpages.things_now(src, r.station, id)
    None => (0, [])
  }
  let files = dv_stations(src, scope_of(r.station)).0.unwrap_or([]).iter().any(fn(s) { s.drive })
  let letters = match view {
    Some(v) => v.letters
    None => 0
  }
  (pulls, said, files, letters, @sf.native_on())
}

///|
/// What is in it (chat_info's last group) in `g`: the pull requests linked in it, the latest 3 (the user, 2026-10-29:
/// most chats have one or two, seen at a look), 全部 N 个 to the rest beside the chat, pressed, one opens in the
/// browser; what else was said in it besides words, the stations' files beside it, what its agents and other chats'
/// wrote each other.
fn info_things_node(
  g : @view.View,
  src : Source,
  r : ChatRef,
  said : (Array[Json], Int, Bool, Int, Bool),
  done : () -> Unit,
) -> Unit {
  let (pulls, things, files, letters, native) = said
  guard pulls.length() > 0 || things > 0 || files || letters > 0 else { return }
  g.box(fn(t) {
    @sf.style_node(t, fn() { info_tools(true) })
    // (beside the system's tabs, a phone's room: none of them by itself, 全部 N 个 alone, the user 2026-11-01)
    let named = if native { 0 } else { info_pulls_most }
    for i, p in pulls {
      if i == named {
        break
      }
      let pv = Some(p)
      info_pull_node(t, src, r, pv, fn() {
        done()
        @sfbase.open_link_in(src, text(pv, "url"))
      }, done)
    }
    if pulls.length() > named {
      info_row_node(t, "list", @sf.t("web-main.things.pullsAll", args=[("n", pulls.length().to_string())]), "", fn() {
        done()
        @sfpages.things_choose(r, "pulls")
        side_change(src, r, "open", Some("things"))
      })
    }
    // (sfpages things.mbt)
    if things > 0 {
      info_row_node(t, "photo", @sf.t("web-main.things.title"), things.to_string(), fn() {
        done()
        side_change(src, r, "open", Some("things"))
      })
    }
    if files {
      info_row_node(t, "folder", @sf.t("web-pages.chat.files"), "", fn() {
        done()
        side_toggle(src, r, "files")
      })
    }
    if letters > 0 {
      info_row_node(t, "chats", @sf.t("web-main.letters.title"), @sf.t("web-main.letters.count", args=[("n", letters.to_string())]), fn() {
        done()
        letters_to_list(r)
        side_toggle(src, r, "letters")
      })
    }
  })
  |> ignore
}

///|
/// The ground of a row of the info under the hand (info_tool's hovered).
fn info_row_ground(b : @view.View) -> Int64 {
  if @sf.lit_node(b) {
    @sf.theme().p.hover
  } else {
    0L
  }
}

///|
// kept across runs: a value (no field of it changes)
let info_row_round : @ui.Style = @ui.style(radius=@sf.panel_in)

///|
/// A row of the info (info_row's, ui.tsx PanelRow) in `parent`: its icon (14, muted) at the panel's words' inset, as
/// the facts' words and the agents' marks over it, and words 10 apart, what is at its end (`end`) muted, under its words
/// where the line has not the room; round with the panel, the pointer's ground on it; `press` as it is pressed.
fn info_row_node(parent : @view.View, icon : String, label : String, end : String, press : () -> Unit) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { info_tool().then(info_row_round) })
    b.ground(By(fn() { info_row_ground(b) })).says(Is(Some(@view.said(Button, label~)))) |> ignore
    @sf.presses_node(b, press)
    b.box(fn(i) {
      @sf.style_node(i, fn() { info_tool_icon }, in_row=true)
      @sf.icon_node(i, icon, 14.0, By(fn() { @sf.theme().p.muted })) |> ignore
    })
    |> ignore
    b.box(fn(l) {
      @sf.style_node(l, fn() { info_label_flow }, in_row=true)
      l.wraps(Is(Some(0.0))) |> ignore
      @sf.words_node(l, fn() { label }, fn() { info_words }) |> ignore
      if end != "" {
        @sf.words_node(l, fn() { end }, fn() { info_end }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A pull request in the info (info_pull_row's, as info_row_node) in `parent`: its mark where a row's icon is, its title
/// cut to the line, its number at the line's end, muted; pointed at, its card (as a message's link to it, at the info's
/// left: under it, it would cover the info's rows after it; the user, 2026-10-29: 显示到左边); held or right clicked,
/// its menu (在对话中查看, its link copied); `press` as it is pressed, `done` closing the info for its menu's choice.
fn info_pull_node(parent : @view.View, src : Source, r : ChatRef, pull : Json?, press : () -> Unit, done : () -> Unit) -> Unit {
  let title = @sfpages.pull_title(pull)
  let url = text(pull, "url")
  parent.box(fn(b) {
    @sf.style_node(b, fn() { info_tool().then(info_row_round) })
    b.ground(By(fn() { info_row_ground(b) })).says(Is(Some(@view.said(Link, label=title)))) |> ignore
    @sf.menu_presses_node(b, press, fn(x, y, _) {
      @sfpages.thing_menu_node_at(x, y, number(pull, "seq"), url, fn(seq) {
        done()
        @sfbase.go_to(r, seq)
      })
    })
    b.box(fn(i) {
      @sf.style_node(i, fn() { info_tool_icon }, in_row=true)
      @sfpages.pull_mark_node(i, fn() { pull }, 14.0)
    })
    |> ignore
    b.box(fn(w) {
      @sf.style_node(w, fn() { info_pull_words }, in_row=true)
      // (its words as wide as they are, cut short where the line has not the room: in a row of their own)
      w.row(Is(true)) |> ignore
      @sf.words_node(w, fn() { title }, fn() { info_pull_title }) |> ignore
    })
    |> ignore
    @sf.words_node(b, fn() { "#" + count(pull, "number").to_string() }, fn() { info_end }) |> ignore
    @sfpages.web_peek_node(b, src, r.station, fn() { url }, fn() { title }, side=Left, peek=fn() { text(pull, "peek") })
  })
  |> ignore
}
