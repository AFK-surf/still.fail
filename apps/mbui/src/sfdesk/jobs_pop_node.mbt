// The chat bar's services' popover's body on 中屏 and 大屏 (JobsPopover; jobs.mbt's jobs_popover till 2026-11-12) as
// nodes of the window's tree, made once as the panel the bar's 服务和后台任务 presents opens (chat_pops_node), each part
// bound to the core's `chatJobs` as it changes: what matters now (services up or restarting, jobs alive, what died
// lately), a job opening in place to its last few notices and last output with its stop and 在面板中查看, at its foot
// all of them in the 任务 tab. Laid out as the old view's was, by the same styles.

///|
/// The popover's body in `v` (jobs_popover's) for jobs of `station`, the core's `chatJobs` as `view` says it now: a
/// service pressed opens its tab (`service`), one that failed and the rest the 任务 tab at it (`tab`, "" none).
fn jobs_pop_node(v : @view.View, src : Source, station : String, view : () -> Json?, service : (String) -> Unit, tab : (String) -> Unit) -> Unit {
  let tips = match @sf.panel_tips_of(v) {
    Some(t) => t
    None => @sf.TipLayer::new(fn() { None })
  }
  let jobs = fn() { items(view(), "jobs") }
  v.pick(fn() { jobs().length() == 0 }, fn(p, none) {
    if none {
      p.box(fn(e) {
        @sf.style_node(e, fn() { jobs_empty })
        @sf.words_node(e, fn() { @sf.t("web-main.jobs.none") }, fn() { jobs_empty_title }) |> ignore
        @sf.words_node(e, fn() { @sf.t("web-main.jobs.noneNote") }, fn() { jobs_empty_words }) |> ignore
      })
      |> ignore
      return
    }
    p.box(fn(list) {
      @sf.style_node(list, fn() { jobs_list })
      let of_kind = fn(services : Bool) {
        jobs().filter(fn(j) { flag(Some(j), "service") == services }).map(fn(j) { text(Some(j), "id") })
      }
      // (its services, then its jobs: each group while it has any, each row by its job's id)
      for services in [true, false] {
        list.show(fn() { of_kind(services).length() > 0 }, fn(g) {
          @sf.style_node(g, fn() { jobs_group })
          jobs_pop_head(
            g,
            @sf.t(if services { "web-main.jobs.services" } else { "web-main.jobs.jobs" }),
            fn() { text(view(), if services { "servicesNote" } else { "jobsNote" }) },
          )
          g.each(fn() { of_kind(services) }, fn(id) { id }, fn(row, said) {
            let id = said.untracked()
            let job = fn() { jobs().iter().find_first(fn(j) { text(Some(j), "id") == id }) }
            if services {
              let failed = fn() { text(job(), "tone") == "fail" }
              jobs_pop_row(row, job, fn() { if failed() { "chevron-right" } else { "arrow-right" } }, fn() { false }, fn() {
                if @signals.untracked(failed) {
                  tab(id)
                } else {
                  service(id)
                }
              })
            } else {
              jobs_pop_fold(row, src, station, id, job, tab, tips)
            }
          })
        })
      }
    })
    |> ignore
    p.box(fn(foot) {
      @sf.style_node(foot, fn() { jobs_foot })
      let words = fn() { text(view(), "allText") + " · " + @sf.t("web-main.jobs.inPanel") }
      foot.box(fn(b) {
        @sf.style_node(b, fn() { jobs_all.then(jobs_pop_round) }, in_row=true)
        b.ground(By(fn() { if @sf.lit_node(b) { @sf.theme().p.hover } else { 0L } })).says(By(fn() { Some(@view.said(Button, label=words())) }))
        |> ignore
        @sf.presses_node(b, fn() { tab("") })
        @sf.words_node(b, words, fn() { if @sf.lit_node(b) { jobs_all_hot } else { jobs_all_words } }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A group's head in the popover (jobs_head's, inset where its rows' words are): its name, what the core notes of it
/// lighter after it.
fn jobs_pop_head(g : @view.View, name : String, note : () -> String) -> Unit {
  g.box(fn(h) {
    @sf.style_node(h, fn() { jobs_head_inset })
    @sf.words_node(h, fn() { name }, fn() { jobs_head_words }) |> ignore
    h.show(fn() { note() != "" }, fn(n) { @sf.words_node(n, note, fn() { jobs_head_note }) |> ignore })
  })
  |> ignore
}

///|
/// A job's row in the popover (job_row's, inset): its dot, its name, what it is up to, `end`'s icon at its end; picked
/// while `open` (the ground the pointer's), on the ground of the fold it heads then; `press` as it is pressed.
fn jobs_pop_row(row : @view.View, job : () -> Json?, end : () -> String, open : () -> Bool, press : () -> Unit) -> Unit {
  row.box(fn(b) {
    @sf.style_node(b, fn() { (if open() { job_row_static_inset } else { job_row_inset }).then(jobs_pop_round) })
    b
    .ground(By(fn() { if !open() && @sf.lit_node(b) { @sf.theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=text(job(), "name"))) }))
    |> ignore
    @sf.presses_node(b, press)
    b.box(fn(on) {
      @sf.style_node(on, fn() { job_row_on }, in_row=true)
      on.box(fn(d) {
        @sf.style_node(d, fn() { job_dot_room }, in_row=true)
        jobs_pop_dot(d, fn() { text(job(), "tone") })
      })
      |> ignore
      on.box(fn(w) {
        @sf.style_node(w, fn() { job_text }, in_row=true)
        @sf.words_node(w, fn() { text(job(), "name") }, fn() { if text(job(), "tone") == "off" { job_name_off } else { job_name } })
        .allow_ellipsis(Is(true))
        |> ignore
        jobs_pop_meta(w, job)
      })
      |> ignore
    })
    |> ignore
    b.box(fn(e) {
      @sf.style_node(e, fn() { job_end }, in_row=true)
      @sf.icon_node(e, "", 16.0, By(fn() { if @sf.lit_node(b) { @sf.theme().p.text } else { @sf.theme().p.subtle } }), name_now=end)
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A job's status (job_dot's) in `d`: a small dot, its tone's colour: alive breathing slowly round it (its breath out
/// from .6 to 1.15 and back, fading), restarting breathing to .35 and back; on the resident clock's steps, as the old
/// view's cycles were.
fn jobs_pop_dot(d : @view.View, tone : () -> String) -> Unit {
  d.pick(tone, fn(p, t) {
    p.box(fn(dot) {
      @sf.style_node(dot, fn() {
        match t {
          "up" | "live" => job_dot_up
          "restart" => job_dot_restart
          "fail" => job_dot_fail
          _ => job_dot_off
        }
      })
      if t == "restart" {
        dot.alpha(By(fn() {
          let f = dot.cycle_resident(@sf.breath_ms)
          let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
          1.0 - (1.0 - job_breath_low) * @ui.Ease::InOut.at(way)
        }))
        |> ignore
      }
      if t == "live" {
        dot.box(fn(halo) {
          @sf.style_node(halo, fn() { job_halo })
          halo.over(Is(true)).offset(Is((-job_halo_out, -job_halo_out))) |> ignore
          let way = fn() {
            let f = halo.cycle_resident(job_live_ms)
            if f < 0.5 {
              f * 2.0
            } else {
              2.0 - f * 2.0
            }
          }
          halo.scale(By(fn() { 0.6 + 0.55 * way() })).alpha(By(fn() { 0.35 * (1.0 - way()) })) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
}

///|
/// How faint a restarting job's dot breathes (breathe's `low` in job_dot).
// kept across runs: a value
let job_breath_low : Double = 0.35

///|
/// The line under a job's name (job_meta's) in `w`: its state's word in its dot's colour's ink, what it said in the
/// words', the rest muted, cut short on its line.
fn jobs_pop_meta(w : @view.View, job : () -> Json?) -> Unit {
  w.box(fn(m) {
    m
    .words_runs(By(fn() {
      let j = job()
      let t = @sf.theme()
      let word = match text(j, "tone") {
        "up" | "live" => t.p.green_ink
        "restart" => t.p.warn_ink
        "fail" => t.p.red
        _ => 0L
      }
      items(j, "meta").map(fn(p) {
        let pv = Some(p)
        match text(pv, "kind") {
          "word" => @ui.span(text(pv, "text"), color=word)
          "notice" => @ui.span(text(pv, "text"), color=t.p.text)
          _ => @ui.span(text(pv, "text"))
        }
      })
    }))
    .words_look(By(fn() { @ui.style_words(job_meta_words) }))
    .ink(By(fn() { @ui.style_ink(job_meta_words) }))
    .allow_ellipsis(Is(true))
    |> ignore
  })
  |> ignore
}

///|
/// A job of the popover (jobs_popover's fold) in `row`: its row, pressed opening it in place (jobs_own's `open`) or
/// closing it; open, on its ground, its last 3 notices, its last output, its stop while it runs and 在面板中查看 (`tab`).
fn jobs_pop_fold(
  row : @view.View,
  src : Source,
  station : String,
  id : String,
  job : () -> Json?,
  tab : (String) -> Unit,
  tips : @sf.TipLayer,
) -> Unit {
  let open = fn() { jobs_own.open.get() == id }
  row.box(fn(f) {
    @sf.style_node(f, fn() { if open() { jobs_fold_open.then(jobs_pop_round) } else { jobs_fold } })
    jobs_pop_row(f, job, fn() { if open() { "chevron-down" } else { "chevron-right" } }, open, fn() {
      jobs_own.open.set(if jobs_own.open.get() == id { "" } else { id })
    })
    f.show(open, fn(body) {
      @sf.style_node(body, fn() { jobs_fold_body })
      jobs_pop_notices(body, job)
      jobs_pop_last(body, src, station, job)
      body.box(fn(acts) {
        @sf.style_node(acts, fn() { job_actions })
        acts.show(fn() { text(job(), "state") == "running" }, fn(s) {
          let doing = fn() { job_stopping(src, station, job()) }
          jobs_pop_action(s, @sf.t("web-main.jobs.stop"), fn() { !doing().0 }, fn(m) {
            m.pick(fn() { doing().0 || doing().1 is Some(_) }, fn(k, busy) {
              if busy {
                @sfpages.doing_mark_node(k, fn() { doing().0 }, fn() { doing().1 }, tips~)
              } else {
                @sf.icon_node(k, "stop", 14.0, By(fn() { @sf.theme().p.muted })) |> ignore
              }
            })
          }, fn() { job_stop(src, station, @signals.untracked(job)) })
        })
        jobs_pop_action(acts, @sf.t("web-main.jobs.inPanel"), fn() { true }, fn(m) {
          @sf.icon_node(m, "panel-open", 14.0, By(fn() { @sf.theme().p.muted })) |> ignore
        }, fn() { tab(id) })
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// What a job said, newest first, each with how long ago (job_notices', 3 at most): none said, how a job says
/// something.
fn jobs_pop_notices(body : @view.View, job : () -> Json?) -> Unit {
  let notices = fn() {
    let all = items(job(), "notices")
    if all.length() > 3 {
      all[:3].to_owned()
    } else {
      all
    }
  }
  body.pick(fn() { notices().length() == 0 }, fn(p, none) {
    if none {
      p.box(fn(w) {
        w
        .words_runs(Is([
          @ui.span(@sf.t("web-main.jobs.noNotices.before")),
          @ui.span("stillfail-job notify", mono=true),
          @ui.span(@sf.t("web-main.jobs.noNotices.after")),
        ]))
        .words_look(By(fn() { @ui.style_words(job_quiet_words) }))
        .ink(By(fn() { @ui.style_ink(job_quiet_words) }))
        |> ignore
      })
      |> ignore
      return
    }
    p.box(fn(list) {
      @sf.style_node(list, fn() { job_notices_box })
      list.each(fn() { Array::makei(notices().length(), fn(i) { i }) }, fn(i) { i }, fn(n, at) {
        let i = at.untracked()
        let nv = fn() { notices().get(i) }
        n.box(fn(line) {
          @sf.style_node(line, fn() { job_notice })
          line.box(fn(a) {
            @sf.style_node(a, fn() { job_notice_ago }, in_row=true)
            // (64 at least, as wide as its words where they are wider: at the system's words set to 1.3 「10 分钟前」 is
            // 70, cut in the old view's 64 column; at the default size the same 64)
            a.width(Is(None)).min_width(Is(Some(job_notice_ago_w))).shrink(Is(0.0)) |> ignore
            @sf.words_node(a, fn() { text(nv(), "ago") }, fn() { job_notice_time }) |> ignore
          })
          |> ignore
          // (taking what the line leaves it, wrapped in it: job_notice_words' grow)
          @sf.words_node(line, fn() { text(nv(), "text") }, fn() { job_notice_words })
          .grow(Is(1.0))
          .basis(Is(Some(0.0)))
          .min_width(Is(Some(0.0)))
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
}

///|
/// The last line a job wrote, and when (job_last's): the job's own word for it until its output is read (the core's
/// `jobLog`, its last line), none where neither says anything.
fn jobs_pop_last(body : @view.View, src : Source, station : String, job : () -> Json?) -> Unit {
  let log = fn() {
    @sfbase.hold(src, @sfbase.jobs_scope(station), "jobLog", {
      "station": Json::string(station),
      "job": Json::string(text(job(), "id")),
      "lines": Json::number(1.0),
    }).get().value
  }
  let said = fn() { if log() is Some(Object(_)) { text(log(), "said") } else { text(job(), "outputSaid") } }
  body.show(fn() { said() != "" }, fn(b) {
    @sf.style_node(b, fn() { job_last_box })
    @sf.words_node(b, said, fn() { job_last_said }) |> ignore
    b.show(fn() { text(log(), "last") != "" }, fn(l) {
      l
      .words_runs(By(fn() { [@ui.span(text(log(), "last"), mono=true)] }))
      .words_look(By(fn() { @ui.style_words(job_last_line) }))
      .ink(By(fn() { @ui.style_ink(job_last_line) }))
      .allow_ellipsis(Is(true))
      |> ignore
    })
  })
}

///|
/// A small action of a job's (job_action's) in `parent`: its mark (`mark`) and `words`, 26 high, the pointer's ground on
/// it and the words' ink; `press` while `on` says so.
fn jobs_pop_action(parent : @view.View, words : String, on : () -> Bool, mark : (@view.View) -> Unit, press : () -> Unit) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { job_action_style }, in_row=true)
    b.ground(By(fn() { if @sf.lit_node(b) { @sf.theme().p.hover } else { 0L } })).says(Is(Some(@view.said(Button, label=words)))) |> ignore
    @sf.presses_node(b, press, on~)
    mark(b)
    @sf.words_node(b, fn() { words }, fn() { if on() && @sf.lit_node(b) { job_action_hot } else { job_action_words } }) |> ignore
  })
  |> ignore
}

///|
/// How wide a notice's time is at least (job_notice_ago's S16).
// kept across runs: a value
let job_notice_ago_w : Double = 64.0

///|
// kept across runs: a value (no field of it changes)
let jobs_pop_round : @ui.Style = @ui.style(radius=@sf.panel_in)
