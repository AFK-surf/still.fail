// An agent's execution history in the desktop's side panel, its head as the web's (ember web/src/History.tsx's head,
// pages/ChatPage.tsx SessionHead, SessionDetails, HistorySummary; History.css.ts, ChatPage.css.ts): how it runs in one
// control (the model, how hard it thinks, the account: model_triple.mbt), what needs seeing to beside it; at the
// head's end 只看收发 and 详情. 详情 unfold under the head, open to begin with: what it has used (the large figures, a
// quiet line), then a line each, its mark leading: what runs it (Profile 详情), the station it runs on (what runs low
// on it), its context (管理: compacted, or cleared, asked first), where its runtime keeps the session's transcript
// (复制路径). Its steps under them are the page's to give.

///|
/// What the history keeps of its own (the rest is the core's): 只看收发 (for every history, as the web keeps it), its
/// details folded; where its runtime keeps each session's transcript (by station and session; "" none), asked once;
/// its context's 管理 menu open (its session's, and from which: its tile or its line), clearing it asked to confirm
/// (its session's key, "" none).
priv struct HistoryOwn {
  mut shut : Bool
  transcripts : Map[String, String]
  mut context_menu : String
  mut clear_asking : String
}

///|
let history_own : HistoryOwn = { shut: false, transcripts: {}, context_menu: "", clear_asking: "" }

///|
fn history_reset() -> Unit {
  history_own.shut = false
  history_own.transcripts.clear()
  history_own.context_menu = ""
  history_own.clear_asking = ""
}

///|
/// Agent `key`'s history beside its chat `r`, in front (not toggled), brought to transcript entry `entry` if one is
/// asked (ChatPage.tsx history): the page the chat's, in place of the one that asked.
fn history_beside(src : Source, r : ChatRef, key : String, entry : Int?) -> Unit {
  match app.nav.top() {
    History(_, _, _) => app.nav.replace(Chat(r))
    _ => ()
  }
  match entry {
    Some(e) => @sfpages.history_focus(r.station, key, e)
    None => ()
  }
  side_change(src, r, "open", Some(key))
}

///|
/// Agent `key`'s history on `station` (`a` as its chat's view has it): its head and, unfolded, its details, a line
/// under them; its steps in the rest (sfpages' history_steps.mbt).
fn agent_history(c : @ui.Ctx, src : Source, station : String, key : String, a : Json?) -> Unit {
  history_head(c, src, station, key, a)
  c.box(style=wh_fill, fn() { @sfpages.history_steps(c, src, station, key) }) |> ignore
}

///|
/// The head (History.tsx historyHead) and, unfolded, its details; a line under them.
fn history_head(c : @ui.Ctx, src : Source, station : String, key : String, a : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=wh_head, fn() {
    c.box(style=wh_identity, fn() {
      @sfpages.model_triple(c, src, station, "session:" + key)
      if items(a, "attention").length() > 0 {
        wh_summary(c, a)
      }
    })
    |> ignore
    c.box(style=wh_tools, fn() {
      let io = c.id("history/only-io")
      c.cursor(io, Hand)
      if c.clicked(io) {
        @sfpages.history_only_io_flip()
      }
      let on = @sfpages.history_only_io()
      let b = c.box(style=if on { wh_toggle_on } else { wh_toggle }, id=io, fn() {
        @sf.icon(c, "filter", size=14.0, color=if on || c.lit(io) { t.p.text } else { t.p.muted }) |> ignore
        c.text(@sf.t("web-main.history.onlyIo"), style=if on || c.lit(io) { wh_toggle_hot } else { wh_toggle_words })
        |> ignore
      })
      c.semantics(b, Button, id=io, label=@sf.t("web-main.history.onlyIo"))
      @sf.tip(c, "history/only-io-tip", io, @sf.t("web-main.history.onlyIoTip"))
      let more = c.id("history/details")
      c.cursor(more, Hand)
      if c.clicked(more) {
        history_own.shut = !history_own.shut
      }
      let hot = c.lit(more)
      let d = c.box(style=wh_toggle, id=more, fn() {
        c.text(@sf.t("web-main.history.details"), style=if hot { wh_toggle_hot } else { wh_toggle_words }) |> ignore
        @sf.icon(c, if history_own.shut { "chevron-down" } else { "chevron-up" }, size=14.0, color=if hot {
          t.p.text
        } else {
          t.p.muted
        })
        |> ignore
      })
      c.semantics(d, Button, id=more, label=@sf.t("web-main.history.details"))
    })
    |> ignore
  })
  |> ignore
  if !history_own.shut {
    wh_details(c, src, station, key, a)
    c.box(style=@sfpages.triple_rule_h, fn() {  }) |> ignore
  }
}

