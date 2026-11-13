// An agent's execution history in the desktop's side panel, its head as the web's (still.fail web/src/History.tsx's head,
// pages/ChatPage.tsx SessionHead, SessionDetails, HistorySummary; History.css.ts, ChatPage.css.ts): how it runs in one
// control (the model, how hard it thinks, the account: model_triple.mbt), what needs seeing to beside it; at the
// head's end 只看收发 and 详情. 详情 unfold under the head, open to begin with: what it has used (the large figures, a
// quiet line), then a line each, its mark leading: what runs it (Profile 详情), the station it runs on (what runs low
// on it), its context (管理: compacted, or cleared, asked first), where its runtime keeps the session's transcript
// (复制路径). All of it nodes of the window's tree, its steps under them sfpages' history_steps_node.mbt's.

///|
/// What the history keeps of its own (the rest is the core's): its details folded (for every history, as the web
/// keeps it); where its runtime keeps each session's transcript (by station and session; "" none), asked once.
priv struct HistoryOwn {
  shut : @signals.Signal[Bool]
  transcripts : Map[String, @signals.Signal[String]]
}

///|
// kept across runs: put back as a run begins (history_reset)
let history_own : HistoryOwn = { shut: @signals.signal(false, same=fn(a, b) { a == b }), transcripts: {} }

///|
fn history_reset() -> Unit {
  history_own.shut.set(false)
  history_own.transcripts.clear()
}

///|
/// The history's top: across the panel, on its ground.
// kept across runs: a value (no field of it changes)
let history_top_box : @ui.Style = @ui.css("w=Full bg=Bg")

