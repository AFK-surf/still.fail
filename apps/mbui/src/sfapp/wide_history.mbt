// An agent's execution history in the wide frame's side panel, its head as the web's (ember web/src/History.tsx's head,
// pages/ChatPage.tsx SessionHead, SessionDetails, HistorySummary; History.css.ts, ChatPage.css.ts): how it runs in one
// control (the model, how hard it thinks, the account: model_triple.mbt), what needs seeing to beside it; at the
// head's end 只看收发 and 详情. 详情 unfold under the head, open to begin with: what it has used (the large figures, a
// quiet line), then a line each, its mark leading: what runs it (Profile 详情), the station it runs on, its context (管理:
// compacted, or cleared, asked first), where its runtime keeps the session's transcript (复制路径).

///|
/// The head and, unfolded, its details; a line under them.
fn wide_history_head(c : @ui.Ctx, src : Source, r : ChatRef, key : String, a : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=wh_head, fn() {
    c.box(style=wh_identity, fn() {
      model_triple(c, src, r.station, "session:" + key)
      if items(a, "attention").length() > 0 {
        wh_summary(c, a)
      }
    })
    |> ignore
    c.box(style=wh_tools, fn() {
      let io = c.id("history/only-io")
      c.cursor(io, Hand)
      if c.clicked(io) {
        wide.history_io = !wide.history_io
      }
      let on = wide.history_io
      let b = c.box(style=if on { wh_toggle_on } else { wh_toggle }, id=io, fn() {
        @sf.icon(c, "filter", size=14.0, color=if on || c.hovered(io) { t.p.text } else { t.p.muted }) |> ignore
        c.text(tr("web-main.history.onlyIo"), style=if on || c.hovered(io) { wh_toggle_hot } else { wh_toggle_words })
        |> ignore
      })
      c.semantics(b, Button, id=io, label=tr("web-main.history.onlyIo"))
      @kit.tooltip(c, "history/only-io-tip", io, tr("web-main.history.onlyIoTip")) |> ignore
      let more = c.id("history/details")
      c.cursor(more, Hand)
      if c.clicked(more) {
        wide.history_shut = !wide.history_shut
      }
      let hot = c.hovered(more)
      let d = c.box(style=wh_toggle, id=more, fn() {
        c.text(tr("web-main.history.details"), style=if hot { wh_toggle_hot } else { wh_toggle_words }) |> ignore
        @sf.icon(c, if wide.history_shut { "chevron-down" } else { "chevron-up" }, size=14.0, color=if hot {
          t.p.text
        } else {
          t.p.muted
        })
        |> ignore
      })
      c.semantics(d, Button, id=more, label=tr("web-main.history.details"))
    })
    |> ignore
  })
  |> ignore
  if !wide.history_shut {
    wh_details(c, src, r, key, a)
    c.box(style=triple_rule_h, fn() {  }) |> ignore
  }
}