///|
/// What needs seeing to now, beside the control (HistorySummary): a quota running out (its chip, what it says and more
/// in its tip), the disk filling up (amber), an account that cannot run (red).
fn wh_summary(c : @ui.Ctx, a : Json?) -> Unit {
  c.box(style=wh_summary_row, fn() {
    for i, n in items(a, "attention") {
      let nv = Some(n)
      match field(nv, "quota") {
        Some(Object(_)) as q => {
          let id = c.id("history/attention/" + i.to_string())
          c.box(id~, taps=false, fn() {
            @settings.quota_chips(
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
          })
          |> ignore
          let more = text(nv, "more")
          @sf.tip(c, "history/attention/" + i.to_string(), id, text(nv, "text") + (if more != "" {
            "\n" + more
          } else {
            ""
          }))
        }
        _ => c.text(text(nv, "text"), style=if text(nv, "kind") == "disk" { wh_amber } else { wh_red }) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// 详情 (SessionDetails): what it has used, as its card says it (the large figures, its context's opening 管理's menu,
/// and a quiet line; a station older than the card's figures, its history's line), then a line each: what runs it
/// (ending it while it is kept warm; its account's page), the station it runs on (what runs low on it), its context,
/// its transcript.
fn wh_details(c : @ui.Ctx, src : Source, station : String, key : String, a : Json?) -> Unit {
  let t = @sf.theme()
  let s = field(a, "session")
  let on = [("station", station), ("key", key)]
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let card = (src.topic)("agentCard", params).value
  let host = (src.topic)("host", { "station": Json::string(station) }).value
  let compacts = flag(s, "canCompact")
  let clears = flag(s, "canClear")
  // (what is under way and what failed a moment ago, as the core's `doing` says: useContextActions)
  let calls = ["session.compact", "session.clear"]
  let busy = core_doing(src, calls, on)
  let failed = core_failed(src, calls, on)
  let me = station + "\u{1}" + key
  c.box(style=wh_details_box, fn() {
    let tiles = text(card, "cost") != "" || field(card, "cache") is Some(_) || field(card, "context") is Some(_)
    if tiles {
      let entry : ContextEntry? = if compacts || clears {
        Some({ open: fn() { history_own.context_menu = me + "\u{1}tile" }, busy, compacts })
      } else {
        None
      }
      usage_tiles(c, card, entry?=entry)
    }
    let quiet = if tiles {
      [text(card, "work"), text(card, "tokens")].filter(fn(x) { x != "" }).join(" · ")
    } else {
      text((src.topic)("history", params).value, "usageLine")
    }
    if quiet != "" {
      c.box(style=wh_quiet_box, fn() { c.text(quiet, style=wh_quiet) |> ignore }) |> ignore
    }
    // what runs it, and its account's page
    wh_line(
      c,
      fn() { agent_mark(c, text(field(s, "maker"), "id"), text(s, "runtime"), "", side=wh_mark_side) },
      fn() {
        c.text(text(s, "runtimeText") + " · " + text(s, "processText"), style=wh_words) |> ignore
        if text(s, "process") == "warm" {
          c.text(" · ", style=wh_dot) |> ignore
          wh_evict(c, src, station, key)
        }
      },
      fn() {
        if wh_link(c, "history/profile", @sf.t("web-pages.chat.profileDetails")) {
          app.nav.push(Setting(@settings.Route::Profile(station, text(s, "profile"))))
        }
      },
    )
    // the station it runs on, what runs low on it at its end
    let look = stations_of((src.topic)("stations", { "scope": Json::string(scope_of(station)) }).value)
      .iter()
      .find_first(fn(x) { x.address == station })
    wh_line(
      c,
      fn() {
        match look {
          Some(st) => @sf.station_mark(c, st.emoji, st.icon, wh_mark_side, t.p.muted, none="server")
          None => @sf.icon(c, "server", size=wh_mark_side, color=t.p.muted) |> ignore
        }
      },
      fn() {
        let name = match look {
          Some(st) if st.name != "" => st.name
          _ =>
            match text(host, "hostname") {
              "" => @sf.t("web-pages.chat.thisMachine")
              h => h
            }
        }
        c.text(name, style=wh_name) |> ignore
        match text(host, "identity") {
          "" => ()
          i => c.text(" · " + i, style=wh_words) |> ignore
        }
      },
      fn() {
        let meters = items(host, "meters")
        if meters.iter().any(fn(m) { text(Some(m), "level") != "ok" }) {
          @settings.meter_chips(c, "history/host", meters, alerts=true)
        }
      },
    )
    // its context, by hand (ContextLine)
    if compacts || clears {
      let used = text(field(card, "context"), "text")
      wh_line(
        c,
        fn() { @sf.icon(c, "shrink", size=wh_mark_side, color=t.p.muted) |> ignore },
        fn() {
          c.text(@sf.t("web-pages.chat.context") + (if used != "" { " · " + used } else { "" }), style=wh_words)
          |> ignore
        },
        fn() {
          @settings.doing_mark(c, busy, failed, inline=true)
          if wh_link(c, "history/context", @sf.t("web-pages.chat.contextManage")) {
            history_own.context_menu = me + "\u{1}line"
          }
        },
      )
    }
    wh_transcript(c, src, station, key, me)
  })
  |> ignore
  wh_context_menu(c, src, station, key, me, compacts, clears, busy)
}

///|
/// Its idle process, kept warm for the next message, ended now (Evict): its link, a turning ring while it is under
/// way, a red mark a few seconds once it failed.
fn wh_evict(c : @ui.Ctx, src : Source, station : String, key : String) -> Unit {
  let on = [("station", station), ("key", key)]
  let evicting = core_doing(src, ["session.evict"], on)
  if wh_link(c, "history/evict", @sf.t("web-pages.chat.evict")) && !evicting {
    act(
      src,
      @sf.t("web-pages.chat.evict"),
      "",
      "session.evict",
      { "station": Json::string(station), "key": Json::string(key) },
      done=@sf.t("web-pages.chat.evicted"),
    )
  }
  @settings.doing_mark(c, evicting, core_failed(src, ["session.evict"], on), inline=true)
}

///|
/// Where its runtime keeps the session's transcript on the station's machine (TranscriptLine): its file's name (the
/// whole path in its tip), and its path to copy. Nothing before it is written, nor from a station from before it.
fn wh_transcript(c : @ui.Ctx, src : Source, station : String, key : String, me : String) -> Unit {
  let t = @sf.theme()
  match history_own.transcripts.get(me) {
    None => {
      history_own.transcripts[me] = ""
      c.tell("history/transcript/" + me, fn() {
        (src.call)("session.transcript", { "station": Json::string(station), "key": Json::string(key) }, fn(res) {
          match res {
            Ok(j) => history_own.transcripts[me] = text(Some(j), "path")
            // not written yet, or a station from before it: nothing said
            Err(_) => ()
          }
        })
      })
    }
    Some("") => ()
    Some(path) => {
      let cut = match path.rev_find("/") {
        Some(i) => Some(i)
        None => path.rev_find("\\")
      }
      let name = match cut {
        Some(i) => path.view(start_offset=i + 1).to_string()
        None => path
      }
      let words = c.id("history/transcript")
      wh_line(
        c,
        fn() { @sf.icon(c, "file", size=wh_mark_side, color=t.p.muted) |> ignore },
        fn() {
          c.box(style=wh_line_words, id=words, taps=false, fn() {
            c.text(@sf.t("web-pages.chat.transcript") + " · ", style=wh_words) |> ignore
            c.text(name, style=wh_file) |> ignore
          })
          |> ignore
          @sf.tip(c, "history/transcript", words, path)
        },
        fn() {
          if wh_link(c, "history/copy-path", @sf.t("web-pages.chat.copyPath")) {
            c.copy_text(path)
            say(c, @sf.t("web-main.chat.transcriptCopied"))
          }
        },
      )
    }
  }
}

///|
/// Its context's 管理 (useContextActions): 压缩上下文 at once, 清空上下文 (in red) asked first; neither while one is under
/// way.
fn wh_context_menu(
  c : @ui.Ctx,
  src : Source,
  station : String,
  key : String,
  me : String,
  compacts : Bool,
  clears : Bool,
  busy : Bool,
) -> Unit {
  let open = history_own.context_menu.has_prefix(me + "\u{1}")
  let anchor = if history_own.context_menu == me + "\u{1}tile" {
    context_tile_id(c)
  } else {
    c.id("history/context")
  }
  let entries : Array[@kit.Entry] = []
  if compacts {
    entries.push(@kit.menu_item("compact", label=@sf.t("web-pages.chat.compact"), disabled=busy))
  }
  if clears {
    entries.push(@kit.menu_item("clear", label=@sf.t("web-pages.chat.clear"), disabled=busy))
  }
  let m = @sf.dropdown(c, "context-menu/" + me, open, anchor, entries, { "compact": "shrink", "clear": "refresh" }, 180.0)
  if open && !m.open {
    history_own.context_menu = ""
  }
  let params : Json = { "station": Json::string(station), "key": Json::string(key) }
  match m.chosen {
    Some("compact") => {
      history_own.context_menu = ""
      act(src, @sf.t("web-pages.chat.compact"), "", "session.compact", params)
    }
    Some("clear") => {
      history_own.context_menu = ""
      history_own.clear_asking = me
    }
    _ => ()
  }
  // asked as the web asks it (ChatPage.tsx: Confirm)
  let asked = @sf.confirm_dialog(
    c,
    "clear-context/" + me,
    history_own.clear_asking == me,
    @sf.t("web-pages.chat.clearConfirm"),
    @sf.t("web-pages.chat.clearBody"),
    @sf.t("web-pages.chat.clear"),
    cancel=@sf.t("common.cancel"),
  )
  if asked.confirmed {
    history_own.clear_asking = ""
    act(src, @sf.t("web-pages.chat.clear"), "", "session.clear", params)
  } else if history_own.clear_asking == me && !asked.open {
    history_own.clear_asking = ""
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
    c.text(words, style=if c.lit(id) { wh_link_hot } else { wh_dot }) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
  c.clicked(id)
}

///|
/// A line's mark's side (sessionLineMark: 16).
let wh_mark_side : Double = 16.0

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
let wh_head : @ui.Style = @ui.css("row w=Full h=S11 pl=S4 pr=S2 pb=SPx gap=S2 align=ACenter justify=JBetween")

///|
/// What it runs on and what needs seeing to (historyIdentity): what is too long cut at its end; the control's own 10 in
/// stood out by (its words on the line of the details' under it).
// kept across runs: a value (no field of it changes)
let wh_identity : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let wh_tools : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wh_summary_row : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// 只看收发 and 详情 (controls.css.ts textToggle): 2 by 4 in, 12 on 18, muted; the words' ink on hover; 只看收发 on, its
/// ground the picked one's.
// kept across runs: a value (no field of it changes)
let wh_toggle : @ui.Style = @ui.css("row px=S1 py=S0_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wh_toggle_on : @ui.Style = @ui.css("row px=S1 py=S0_5 gap=S1 align=ACenter bg=Selected radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let wh_toggle_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_toggle_hot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// 详情 (sessionDetails): 2 over, 16 at the sides, 14 under, 10 between; words 12, muted.
// kept across runs: a value (no field of it changes)
let wh_details_box : @ui.Style = @ui.css("w=Full px=S4 pt=S0_5 pb=S3_5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let wh_quiet : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted)

///|
/// The quiet line 4 nearer what is over it (sessionQuiet: outsetTop(4)).
// kept across runs: a value (no field of it changes)
let wh_quiet_box : @ui.Style = @ui.css("w=Full").then(@sf.outset_top(4.0))

///|
/// What needs seeing to, in its tone (ChatPage.css.ts attention: 12; the disk amber, an account red).
// kept across runs: a value (no field of it changes)
let wh_amber : @ui.TextStyle = @ui.text_style(size=Xs, color=Warn, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_red : @ui.TextStyle = @ui.text_style(size=Xs, color=Danger, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_line_style : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wh_mark : @ui.Style = @ui.css("w=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let wh_line_words : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let wh_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, w=Cut)

///|
/// The dot between a line's words and what is done at it, and a link at its end: kept whole.
// kept across runs: a value (no field of it changes)
let wh_dot : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_file : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let wh_link_box : @ui.Style = @ui.css("row align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wh_link_hot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// The steps under the head: the rest of the panel.
// kept across runs: a value (no field of it changes)
let wh_fill : @ui.Style = @ui.css("w=Full h=Full")
