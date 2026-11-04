// What still.fail itself says in a chat (message.mbt's system_notice) as nodes of the window's tree, made once: a pill
// across the chat in one line, a failure in red; pressed, all its words, what failed said of it, and its time under it;
// what is done of it at its words' end (installing a runtime the station lacks, reporting a failure), and a retry's own
// 取消 beside it while one waits.

///|
/// Notice `m` (as it is now) in `row` of a chat (`here`).
fn notice_node(row : @view.View, src : Source, here : () -> MessageHere, m : () -> Message) -> Unit {
  let ts = @signals.untracked(m).ts
  let open = @signals.signal(notices_open.get(ts).unwrap_or(false), same=fn(a, b) { a == b })
  let failed = fn() { m().notice_failed }
  let ink = fn() { if failed() { @sf.theme().p.red } else { @sf.theme().p.text } }
  let station = fn() { here().station }
  let retry = fn() { m().notice_retry_session != "" && here().list is Some(_) }
  row.gap(Is(4.0)).lines_up(Is(Some(Middle))) |> ignore
  row.box(fn(line) {
    line.row(Is(true)).max_width(Is(Some(@double.infinity))).lines_up(Is(Some(Middle))) |> ignore
    // (its pill: as wide as its words, 6 by 14 in, round at its ends (16 once opened); the hover ground, a failure's red)
    line.box(fn(pill) {
      pill
      .min_width(Is(Some(0.0)))
      .shrink(Is(1.0))
      .padding(Is((14.0, 6.0, 14.0, 6.0)))
      .radius(By(fn() { if open.get() { 16.0 } else { 999.0 } }))
      .ground(By(fn() { @ui.tree_theme().color(if failed() { DangerBg } else { Hover }) }))
      .says(By(fn() { Some(@view.said(Button, label=m().notice_words)) }))
      |> ignore
      @sf.presses_node(pill, fn() {
        let now = !@signals.untracked(fn() { open.get() })
        notices_open[ts] = now
        open.set(now)
      })
      pill.box(fn(words_line) {
        words_line.row(Is(true)).lines_up(Is(Some(End))) |> ignore
        words_line.box(fn(words) {
          words.min_width(Is(Some(0.0))).shrink(Is(1.0)).clips(Is(true)) |> ignore
          notice_words_node(words, m, open, ink, station)
        })
        |> ignore
        // (what is done of it at its words' end: installing what the station lacks, else reporting a failure)
        words_line.pick(fn() {
          let now = m()
          match now.install {
            Some(i) if i.action != "" => 1
            _ => if now.reportable { 2 } else { 0 }
          }
        }, fn(end, which) {
          match which {
            1 =>
              notice_action_node(end, fn() { m().install.map(fn(i) { i.action }).unwrap_or("") }, failed, fn() {
                match m().install {
                  Some(i) => install_busy(src, station(), i)
                  None => false
                }
              }, fn() {
                match m().install {
                  Some(i) => install_runtime(src, station(), i)
                  None => ()
                }
              })
            2 => {
              let on = fn() {
                let now = m()
                [("station", station()), ("thread", now.thread.to_int().to_string()), ("seq", now.seq.to_int().to_string())]
              }
              notice_action_node(end, fn() { @sf.t("common.report.action") }, failed, fn() {
                core_doing(src, ["chat.report"], on())
              }, fn() { notice_report(src, station(), m()) })
            }
            _ => ()
          }
        })
      })
      |> ignore
      // (what failed said of it, as it said it: opened only)
      pill.show(fn() { open.get() && m().notice_detail != "" }, fn(d) {
        d.padding(Is((0.0, 6.0, 0.0, 0.0))).gap(Is(6.0)) |> ignore
        d.box(fn(w) {
          w
          .words_runs(By(fn() { [@ui.span(m().notice_detail, mono=true)] }))
          .words_look(By(fn() { @ui.style_words(notice_detail) }))
          .ink(By(ink))
          |> ignore
        })
        |> ignore
        let copied = @signals.signal(false, same=fn(a, b) { a == b })
        d.box(fn(cp) {
          cp
          .words_runs(By(fn() { [@ui.span(@sf.t(if copied.get() { "common.copied" } else { "common.copy" }), underline=true)] }))
          .words_look(By(fn() { @ui.style_words(notice_act) }))
          .ink(By(ink))
          |> ignore
          @sf.presses_node(cp, fn() {
            @ui.current().copy_text(m().notice_detail)
            copied.set(true)
            cp.at_moment(cp.cause_at() + @sf.copied_ms, fn() { copied.set(false) }) |> ignore
          })
        })
        |> ignore
      })
    })
    |> ignore
    // (a retry waiting: its 取消 beside the pill, coming in and going as wide as it is)
    line.show(retry, fn(cancel) {
      cancel.padding(Is((6.0, 0.0, 0.0, 0.0))) |> ignore
      let session = fn() { m().notice_retry_session }
      @sf.button_node(
        cancel,
        fn() { @sf.t("common.cancel") },
        fn() {
          let now = m()
          act(src, @sf.t("common.cancel"), "", "session.cancelRetry", {
            "station": Json::string(station()),
            "key": Json::string(session()),
            "thread": Json::number(now.thread),
            "seq": Json::number(now.seq),
          })
        },
        busy=fn() { core_doing(src, ["session.cancelRetry"], [("station", station()), ("key", session())]) },
        disabled=fn() { src.read_only || here().view.offline },
      )
      |> ignore
    })
  })
  |> ignore
  // (opened: its time under it)
  row.show(fn() { open.get() }, fn(t) { message_time_node(t, fn() { m().time }, None) })
}