///|
/// What needs seeing to now, beside the control (HistorySummary): a quota running out (its chip), the disk filling up
/// (amber), an account that cannot run (red).
fn wh_summary(c : @ui.Ctx, a : Json?) -> Unit {
  c.box(style=wh_summary_row, fn() {
    for n in items(a, "attention") {
      let nv = Some(n)
      match field(nv, "quota") {
        Some(Object(_)) as q =>
          quota_chips(
            c,
            Some({
              "state": "ok",
              "windows": [
                {
                  "mark": Json::string(text(q, "mark")),
                  "left": Json::number(number(q, "left")),
                  "level": Json::string(text(q, "level")),
                },
              ],
            }),
            small=true,
          )
        _ => c.text(text(nv, "text"), style=if text(nv, "kind") == "disk" { triple_amber } else { triple_red }) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// 详情 (SessionDetails): what it has used, the large figures (its context's opening 管理's menu) and a quiet line; the
/// lines of what runs it, its station, its context, its transcript.
fn wh_details(c : @ui.Ctx, src : Source, r : ChatRef, key : String, a : Json?) -> Unit {
  let t = @sf.theme()
  let s = field(a, "session")
  let card = (src.topic)("agentCard", { "station": Json::string(r.station), "key": Json::string(key) }).value
  let host = (src.topic)("host", { "station": Json::string(r.station) }).value
  let compacts = flag(s, "canCompact")
  let clears = flag(s, "canClear")
  let compacting = context_key("session.compact", r.station, key)
  let clearing = context_key("session.clear", r.station, key)
  let busy = doing(compacting) || doing(clearing)
  let failed = failed_lately(c, compacting) || failed_lately(c, clearing)
  let me = r.station + "\u{1}" + key
  c.box(style=wh_details_box, fn() {
    let entry : ContextTile? = if compacts || clears {
      Some({ open: fn() { wide.context_menu = me + "\u{1}tile" }, busy, failed, compacts })
    } else {
      None
    }
    let tiles = text(card, "cost") != "" || field(card, "cache") is Some(_) || field(card, "context") is Some(_)
    if tiles {
      agent_tiles(c, card, 0.0, entry~)
    }
    let quiet = if tiles {
      [text(card, "work"), text(card, "tokens")].filter(fn(x) { x != "" }).join(" · ")
    } else {
      text((src.topic)("history", history_params(r, key)).value, "usageLine")
    }
    if quiet != "" {
      c.text(quiet, style=wh_quiet) |> ignore
    }
    // what runs it, and its account's page
    let warm = text(s, "process") == "warm"
    wh_line(
      c,
      fn() { @sf.maker_mark(c, text(field(s, "maker"), "id"), text(s, "runtime"), 16.0) |> ignore },
      fn() {
        c.text([text(s, "runtimeText"), text(s, "processText")].filter(fn(x) { x != "" }).join(" · "), style=wh_words)
        |> ignore
        if warm {
          c.text(" · ", style=wh_words) |> ignore
          let ekey = "session.evict/" + r.station + "/" + key
          if wh_link(c, "history/evict", tr("web-pages.chat.evict")) && !doing(ekey) {
            act(
              src,
              tr("web-pages.chat.evict"),
              ekey,
              "session.evict",
              { "station": Json::string(r.station), "key": Json::string(key) },
              done=tr("web-pages.chat.evicted"),
            )
          }
          if doing(ekey) {
            @sf.spinner(c, size=12.0) |> ignore
          }
        }
      },
      fn() {
        match text(s, "profile") {
          "" => ()
          p =>
            if wh_link(c, "history/profile", tr("web-pages.chat.profileDetails")) {
              app.nav.push(Setting(@settings.Route::Profile(r.station, p)))
            }
        }
      },
    )
    // the station it runs on
    let station = stations_of((src.topic)("stations", { "scope": Json::string(scope_of(r.station)) }).value)
      .iter()
      .find_first(fn(x) { x.address == r.station })
    wh_line(
      c,
      fn() {
        match station {
          Some(st) => @sf.station_mark(c, st.emoji, st.icon, 16.0, t.p.muted, none="server")
          None => @sf.icon(c, "server", size=16.0, color=t.p.muted) |> ignore
        }
      },
      fn() {
        let name = match station {
          Some(st) if st.name != "" => st.name
          _ =>
            match text(host, "hostname") {
              "" => tr("web-pages.chat.thisMachine")
              h => h
            }
        }
        c.text(name, style=wh_name) |> ignore
        match text(host, "identity") {
          "" => ()
          i => c.text(" · " + i, style=wh_words) |> ignore
        }
      },
      fn() {  },
    )
    // its context, by hand
    if compacts || clears {
      let used = text(field(card, "context"), "text")
      wh_line(
        c,
        fn() { @sf.icon(c, "shrink", size=16.0, color=t.p.muted) |> ignore },
        fn() {
          c.text(tr("web-pages.chat.context") + (if used != "" { " · " + used } else { "" }), style=wh_words) |> ignore
          if busy || failed {
            @settings.doing_mark(c, busy, if failed { Some("") } else { None })
          }
        },
        fn() {
          if wh_link(c, "history/context", tr("web-pages.chat.contextManage")) {
            wide.context_menu = me + "\u{1}line"
          }
        },
      )
    }
    // where its runtime keeps the transcript
    match wide.transcripts.get(me) {
      None => {
        wide.transcripts[me] = ""
        c.tell("history/transcript/" + me, fn() {
          (src.call)("session.transcript", { "station": Json::string(r.station), "key": Json::string(key) }, fn(res) {
            match res {
              Ok(j) => wide.transcripts[me] = text(Some(j), "path")
              // not written yet, or a station from before it: nothing said
              Err(_) => ()
            }
          })
        })
      }
      Some("") => ()
      Some(path) => {
        let name = match path.rev_find("/") {
          Some(i) => path.view(start_offset=i + 1).to_string()
          None => path
        }
        wh_line(
          c,
          fn() { @sf.icon(c, "file", size=16.0, color=t.p.muted) |> ignore },
          fn() {
            c.text(tr("web-pages.chat.transcript") + " · ", style=wh_words) |> ignore
            c.text(name, style=wh_file) |> ignore
          },
          fn() {
            if wh_link(c, "history/copy-path", tr("web-pages.chat.copyPath")) {
              c.copy_text(path)
              say(c, tr("web-main.chat.transcriptCopied"))
            }
          },
        )
      }
    }
  })
  |> ignore
  wh_context_menu(c, src, r, key, me, compacts, clears)
}

///|
/// Its context's 管理 (useContextActions): 压缩上下文 at once (the chat told when it is done), 清空上下文 asked first.
fn wh_context_menu(c : @ui.Ctx, src : Source, r : ChatRef, key : String, me : String, compacts : Bool, clears : Bool) -> Unit {
  let open = wide.context_menu.has_prefix(me + "\u{1}")
  let anchor = if wide.context_menu == me + "\u{1}tile" {
    c.id("agent/context-tile")
  } else {
    c.id("history/context")
  }
  let entries : Array[@kit.Entry] = []
  if compacts {
    entries.push(@kit.menu_item("compact", label=tr("web-pages.chat.compact")))
  }
  if clears {
    entries.push(@kit.menu_item("clear", label=tr("web-pages.chat.clear")))
  }
  let m = wide_menu(c, "context-menu/" + me, open, anchor, entries, { "compact": "shrink", "clear": "refresh" }, 180.0)
  if open && !m.open {
    wide.context_menu = ""
  }
  let params : Json = { "station": Json::string(r.station), "key": Json::string(key) }
  match m.chosen {
    Some("compact") => {
      wide.context_menu = ""
      act(src, tr("web-pages.chat.compact"), context_key("session.compact", r.station, key), "session.compact", params, done=tr("web-mobile.agent.compacting"))
    }
    Some("clear") => {
      wide.context_menu = ""
      wide.clear_asking = me
    }
    _ => ()
  }
  match wide_confirm(c, "clear-context/" + me, wide.clear_asking == me, tr("web-pages.chat.clearConfirm"), [tr("web-pages.chat.clearBody")], tr("web-pages.chat.clear"), false, true) {
    Some(yes) => {
      wide.clear_asking = ""
      if yes {
        act(src, tr("web-pages.chat.clear"), context_key("session.clear", r.station, key), "session.clear", params)
      }
    }
    None => ()
  }
}

///|
/// A line of the details (sessionLine): its mark in a 16 column, its words cut at their end, what can be done at its
/// end.
fn wh_line(c : @ui.Ctx, mark : () -> Unit, words : () -> Unit, end : () -> Unit) -> Unit {
  c.box(style=wh_line_style, fn() {
    c.box(style=wh_mark, mark) |> ignore
    c.box(style=wh_line_words, words) |> ignore
    end()
  })
  |> ignore
}

///|
/// A link of the details (detailLink): its words, underlined on hover. True on the frame after a press.
fn wh_link(c : @ui.Ctx, key : String, words : String) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(id~, style=wh_link_box, fn() {
    c.text(words, style=if c.hovered(id) { wh_link_hot } else { wh_words }) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
  c.clicked(id)
}

///|
/// A station's workspace, from its address (ws/station).
fn scope_of(station : String) -> String {
  match station.find("/") {
    Some(i) => station.view(end_offset=i).to_string()
    None => station
  }
}

///|
/// The head (historyHead): 45 high, 16 in at its start, 8 at its end.
// kept across runs: a value (no field of it changes)
let wh_head : @ui.Style = @ui.style(row=true, w=Full, h=S11, pl=S4, pr=S2, pb=SPx, gap=S2, align=ACenter, justify=JBetween)

///|
/// What it runs on and what needs seeing to (historyIdentity): what is too long cut at its end; the control's own 10 in
/// stood out by (its words on the line of the details' under it).
// kept across runs: a value (no field of it changes)
let wh_identity : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let wh_tools : @ui.Style = @ui.style(row=true, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wh_summary_row : @ui.Style = @ui.style(row=true, gap=S2_5, align=ACenter)

///|
/// 只看收发 and 详情 (controls.css.ts textToggle): 2 by 4 in, 12 on 18, muted; the words' ink on hover; 只看收发 on, its
/// ground the picked one's.
// kept across runs: a value (no field of it changes)
let wh_toggle : @ui.Style = @ui.style(row=true, px=S1, py=S0_5, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wh_toggle_on : @ui.Style = @ui.style(row=true, px=S1, py=S0_5, gap=S1, align=ACenter, bg=Selected, radius=Lg)

///|
// kept across runs: a value (no field of it changes)
let wh_toggle_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_toggle_hot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// 详情 (sessionDetails): 2 over, 16 at the sides, 14 under, 10 between; words 12, muted.
// kept across runs: a value (no field of it changes)
let wh_details_box : @ui.Style = @ui.style(w=Full, px=S4, pt=S0_5, pb=S3_5, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let wh_quiet : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let wh_line_style : @ui.Style = @ui.style(row=true, w=Full, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wh_mark : @ui.Style = @ui.style(w=S4, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let wh_line_words : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let wh_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_file : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let wh_link_box : @ui.Style = @ui.style(row=true, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wh_link_hot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// The steps under the head: the rest of the panel.
// kept across runs: a value (no field of it changes)
let wh_fill : @ui.Style = @ui.style(w=Full, h=Full)