///|
/// Agent `key`'s history's head in chat `r`'s panel, made once in `v` (under the panel's bar), as the chat says the
/// agent now: how it runs in one control and what needs seeing to beside it, 只看收发 and 详情 at its end; unfolded, its
/// details under it, a line under them. What is said over what is pointed at, in `tips`.
fn history_head_node(v : @view.View, src : Source, r : ChatRef, key : String, tips : @sf.TipLayer) -> Unit {
  let src = src.owned_by(v)
  let station = r.station
  let a = fn() { agent_json(src.topic("chat", chat_params(r)).get().value, key) }
  v.box(fn(top) {
    @sf.style_node(top, fn() { history_top_box })
    top.shrink(Is(0.0)) |> ignore
    top.box(fn(h) {
      @sf.style_node(h, fn() { wh_head })
      h.box(fn(id) {
        @sf.style_node(id, fn() { wh_identity }, in_row=true)
        id.min_width(Is(Some(0.0))) |> ignore
        @sfpages.model_triple_node(id, src, station, "session:" + key, saved=@sf.t("web-pages.chat.pickSaved"))
        id.show(at_once=true, fn() { items(a(), "attention").length() > 0 }, fn(s) { wh_summary_node(s, a, tips) })
      })
      |> ignore
      h.box(fn(k) {
        @sf.style_node(k, fn() { @sf.keys_row() }, in_row=true)
        k.shrink(Is(0.0)) |> ignore
        // 只看收发, its ground the picked one's while it is on
        let io = @sf.toggle_chip_node(
          k,
          fn() { @sf.t("web-main.history.onlyIo") },
          fn() { @sfpages.history_only_io() },
          fn() { @sfpages.history_only_io_flip() },
          icon="filter",
        )
        @sf.tip_node(tips, io, fn() { @sf.t("web-main.history.onlyIoTip") }) |> ignore
        // 详情, folded or not
        @sf.toggle_chip_node(
          k,
          fn() { @sf.t("web-main.history.details") },
          fn() { !history_own.shut.get() },
          fn() { history_own.shut.set(!history_own.shut.get()) },
          chevron=true,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
    top.show(fn() { !history_own.shut.get() }, fn(d) {
      wh_details_node(d, src, station, key, a, tips)
      // (its details set apart from its steps by a line across the panel: kept, 2026-10-25 用户「这两个的分割线可以保留」)
      d.box(fn(l) { @sf.style_node(l, fn() { @sfpages.triple_rule_h }) }) |> ignore
    })
  })
  |> ignore
}

///|
/// What needs seeing to now, beside the control (HistorySummary), as `a` says it: sfpages' history_attention_node in a
/// row of its own.
fn wh_summary_node(v : @view.View, a : () -> Json?, tips : @sf.TipLayer) -> Unit {
  v.box(fn(r) {
    @sf.style_node(r, fn() { wh_summary_row }, in_row=true)
    r.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    @sfpages.history_attention_node(r, a, tips, wh_amber, wh_red)
  })
  |> ignore
}

///|
/// 详情 (SessionDetails) made once in `v`, as agent `a` and its card say it now: what it has used (the large figures,
/// its context's opening 管理's menu, and a quiet line, the mark of its work past its turns at its end: work_mark_node;
/// a station older than the card's figures, its history's line), then a line each: what runs it (ending it while it is
/// kept warm; its account's page), the station it runs on (what runs low on it), its context, its transcript.
fn wh_details_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  a : () -> Json?,
  tips : @sf.TipLayer,
) -> Unit {
  let s = fn() { field(a(), "session") }
  let on = [("station", station), ("key", key)]
  let params : Map[String, Json] = { "station": Json::string(station), "key": Json::string(key) }
  let card = fn() { src.topic("agentCard", params).get().value }
  let host_held = @sfbase.hold(src, @sfbase.history_scope(station, key), "host", { "station": Json::string(station) })
  let host = fn() { host_held.get().value }
  let compacts = fn() { flag(s(), "canCompact") }
  let clears = fn() { flag(s(), "canClear") }
  // (what is under way and what failed a moment ago, as the core's `doing` says: useContextActions)
  let calls = ["session.compact", "session.clear"]
  let busy = fn() { core_doing(src, calls, on) }
  let failed = fn() { core_failed(src, calls, on) }
  let manage = fn(from : @sf.Beside) { @sfpages.open_context_actions(src, station, key, @signals.untracked(s), from) }
  v.box(fn(d) {
    @sf.style_node(d, fn() { wh_details_box })
    let tiles = fn() { text(card(), "cost") != "" || field(card(), "cache") is Some(_) || field(card(), "context") is Some(_) }
    d.pick(at_once=true, fn() { compacts() || clears() }, fn(t, opens) {
      if opens {
        @sfpages.usage_tiles_node(t, card, tips, context=manage, busy~, compacts~)
      } else {
        @sfpages.usage_tiles_node(t, card, tips)
      }
    })
    let quiet = fn() {
      if tiles() {
        [text(card(), "work"), text(card(), "tokens")].filter(fn(x) { x != "" }).join(" · ")
      } else {
        @sfpages.history_usage_line(src, station, key)
      }
    }
    // (and after it what it has going in the background and its checklist, a mark that opens them: the first to
    // give way, the line's own words whole till then)
    d.show(at_once=true, fn() { quiet() != "" }, fn(q) {
      @sf.style_node(q, fn() { wh_quiet_line })
      q.fits(Is(true)) |> ignore
      @sf.words_node(q, quiet, fn() { wh_quiet_one }).shrink(Is(1.0)).min_width(Is(Some(0.0))).fit_whole(Is(true)) |> ignore
      @sfpages.work_mark_node(q, src, station, key, wh_quiet_one, wh_quiet_link, link=wh_quiet_link, lead=" · ")
    })
    // what runs it, and its account's page
    wh_line_node(
      d,
      fn(m) { @sfpages.agent_mark_node(m, fn() { text(field(s(), "maker"), "id") }, fn() { text(s(), "runtime") }, wh_mark_side) },
      fn(w) {
        @sf.words_node(w, fn() { text(s(), "runtimeText") }, fn() { wh_words })
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
      },
      fn(e) {
        @sf.link_node(e, fn() { @sf.t("web-pages.chat.profileDetails") }, fn() {
          @sfbase.history_push()
          app.nav.push(Setting(@settings.Route::Profile(station, text(@signals.untracked(s), "profile"))))
        }, chevron=true)
        |> ignore
      },
    )
    // process state and evict action on their own single line aligned under the runtime name (never wrapped beside centered icons)
    d.show(at_once=true, fn() { text(s(), "processText") != "" || text(s(), "process") == "warm" }, fn(p) {
      wh_line_node(
        p,
        fn(_) {  },
        fn(w) {
          w.show(at_once=true, fn() { text(s(), "processText") != "" }, fn(t) {
            @sf.words_node(t, fn() { text(s(), "processText") }, fn() { wh_words })
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            |> ignore
          })
          w.show(at_once=true, fn() { text(s(), "process") == "warm" }, fn(e) {
            e.row(Is(true)).lines_up(Is(Some(Middle))).shrink(Is(0.0)) |> ignore
            e.show(at_once=true, fn() { text(s(), "processText") != "" }, fn(sep) {
              @sf.words_node(sep, fn() { " · " }, fn() { wh_words }) |> ignore
            })
            wh_evict_node(e, src, station, key, tips)
          })
        },
        fn(_) {  },
      )
    })
    // the station it runs on, what runs low on it at its end
    let look = fn() {
      @sfbase.station_marks(src, scope_of(station)).iter().find_first(fn(x) { x.address == station })
    }
    wh_line_node(
      d,
      fn(m) {
        m.pick(at_once=true, fn() { look().map(fn(st) { (st.emoji, st.icon) }) }, fn(x, mark) {
          match mark {
            Some((emoji, icon)) if emoji != "" || icon != "" =>
              @sf.station_mark_node(x, fn() { emoji }, fn() { icon }, wh_mark_side, fn() { @sf.theme().p.muted }, fn() { 0 })
            _ => @sf.icon_node(x, "server", wh_mark_side, By(fn() { @sf.theme().p.muted })) |> ignore
          }
        })
      },
      fn(w) {
        @sf.name_line_node(
          w,
          fn() {
            match look() {
              Some(st) if st.name != "" => st.name
              _ =>
                match text(host(), "hostname") {
                  "" => @sf.t("web-pages.chat.thisMachine")
                  h => h
                }
            }
          },
          fn() { wh_name },
          fn() {
            match text(host(), "identity") {
              "" => ""
              i => " · " + i
            }
          },
          fn() { wh_words },
        )
        .grow(Is(1.0))
        .shrink(Is(1.0))
        .basis(Is(Some(0.0)))
        |> ignore
      },
      fn(e) {
        let low = fn() { items(host(), "meters").filter(fn(m) { text(Some(m), "level") != "ok" }) }
        e.show(at_once=true, fn() { low().length() > 0 }, fn(x) { @sf.meter_chips_node(x, low, tips~) })
      },
    )
    // its context, by hand (ContextLine)
    d.show(at_once=true, fn() { compacts() || clears() }, fn(c) {
      wh_line_node(
        c,
        fn(m) { @sf.icon_node(m, "shrink", wh_mark_side, By(fn() { @sf.theme().p.muted })) |> ignore },
        fn(w) {
          @sf.words_node(w, fn() {
            let used = text(field(card(), "context"), "text")
            @sf.t("web-pages.chat.context") + (if used != "" { " · " + used } else { "" })
          }, fn() { wh_words })
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          |> ignore
        },
        fn(e) {
          @sfpages.doing_mark_node(e, busy, failed, tips~)
          @sf.link_opens_node(e, fn() { @sf.t("web-pages.chat.contextManage") }, fn(b) {
            let (x, y, w, h) = b.placed_window_now()
            manage(At(x, y, w, h))
          }, chevron=true)
          |> ignore
        },
      )
    })
    wh_transcript_node(d, src, station, key, tips)
  })
  |> ignore
}

///|
/// Its idle process, kept warm for the next message, ended now (Evict) in `v`: its link, a turning ring while it is
/// under way, a red mark a few seconds once it failed.
fn wh_evict_node(v : @view.View, src : Source, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let on = [("station", station), ("key", key)]
  let evicting = fn() { core_doing(src, ["session.evict"], on) }
  @sf.link_node(v, fn() { @sf.t("web-pages.chat.evict") }, fn() {
    if !@signals.untracked(evicting) {
      act(
        src,
        @sf.t("web-pages.chat.evict"),
        "",
        "session.evict",
        { "station": Json::string(station), "key": Json::string(key) },
        done=@sf.t("web-pages.chat.evicted"),
      )
    }
  })
  |> ignore
  @sfpages.doing_mark_node(v, evicting, fn() { core_failed(src, ["session.evict"], on) }, tips~)
}

///|
/// Where its runtime keeps the session's transcript on the station's machine (TranscriptLine), in `v`: its file's name
/// (the whole path in its tip), and its path to copy. Nothing before it is written, nor from a station from before it.
/// Asked once a run, as it is first made.
fn wh_transcript_node(v : @view.View, src : Source, station : String, key : String, tips : @sf.TipLayer) -> Unit {
  let me = station + "\u{1}" + key
  let path = match history_own.transcripts.get(me) {
    Some(p) => p
    None => {
      let p = @signals.signal("", same=fn(a, b) { a == b })
      history_own.transcripts[me] = p
      (src.call)("session.transcript", { "station": Json::string(station), "key": Json::string(key) }, fn(res) {
        match res {
          Ok(j) => p.set(text(Some(j), "path"))
          // not written yet, or a station from before it: nothing said
          Err(_) => ()
        }
      })
      p
    }
  }
  v.show(at_once=true, fn() { path.get() != "" }, fn(o) {
    let name = fn() {
      let whole = path.get()
      let cut = match whole.rev_find("/") {
        Some(i) => Some(i)
        None => whole.rev_find("\\")
      }
      match cut {
        Some(i) => whole.exact_view(start=i + 1).to_owned()
        None => whole
      }
    }
    wh_line_node(
      o,
      fn(m) { @sf.icon_node(m, "file", wh_mark_side, By(fn() { @sf.theme().p.muted })) |> ignore },
      fn(w) {
        let words = w.box(fn(b) {
          @sf.style_node(b, fn() { wh_line_words }, in_row=true)
          @sf.words_node(b, fn() { @sf.t("web-pages.chat.transcript") + " · " }, fn() { wh_words }).shrink(Is(0.0)) |> ignore
          b.box(fn(f) {
            f.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            f
            .words_runs(By(fn() { [@ui.span(name(), mono=true)] }))
            .words_look(By(fn() { @ui.style_words(wh_file) }))
            .ink(By(fn() { @ui.style_ink(wh_file) }))
            .cuts(Is(true))
            .allow_ellipsis(Is(true))
            |> ignore
          })
          |> ignore
        })
        @sf.tip_node(tips, words, fn() { path.get() }) |> ignore
      },
      fn(e) {
        @sf.link_node(
          e,
          fn() { @sf.t("web-pages.chat.copyPath") },
          fn() { @sfbase.copy_out(path.get(), said=@sf.t("web-main.chat.transcriptCopied")) },
          icon="copy",
        )
        |> ignore
      },
    )
  })
}

///|
/// A line of the details (sessionLine) in `v`: its mark (`mark`) in a 16 column, its words (`words`) cut at their end,
/// what can be done at its end (`end`).
fn wh_line_node(
  v : @view.View,
  mark : (@view.View) -> Unit,
  words : (@view.View) -> Unit,
  end : (@view.View) -> Unit,
) -> Unit {
  v.box(fn(l) {
    @sf.style_node(l, fn() { wh_line_style })
    l.box(fn(m) {
      @sf.style_node(m, fn() { wh_mark }, in_row=true)
      m.shrink(Is(0.0)) |> ignore
      mark(m)
    })
    |> ignore
    l.box(fn(w) {
      @sf.style_node(w, fn() { wh_line_words }, in_row=true)
      w.min_width(Is(Some(0.0))) |> ignore
      words(w)
    })
    |> ignore
    l.box(fn(e) {
      e.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(4.0)).shrink(Is(0.0)) |> ignore
      end(e)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A line's mark's side (sessionLineMark: 16).
let wh_mark_side : Double = 16.0

///|
/// A station's workspace, from its address (ws/station).
fn scope_of(station : String) -> String {
  match station.find("/") {
    Some(i) => station.exact_view(end=i).to_owned()
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
let wh_summary_row : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// 详情 (sessionDetails): 2 over, 16 at the sides, 14 under, 10 between; words 12, muted.
// kept across runs: a value (no field of it changes)
let wh_details_box : @ui.Style = @ui.css("w=Full px=S4 pt=S0_5 pb=S3_5 gap=S2_5")

///|
/// The quiet line 4 nearer what is over it (sessionQuiet: outsetTop(4)).
// kept across runs: a value (no field of it changes)
let wh_quiet_box : @ui.Style = @ui.css("w=Full").then(@sf.outset_top(4.0))

///|
/// The quiet line with the mark of its work past its turns after it (work_mark): one line, its words cut short only
/// once the mark has given way.
// kept across runs: a value (no field of it changes)
let wh_quiet_line : @ui.Style = wh_quiet_box.then(@ui.css("row align=ACenter"))

///|
// kept across runs: a value (no field of it changes)
let wh_quiet_one : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// What is pressed of the mark, under the pointer: a link's ink.
// kept across runs: a value (no field of it changes)
let wh_quiet_link : @ui.TextStyle = @ui.text_style(size=Meta, color=Link, wrap=false)

///|
/// What needs seeing to, in its tone (the disk amber, an account red).
// kept across runs: a value (no field of it changes)
let wh_amber : @ui.TextStyle = @ui.text_style(size=Meta, color=WarnInk, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let wh_red : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false, w=Cut)

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
let wh_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// The station's name: whole on its one line, what its machine is after it cut short first (itself only where it is
/// longer than the line leaves beside the least of that, as a last resort: @sf.name_line_node).
// kept across runs: a value (no field of it changes)
let wh_name : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wh_file : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=@sf.grow)
