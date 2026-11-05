// What is left up a long while on the workspace's stations (open_jobs's, OpenJobs.kt) at the foot of Home's lists, as
// nodes of the window's tree made once: each group under its heading, three of a group and the rest folded under 还有
// N 个; a row leads to its chat, its stop at its end. As tall as it is laid out there, nothing of the old frame's
// measured for it.

///|
/// The groups folded open (还有 N 个 pressed), by their keys.
// kept across runs: put back as a run begins (on_reset)
let open_jobs_unfolded : @signals.Signal[Array[String]] = @signals.signal([], same=fn(a, b) { a == b })

///|
/// A run begins with every group folded again.
fn init {
  @ui.on_reset(fn() { open_jobs_unfolded.set([]) })
}

///|
/// The block (open_jobs's) in `parent` for workspace `w`: 10 in at its sides, 4 over, 10 under, its groups 8 apart.
fn open_jobs_node(parent : @view.View, src : Source, w : Workspace) -> Unit {
  let groups = fn() { items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups") }
  parent.box(fn(b) {
    b.width_share(Is(1.0)).padding(Is((10.0, 4.0, 10.0, 10.0))).gap(Is(8.0)) |> ignore
    b.each(groups, fn(g) { text(Some(g), "key") }, fn(gv, g) { open_jobs_group_node(gv, src, g) })
  })
  |> ignore
}

///|
/// A group: its heading (caption, muted, 10 by 2 in), its rows (three and 还有 N 个 where there are more than four,
/// till that is pressed), 2 apart.
fn open_jobs_group_node(v : @view.View, src : Source, g : @signals.Signal[Json]) -> Unit {
  let gkey = fn() { "open-jobs/" + text(Some(g.get()), "key") }
  let list = fn() { items(Some(g.get()), "jobs") }
  let shown = fn() {
    let all = list()
    if open_jobs_unfolded.get().contains(gkey()) || all.length() <= 4 {
      all
    } else {
      all[:3].to_array()
    }
  }
  v.width_share(Is(1.0)).gap(Is(2.0)) |> ignore
  v.box(fn(h) {
    h.padding(Is((10.0, 2.0, 10.0, 2.0))) |> ignore
    open_jobs_head_node(h, fn() { text(Some(g.get()), "head") })
  })
  |> ignore
  v.each(shown, fn(j) { text(Some(j), "station") + "/" + text(Some(j), "id") }, fn(r, j) { open_job_row_node(r, src, j) })
  v.show(fn() { shown().length() < list().length() }, fn(m) {
    m.box(fn(more) {
      more.padding(Is((10.0, 3.0, 10.0, 3.0))).radius(Is(8.0)) |> ignore
      let words = fn() {
        fill("android-misc.openJobs.more", [("n", (list().length() - shown().length()).to_string())])
      }
      @sf.pressed_node(more, fn() { open_jobs_unfolded.set(open_jobs_unfolded.get() + [gkey()]) }, Is(8.0), Button, words)
      open_jobs_head_node(more, words)
    })
    |> ignore
  })
}

///|
/// A job left up (open_job_row's): its dot, its name over where it is and how long, 10 apart, 10 in at its start, 4 at
/// its end, 5 over and under, round 10; the row to its chat, its stop (32, round) at its end.
fn open_job_row_node(r : @view.View, src : Source, job : @signals.Signal[Json]) -> Unit {
  let j = fn() { Some(job.get()) }
  let station = fn() { text(j(), "station") }
  let id = fn() { text(j(), "id") }
  let skey = fn() { "job-stop/" + station() + "/" + id() }
  r.show(fn() { station() != "" }, fn(row) {
    row
    .row(Is(true))
    .width_share(Is(1.0))
    .padding(Is((10.0, 5.0, 4.0, 5.0)))
    .gap(Is(10.0))
    .radius(Is(10.0))
    .lines_up(Is(Some(Middle)))
    |> ignore
    @sf.pressed_node(
      row,
      fn() {
        let chat = field(j(), "chat")
        if chat is Some(Object(_)) {
          @sfbase.history_push()
          app.nav.push(Chat({ station: station(), session: text(chat, "id"), title: text(chat, "title"), station_name: "" }))
          // a service: its page over its chat (OpenJobs.kt OpenRow)
          if flag(j(), "service") {
            app.nav.push(Service(station(), id()))
          }
        }
      },
      Is(10.0),
      Button,
      fn() { text(j(), "name") },
    )
    // its dot, in a 16 wide column (job_dot's: 8 round, its tone's; breathing as it restarts)
    row.box(fn(d) {
      d.width(Is(Some(16.0))).lines_up(Is(Some(Middle))) |> ignore
      let dot = fn(at : @view.View) {
        at
        .width(Is(Some(8.0)))
        .height(Is(Some(8.0)))
        .radius(Is(4.0))
        .ground(By(fn() { job_tint(text(j(), "tone")).unwrap_or(@sf.theme().p.subtle) }))
        |> ignore
      }
      d.show(fn() { text(j(), "tone") == "restart" }, fn(at) {
        dot(at)
        @sf.breathe_node(at, low=0.35) |> ignore
      })
      d.show(fn() { text(j(), "tone") != "restart" }, fn(at) { dot(at) })
    })
    |> ignore
    row.box(fn(words) {
      words.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(words, fn() { text(j(), "name") }, fn() { open_job_name }) |> ignore
      @sf.words_node(words, fn() { text(j(), "whereText") + " · " + text(j(), "age") }, fn() { open_job_where }) |> ignore
    })
    |> ignore
    row.box(fn(stop) {
      stop.width(Is(Some(32.0))).height(Is(Some(32.0))).radius(Is(16.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
      |> ignore
      @sf.pressed_node(
        stop,
        fn() {
          if !doing(skey()) {
            @ui.haptic(Confirm)
            act(
              src,
              fill("android-misc.jobs.stopWhat", [("name", text(j(), "name"))]),
              skey(),
              "job.stop",
              { "station": Json::string(station()), "id": Json::string(id()) },
            )
          }
        },
        Is(16.0),
        Button,
        fn() { tr("android-misc.jobs.stop") },
      )
      stop.show(fn() { doing(skey()) }, fn(s) { @sf.spinner_node(s, size=12.0) |> ignore })
      stop.show(fn() { !doing(skey()) }, fn(s) {
        @sf.icon_node(s, "stop", 15.0, By(fn() { @sf.theme().p.muted })) |> ignore
      })
    })
    |> ignore
  })
}

///|
/// A group's heading and 还有 N 个 (caption, muted, one line) in node `parent`: on the theme's share of its size, as
/// words said only by their size are (open_jobs's), not the caption's own line.
fn open_jobs_head_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(w) {
    w
    .words(By(words))
    .words_look(By(fn() {
      let th = @ui.tree_theme()
      let size = th.text_size(Caption).0
      { size, weight: 400, line: th.text_line * size, wrap: false, tracking: @view.letters_own, balance: false }
    }))
    .ink(By(fn() { @sf.theme().p.muted }))
    |> ignore
  })
  |> ignore
}

///|
/// A job's name (14 on L5's 18, the ink, cut short on its line).
// kept across runs: a value (no field of it changes)
let open_job_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, leading=L5, w=Cut)

///|
/// Where it is and how long (caption on L4's 16, muted, cut short on its line).
// kept across runs: a value (no field of it changes)
let open_job_where : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false, leading=L4, w=Cut)