///|
/// A notice's words (system_notice's): about a profile, what went wrong a link to that profile's page; else as
/// Markdown, as the core read them, closed their first block on one line cut short.
fn notice_words_node(
  words : @view.View,
  m : () -> Message,
  open : @signals.Signal[Bool],
  ink : () -> Int64,
  station : () -> String,
) -> Unit {
  let linked = fn() {
    let now = m()
    now.profile != "" && now.notice_link >= 0 && now.notice_link <= now.notice_words.length()
  }
  words.pick(fn() { (linked(), open.get()) }, fn(w, which) {
    let (profile, opened) = which
    if profile {
      let runs = fn() {
        let now = m()
        let said = now.notice_words
        [
          @ui.span(said.view(end_offset=now.notice_link).to_string()),
          @ui.span(said.view(start_offset=now.notice_link).to_string(), underline=true, link="profile"),
        ]
      }
      w.box(fn(t) {
        t
        .words_runs(By(runs))
        .words_look(By(fn() { @ui.style_words(if opened { notice_words_open } else { notice_words }) }))
        .runs_look(Is({ ..@view.runs_plain, link: 0L, max_lines: if opened { 0 } else { 1 } }))
        .ink(By(ink))
        |> ignore
        @ui.runs_links(t, runs, fn(_) {
          let now = m()
          open_page(Setting(@settings.Route::Profile(station(), now.profile)))
        })
        |> ignore
      })
      |> ignore
    } else {
      // (the notice's one size, as the theme of the tree says it, and its lines' height over it)
      let meta = @signals.untracked(fn() { @ui.tree_theme().text_size(notice_size).0 })
      let line = @signals.untracked(fn() { @ui.tree_theme().leading(notice_leading).unwrap_or(0.0) }) / meta
      @sf.markdown_node(
        w,
        fn() { m().notice_words },
        tree=fn() { m().notice_md },
        size=fn() { meta },
        line~,
        ink=fn() { if m().notice_failed { @sf.theme().p.red } else { 0L } },
        on_link=fn(h) { open_link(h) },
        chat_title=fn(href) { m().linked(href).map(fn(l) { l.title }) },
        one_line=!opened,
        tracking=fn() { @ui.style_words(notice_words).tracking },
      )
      |> ignore
    }
  })
}

///|
/// What is done of a notice at its words' end (notice_action's): a dot, then its word underlined, at half while it is
/// under way; pressed, done.
fn notice_action_node(
  end : @view.View,
  action : () -> String,
  failed : () -> Bool,
  busy : () -> Bool,
  run : () -> Unit,
) -> Unit {
  end.row(Is(true)) |> ignore
  end.box(fn(dot) {
    dot.padding(Is((6.0, 0.0, 6.0, 0.0))) |> ignore
    @sf.words_node(dot, fn() { "·" }, fn() { if failed() { notice_dot_failed } else { notice_dot } }) |> ignore
  })
  |> ignore
  end.box(fn(a) {
    a
    .words_runs(By(fn() { [@ui.span(action(), underline=true)] }))
    .words_look(By(fn() { @ui.style_words(notice_act) }))
    .ink(By(fn() {
      let k = if failed() { @sf.theme().p.red } else { @sf.theme().p.text }
      if busy() { @sf.alpha(k, 0.5) } else { k }
    }))
    .says(By(fn() { Some(@view.said(Button, label=action())) }))
    |> ignore
    @sf.presses_node(a, fn() { if !busy() { run() } })
  })
  |> ignore
}

///|
/// A failure notice sent to the still.fail team (report_action's): asked first, saying what goes; what it was filed as
/// said once sent.
fn notice_report(src : Source, station : String, m : Message) -> Unit {
  let action = @sf.t("common.report.action")
  @sf.confirm(@sf.t("common.report.title"), @sf.t("common.report.lead") + "\n\n" + @sf.t("common.report.sends"), action, fn() {
    act(
      src,
      action,
      "",
      "chat.report",
      { "station": Json::string(station), "thread": Json::number(m.thread), "seq": Json::number(m.seq) },
      ok=fn(v) {
        @ui.haptic(Confirm)
        let number = match field(Some(v), "number") {
          Some(Number(n, ..)) => n.to_int().to_string()
          _ => "?"
        }
        toast_later(
          @sf.t(if flag(Some(v), "duplicate") { "common.report.again" } else { "common.report.done" }, args=[
            ("number", number),
          ]),
        )
      },
    )
  })
}
