// A chat's web services and background jobs on the desktop (ember web/src/Jobs.tsx, Jobs.css.ts): status a small dot
// before the name and a word on the line under it; the chat bar's popover shows what matters now (JobsPopover), the
// 任务 tab beside the chat everything (JobsTab). What a job's dot says, its word, the line under its name and every
// time in words are the core's (its `chatJobs` view, `jobLog`); what is done goes through its calls.

///|
/// What the jobs keep of their own: the job open in the popover ("" none), the one picked in the 任务 tab ("" the
/// first), whether the tab shows its output (else what it said).
priv struct JobsOwn {
  mut open : String
  mut picked : String
  mut output : Bool
}

///|
let jobs_own : JobsOwn = { open: "", picked: "", output: false }

///|
fn jobs_reset() -> Unit {
  jobs_own.open = ""
  jobs_own.picked = ""
  jobs_own.output = false
}

///|
/// The job picked in the 任务 tab (a row of the popover, a search's find).
pub fn pick_job(id : String) -> Unit {
  jobs_own.picked = id
}

///|
/// The job opened in the popover (a screen's fixture).
pub fn open_job_pop(id : String) -> Unit {
  jobs_own.open = id
}

///|
/// A job's status (JobDot): a small dot, on its name's line: up or alive green (alive breathing slowly round it),
/// restarting amber (breathing), failed red, else the strong line's grey.
fn job_dot(c : @ui.Ctx, tone : String) -> Unit {
  let dot = match tone {
    "up" | "live" => job_dot_up
    "restart" => job_dot_restart
    "fail" => job_dot_fail
    _ => job_dot_off
  }
  let n = c.box(style=dot, fn() {
    // alive: its breath out round it, from .6 to 1.15 and back, fading (jobLive); resident: up as long as it runs
    if tone == "live" {
      c.layer(fn() {
        let halo = c.box(style=job_halo, tx=-job_halo_out, ty=-job_halo_out, fn() {  })
        c.cycle_look(
          halo,
          job_live_ms,
          fn(f) {
            let p = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
            @ui.look(scale=0.6 + 0.55 * p, alpha=0.35 * (1.0 - p))
          },
          resident=true,
        )
      })
      |> ignore
    }
  })
  // restarting: breathing to .35 and back (jobBreathe)
  if tone == "restart" {
    @sf.breathe(c, n, low=0.35, resident=true)
  }
}

///|
/// How long an alive job's breath out takes (jobLive 2.4 s).
let job_live_ms : Double = 2400.0

///|
/// How far an alive job's breath reaches past its dot (inset -4).
let job_halo_out : Double = 4.0

///|
/// The line under a job's name (metaOf): its state's word in its dot's colour's ink (green's, amber's, red: the dot's
/// green read 3.5 to 1), what it said in the words', the rest muted.
fn job_meta(c : @ui.Ctx, job : Json?) -> Unit {
  let t = @sf.theme()
  let word = match text(job, "tone") {
    "up" | "live" => t.p.green_ink
    "restart" => t.p.warn_ink
    "fail" => t.p.red
    _ => 0L
  }
  let runs = items(job, "meta").map(fn(p) {
    let pv = Some(p)
    match text(pv, "kind") {
      "word" => @ui.span(text(pv, "text"), color=word)
      "notice" => @ui.span(text(pv, "text"), color=t.p.text)
      _ => @ui.span(text(pv, "text"))
    }
  })
  c.rich(runs, style=job_meta_words, allow_ellipsis=true) |> ignore
}

///|
/// A job's row (JobRow): its dot, its name, what it is up to; what is at its end (`end`: a service's arrow, a job's
/// chevron); picked (`selected`), over (faded); on a ground not its own (`grounded`: a job opened in the popover, its
/// row the top of the one piece it and its body are), no ground of its own. True on the frame after a press (`press`:
/// none for a row that does nothing).
fn job_row(
  c : @ui.Ctx,
  key : String,
  job : Json?,
  end? : String = "",
  selected? : Bool = false,
  press? : Bool = true,
  inset? : Bool = false,
  grounded? : Bool = false,
) -> Bool {
  let off = text(job, "tone") == "off"
  let id = c.id(key)
  let style = match (press && !grounded, inset) {
    (true, false) => job_row_style
    (true, true) => job_row_inset
    (false, false) => job_row_static
    (false, true) => job_row_static_inset
  }
  let b = c.box(style~, selected~, id~, fn() {
    c.box(style=job_row_on, fn() {
      c.box(style=job_dot_room, fn() { job_dot(c, text(job, "tone")) }) |> ignore
      c.box(style=job_text, fn() {
        c.text(text(job, "name"), style=if off { job_name_off } else { job_name }, allow_ellipsis=true) |> ignore
        job_meta(c, job)
      })
      |> ignore
    })
    |> ignore
    if end != "" {
      c.box(style=job_end, fn() {
        @sf.icon(c, end, size=16.0, color=if press && c.lit(id) {
          @sf.theme().p.text
        } else {
          @sf.theme().p.subtle
        })
        |> ignore
      })
      |> ignore
    }
  })
  c.semantics(b, Button, id~, label=text(job, "name"))
  press && c.clicked(id)
}

///|
/// What a job said, newest first, each with when (Notices): `limit` of them at most; with `clock` the time of day, in
/// the row's words (the 任务 tab's), else how long ago. None said: how a job says something.
fn job_notices(c : @ui.Ctx, job : Json?, limit? : Int = 0, clock? : Bool = false) -> Unit {
  let all = items(job, "notices")
  let notices = if limit > 0 && all.length() > limit { all[:limit].to_array() } else { all }
  if notices.length() == 0 {
    c.rich(
      [
        @ui.span(@sf.t("web-main.jobs.noNotices.before")),
        @ui.span("stillfail-job notify", mono=true),
        @ui.span(@sf.t("web-main.jobs.noNotices.after")),
      ],
      style=job_quiet_words,
    )
    |> ignore
    return
  }
  c.box(style=if clock { job_notices_clock } else { job_notices_box }, fn() {
    for n in notices {
      let nv = Some(n)
      c.box(style=job_notice, fn() {
        c.box(style=if clock { job_notice_clock } else { job_notice_ago }, fn() {
          c.text(text(nv, if clock { "clock" } else { "ago" }), style=if clock {
            job_notice_time_ui
          } else {
            job_notice_time
          })
          |> ignore
        })
        |> ignore
        c.text(text(nv, "text"), style=if clock { job_notice_words_ui } else { job_notice_words }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The last line a job wrote, and when (LastOutput: the job's own word for it until its output is read).
fn job_last(c : @ui.Ctx, src : Source, station : String, job : Json?) -> Unit {
  let log = @sfbase.hold(src, @sfbase.jobs_scope(station), "jobLog", {
    "station": Json::string(station),
    "job": Json::string(text(job, "id")),
    "lines": Json::number(1.0),
  }).value
  let read = log is Some(Object(_))
  let said = if read { text(log, "said") } else { text(job, "outputSaid") }
  if said == "" {
    return
  }
  c.box(style=job_last_box, fn() {
    c.text(said, style=job_last_said) |> ignore
    match text(log, "last") {
      "" => ()
      l => c.rich([@ui.span(l, mono=true)], style=job_last_line) |> ignore
    }
  })
  |> ignore
}

///|
/// Stopping a job from the page (useStopJob, JobStop): its agent is told who did; turning, not pressed again, while
/// it is being stopped wherever that was asked (the core's `doing`), a red mark a few seconds when that failed.
fn job_stopping(src : Source, station : String, job : Json?) -> (Bool, String?) {
  let on = [("station", station), ("id", text(job, "id"))]
  (core_doing(src, ["job.stop"], on), core_failed(src, ["job.stop"], on))
}

///|
fn job_stop(src : Source, station : String, job : Json?) -> Unit {
  act(
    src,
    @sf.t("web-main.jobs.stopWhat", args=[("name", text(job, "name"))]),
    "",
    "job.stop",
    { "station": Json::string(station), "id": Json::string(text(job, "id")) },
  )
}

///|
/// Clearing a chat's jobs that are over (ClearEnded): the button says how many, turning while they go (a red mark a
/// moment if not).
fn jobs_clear(c : @ui.Ctx, src : Source, station : String, view : Json?, inset? : Bool = false) -> Unit {
  let on = [("station", station)]
  let clearing = core_doing(src, ["job.clearEnded"], on)
  let id = c.id("jobs/clear")
  if !clearing && c.clicked(id) {
    for session in items(view, "clear") {
      match session {
        String(s) =>
          act(src, @sf.t("web-main.jobs.clearWhat"), "", "job.clearEnded", {
            "station": Json::string(station),
            "session": Json::string(s),
          })
        _ => ()
      }
    }
  }
  let b = c.box(style=if inset { jobs_clear_inset } else { jobs_clear_style }, id~, fn() {
    @settings.doing_mark(c, clearing, core_failed(src, ["job.clearEnded"], on), inline=true)
    c.text(text(view, "clearText"), style=if inset { jobs_clear_words_sm } else { jobs_clear_words }) |> ignore
  })
  c.semantics(b, Button, id~, label=text(view, "clearText"))
}

///|
/// A group's head (jobsHead): its name, what the core notes of it lighter after it; in the popover (`inset`) where its
/// rows' words are, a small panel's heading.
fn jobs_head(c : @ui.Ctx, name : String, note : String, inset? : Bool = false) -> Unit {
  c.box(style=if inset { jobs_head_inset } else { jobs_head_box }, fn() {
    c.text(name, style=jobs_head_words) |> ignore
    if note != "" {
      c.text(note, style=jobs_head_note) |> ignore
    }
  })
  |> ignore
}

///|
/// The chat bar's popover's body (JobsPopover): what matters now (services up or restarting, jobs alive, what died
/// lately); a service pressed opens its tab (`service`), one that failed and the rest the 任务 tab at it (`tab`); a job
/// opens in place to its last few notices and last output, with its stop and 在面板中查看. At its foot all of them in
/// the 任务 tab, and clearing what is over.
pub fn jobs_popover(
  c : @ui.Ctx,
  src : Source,
  station : String,
  view : Json?,
  service : (String) -> Unit,
  tab : (String) -> Unit,
) -> Unit {
  let jobs = items(view, "jobs")
  if jobs.length() == 0 {
    c.box(style=jobs_empty, fn() {
      c.text(@sf.t("web-main.jobs.none"), style=jobs_empty_title) |> ignore
      c.text(@sf.t("web-main.jobs.noneNote"), style=jobs_empty_words) |> ignore
    })
    |> ignore
    return
  }
  let shown = jobs.filter(fn(j) { flag(Some(j), "current") })
  let services = shown.filter(fn(j) { flag(Some(j), "service") })
  let plain = shown.filter(fn(j) { !flag(Some(j), "service") })
  c.box(style=jobs_list, fn() {
    if services.length() > 0 {
      c.box(style=jobs_group, fn() {
        jobs_head(c, @sf.t("web-main.jobs.services"), text(view, "servicesNote"), inset=true)
        for j in services {
          let jv = Some(j)
          let id = text(jv, "id")
          let failed = text(jv, "tone") == "fail"
          if job_row(c, "jobs-pop/" + id, jv, end=if failed { "chevron-right" } else { "arrow-right" }, inset=true) {
            if failed {
              tab(id)
            } else {
              service(id)
            }
          }
        }
      })
      |> ignore
    }
    if plain.length() > 0 {
      c.box(style=jobs_group, fn() {
        jobs_head(c, @sf.t("web-main.jobs.jobs"), text(view, "jobsNote"), inset=true)
        for j in plain {
          let jv = Some(j)
          let id = text(jv, "id")
          let open = jobs_own.open == id
          c.box(style=if open { jobs_fold_open } else { jobs_fold }, fn() {
            if job_row(
                c,
                "jobs-pop/" + id,
                jv,
                end=if open { "chevron-down" } else { "chevron-right" },
                selected=open,
                inset=true,
                grounded=open,
              ) {
              jobs_own.open = if open { "" } else { id }
            }
            if open {
              c.box(style=jobs_fold_body, fn() {
                job_notices(c, jv, limit=3)
                job_last(c, src, station, jv)
                c.box(style=job_actions, fn() {
                  if text(jv, "state") == "running" {
                    let (stopping, failed) = job_stopping(src, station, jv)
                    if job_action(c, "jobs-pop/stop/" + id, fn() {
                        if stopping || failed is Some(_) {
                          @settings.doing_mark(c, stopping, failed, inline=true)
                        } else {
                          @sf.icon(c, "stop", size=14.0, color=@sf.theme().p.muted) |> ignore
                        }
                      }, @sf.t("web-main.jobs.stop"), !stopping) {
                      job_stop(src, station, jv)
                    }
                  }
                  if job_action(c, "jobs-pop/tab/" + id, fn() {
                      @sf.icon(c, "panel-open", size=14.0, color=@sf.theme().p.muted) |> ignore
                    }, @sf.t("web-main.jobs.inPanel"), true) {
                    tab(id)
                  }
                })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
  if shown.length() == 0 {
    c.box(style=jobs_quiet_at, fn() { c.text(@sf.t("web-main.jobs.quiet"), style=jobs_quiet) |> ignore }) |> ignore
  }
  c.box(style=jobs_foot, fn() {
    let all = c.id("jobs-pop/all")
    if c.clicked(all) {
      tab("")
    }
    let words = text(view, "allText") + " · " + @sf.t("web-main.jobs.inPanel")
    let b = c.box(style=jobs_all, id=all, fn() {
      c.text(words, style=if c.lit(all) { jobs_all_hot } else { jobs_all_words }) |> ignore
    })
    c.semantics(b, Button, id=all, label=words)
    // what the popover leaves out is all over: the button to clear them says how many
    if number(view, "ended") > 0.0 {
      jobs_clear(c, src, station, view, inset=true)
    }
  })
  |> ignore
}

///|
/// A small action of a job's (jobAction): its mark and words, 26 high; the picked ground and the words' ink on hover.
/// True on the frame after a press (none while `on` is false).
fn job_action(c : @ui.Ctx, key : String, mark : () -> Unit, words : String, on : Bool) -> Bool {
  let id = c.id(key)
  let b = c.box(style=job_action_style, id~, fn() {
    mark()
    c.text(words, style=if on && c.lit(id) { job_action_hot } else { job_action_words }) |> ignore
  })
  c.semantics(b, Button, id~, label=words)
  on && c.clicked(id)
}

///|
/// The 任务 tab beside the chat (JobsTab): every service and job (those over faded, last); a service up or restarting
/// opens its tab (`service`); a job picked (the first while none is) shows what it said, or its output as it grows,
/// under its name, state and command.
pub fn jobs_tab(c : @ui.Ctx, src : Source, station : String, chat : String, view : Json?, service : (String) -> Unit) -> Unit {
  let all = items(view, "jobs")
  if all.length() == 0 {
    @sf.empty(c, fn() { c.text(@sf.t("web-main.jobs.noneInChat"), style=jobs_empty_words) |> ignore })
    return
  }
  let services = all.filter(fn(j) { flag(Some(j), "service") })
  let plain = all.filter(fn(j) { !flag(Some(j), "service") })
  let job = match plain.iter().find_first(fn(j) { text(Some(j), "id") == jobs_own.picked }) {
    Some(j) => Some(j)
    None => plain.get(0)
  }
  c.box(style=jobs_tab_box, fn() {
    // the list, 45% of the tab at most, scrolling past that (as tall as its rows and heads are, less)
    let most = c.height * jobs_list_most
    let heads = (if services.length() > 0 { 1 } else { 0 }) + (if plain.length() > 0 { 1 } else { 0 })
    let tall = (services.length() + plain.length()).to_double() * job_row_h +
      heads.to_double() * jobs_head_h +
      jobs_list_room +
      (if number(view, "ended") > 0.0 { jobs_clear_h } else { 0.0 })
    let h = if tall < most { tall } else { most }
    c.box(style=jobs_tab_list_room.then(@ui.style(h=Fixed(h))), fn() {
      c.list("jobs-tab/" + chat, 1, 200.0, fn(_) {
        c.box(style=jobs_tab_list, fn() {
          if services.length() > 0 {
            c.box(style=jobs_group, fn() {
              jobs_head(c, @sf.t("web-main.jobs.services"), "")
              for j in services {
                let jv = Some(j)
                let opens = text(jv, "tone") == "up" || text(jv, "tone") == "restart"
                if job_row(c, "jobs-tab/" + text(jv, "id"), jv, end=if opens { "arrow-right" } else { "" }, press=opens) {
                  service(text(jv, "id"))
                }
              }
            })
            |> ignore
          }
          if plain.length() > 0 {
            c.box(style=if services.length() > 0 { jobs_group_after } else { jobs_group }, fn() {
              jobs_head(c, @sf.t("web-main.jobs.jobs"), "")
              for j in plain {
                let jv = Some(j)
                let id = text(jv, "id")
                let on = match job {
                  Some(p) => text(Some(p), "id") == id
                  None => false
                }
                if job_row(c, "jobs-tab/" + id, jv, selected=on) {
                  jobs_own.picked = id
                }
              }
            })
            |> ignore
          }
          if number(view, "ended") > 0.0 {
            jobs_clear(c, src, station, view)
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    match job {
      Some(j) => job_detail(c, src, station, Some(j))
      None => ()
    }
  })
  |> ignore
}

///|
/// A job picked in the 任务 tab (jobDetail): on the paper, its dot, name and state, what it said or its output (a
/// choice of the two), its stop while it runs; its command under them, whole in its tip; then what it said with the
/// time of day and its last output, or its output as it grows.
fn job_detail(c : @ui.Ctx, src : Source, station : String, job : Json?) -> Unit {
  let id = text(job, "id")
  let running = text(job, "state") == "running"
  c.box(style=job_detail_box.then(@sf.pane_foot_card()).then(job_detail_at(running)), fn() {
    c.box(style=job_detail_head, fn() {
      job_dot(c, text(job, "tone"))
      c.text(text(job, "name"), style=job_detail_name) |> ignore
      c.text(text(job, "detail"), style=job_detail_state) |> ignore
      c.box(style=job_detail_grow, fn() {  }) |> ignore
      // (kept as it is: the name and the state are what is cut short, as the web's segmented, flex: none)
      c.box(style=job_detail_choice, keep=true, fn() {
        let labels = [@sf.t("web-main.jobs.notices"), @sf.t("web-main.jobs.output")]
        let picked = @sf.segmented(c, "jobs-tab/show", labels, if jobs_own.output { 1 } else { 0 })
        jobs_own.output = picked == 1
      })
      |> ignore
      if running {
        let (stopping, failed) = job_stopping(src, station, job)
        let sid = c.id("jobs-tab/stop")
        if !stopping && c.clicked(sid) {
          job_stop(src, station, job)
        }
        let b = c.box(style=job_detail_stop, id=sid, fn() {
          if stopping || failed is Some(_) {
            @settings.doing_mark(c, stopping, failed)
          } else {
            @sf.icon(c, "stop", size=16.0, color=if c.lit(sid) {
              @sf.theme().p.text
            } else {
              @sf.theme().p.muted
            })
            |> ignore
          }
        })
        c.semantics(b, Button, id=sid, label=@sf.t("web-main.jobs.stop"))
        @sf.tip(c, "jobs-tab/stop", sid, @sf.t("web-main.jobs.stop"))
      }
    })
    |> ignore
    let command = text(job, "command")
    if command != "" {
      let cid = c.id("jobs-tab/command")
      c.box(style=job_detail_command, id=cid, taps=false, points=true, fn() {
        c.rich([@ui.span(command, mono=true)], style=job_command_words) |> ignore
      })
      |> ignore
      @sf.tip(c, "jobs-tab/command", cid, command, repeats=true)
    }
    if jobs_own.output {
      job_output(c, src, station, id)
    } else {
      c.box(style=job_detail_notices, fn() {
        c.list("jobs-tab/notices/" + id, 1, 200.0, fn(_) { job_notices(c, job, clock=true) }) |> ignore
      })
      |> ignore
      c.box(style=job_detail_last, fn() { job_last(c, src, station, job) }) |> ignore
    }
  })
  |> ignore
}

///|
/// A job's output (Output: its last 400 lines), in a terminal's colours where the core says them, following its end
/// while it is scrolled there.
fn job_output(c : @ui.Ctx, src : Source, station : String, id : String) -> Unit {
  let t = @sf.theme()
  c.box(style=job_output_box, fn() {
    match @sfbase.job_output_lines(src, station, id, job_output_lines, t.p.text, t.dark) {
      Some([]) => c.text(@sf.t("web-main.jobs.noOutput"), style=job_output_none) |> ignore
      Some(lines) =>
        c.list(
          "jobs-tab/output/" + id,
          lines.length(),
          job_output_line,
          fn(i) { c.rich(lines[i], style=job_output_words) |> ignore },
          stick_end=true,
        )
        |> ignore
      None => @sf.wait_line(c, "", key="jobs-tab/output/" + id)
    }
  })
  |> ignore
}

///|
/// How much of a job's output is read (Output: 400), how tall a line of it is (11.5 on 1.6, about 18), how much of
/// the tab its list may take (jobsTabList: 45%).
let job_output_lines : Double = 400.0

///|
let job_output_line : Double = 18.0

///|
let jobs_list_most : Double = 0.45

///|
/// How tall a job's row stands (its two lines and its padding, 4 apart), a group's head, the list's padding, clearing.
let job_row_h : Double = 54.0

///|
let jobs_head_h : Double = 30.0

///|
let jobs_list_room : Double = 18.0

///|
let jobs_clear_h : Double = 38.0

///|
/// A job's dot (jobDot): 8 across, round.
// kept across runs: a value (no field of it changes)
let job_dot_off : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Border")

///|
// kept across runs: a value (no field of it changes)
let job_dot_up : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Positive")

///|
// kept across runs: a value (no field of it changes)
let job_dot_restart : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Warn")

///|
// kept across runs: a value (no field of it changes)
let job_dot_fail : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Danger")

///|
/// An alive job's breath round its dot: 16 across (inset -4), the online green.
// kept across runs: a value (no field of it changes)
let job_halo : @ui.Style = @ui.css("w=S4 h=S4 radius=Full bg=Positive")

///|
/// The dot on the name's line (20 high): 6 down.
// kept across runs: a value (no field of it changes)
let job_dot_room : @ui.Style = @ui.css("pt=S1_5")

///|
/// A job's row (jobRow): its dot and words 12 apart, 6 by 8 in (12 at its start); round as an option, the pointer's
/// ground on it, the picked ground while picked; in the popover in by the panel's words (10), round with it.
// kept across runs: a value (no field of it changes)
let job_row_style : @ui.Style = @ui.css(
  #|row w=Full py=S1_5 pl=S3 pr=S2 gap=S3 align=AStart radius=Xl hovered{bg=Hover} selected{bg=Selected}
)

///|
// kept across runs: a value (no field of it changes)
let job_row_inset : @ui.Style = @ui.css(
  #|row w=Full py=S1_5 px=S2_5 gap=S3 align=AStart radius=Inner hovered{bg=Hover} selected{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let job_row_static : @ui.Style = @ui.css("row w=Full py=S1_5 pl=S3 pr=S2 gap=S3 align=AStart radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let job_row_static_inset : @ui.Style = @ui.css("row w=Full py=S1_5 px=S2_5 gap=S3 align=AStart radius=Inner")

///|
/// Its dot and words; over, its name stepped back to the muted grey (data-off), not faded (at 55% its words were 2.3 to
/// 1: docs/ui-panels.md 对比度).
// kept across runs: a value (no field of it changes)
let job_row_on : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S3, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let job_text : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// Its name (13, 500, on 20), what it is up to under it (12, muted), each a line.
// kept across runs: a value (no field of it changes)
let job_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let job_name_off : @ui.TextStyle = job_name.then(@ui.text_style(color=Muted))

///|
// kept across runs: a value (no field of it changes)
let job_meta_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// What is at its end (jobEnd): 24 wide, at the middle of its two lines.
// kept across runs: a value (no field of it changes)
let job_end : @ui.Style = @ui.css("w=S6 pt=S2_5 align=ACenter")

///|
/// What a job said (jobNotices): 6 apart, 12; with the time of day 12 apart, 13; the time in a column of its own.
// kept across runs: a value (no field of it changes)
let job_notices_box : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let job_notices_clock : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let job_notice : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
/// Its time's column (5.6em of 12, about 68; 3.4em of 13, about 44).
// kept across runs: a value (no field of it changes)
let job_notice_ago : @ui.Style = @ui.css("w=S16")

///|
// kept across runs: a value (no field of it changes)
let job_notice_clock : @ui.Style = @ui.css("w=S11")

///|
// kept across runs: a value (no field of it changes)
let job_notice_time : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let job_notice_time_ui : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let job_notice_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let job_notice_words_ui : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let job_quiet_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// Its last output (jobLast): 10 over it, 2 apart; when (11, subtle), the line in mono, cut at its end.
// kept across runs: a value (no field of it changes)
let job_last_box : @ui.Style = @ui.css("w=Full pt=S2_5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let job_last_said : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, w=Full)

///|
// kept across runs: a value (no field of it changes)
let job_last_line : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false, max_lines=1)

///|
/// Its actions (jobActions): 2 apart, 6 under what is over them, 8 out at their start; each 26 high, 8 in, its mark and
/// words 5 apart, the pointer's ground on hover (over the row's, lit with it: docs/ui-panels.md 悬停).
// kept across runs: a value (no field of it changes)
let job_actions : @ui.Style = @ui.css("row pt=S1_5 gap=S0_5").then(@sf.outset_start(8.0))

///|
// kept across runs: a value (no field of it changes)
let job_action_style : @ui.Style = @ui.style(
  row=true,
  h=@sf.job_action_h,
  px=S2,
  gap=S1_25,
  align=ACenter,
  radius=Lg,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let job_action_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let job_action_hot : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// A group's head (jobsHead): 8 over, 12 in, 4 under; 12 in 500, muted; its note in 400, subtle, 6 after.
// kept across runs: a value (no field of it changes)
let jobs_head_box : @ui.Style = @ui.css("row w=Full pt=S2 px=S3 pb=S1 gap=S1_5 align=AEnd")

///|
/// In the popover: a small panel's heading, its words as far in as its rows' (a row's padding) and as far under what
/// is over them as a row's words (at the panel's top, where a menu's first item's words are), 4 over its rows.
// kept across runs: a value (no field of it changes)
let jobs_head_inset : @ui.Style = @ui.css("row w=Full pt=S1_5 px=S2_5 pb=S1 gap=S1_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let jobs_head_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let jobs_head_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// A group's rows, 4 apart; one after another 6 under it (the 任务 tab's).
// kept across runs: a value (no field of it changes)
let jobs_group : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let jobs_group_after : @ui.Style = @ui.css("w=Full pt=S1_5 gap=S1")

///|
/// The popover's groups, and a job opened in it (jobFold): its row and its body under it one piece on the pointer's
/// ground, round as a row, 4 under it; the body 4 by 8 in, its words in the names' column (jobs_names_in).
// kept across runs: a value (no field of it changes)
let jobs_list : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let jobs_fold : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let jobs_fold_open : @ui.Style = @ui.css("w=Full mb=S1 bg=Hover radius=Inner")

///|
// kept across runs: a value (no field of it changes)
let jobs_fold_body : @ui.Style = @ui.style(w=Full, pt=S1, pr=S2, pb=S2, pl=@sf.room_of(jobs_names_in))

///|
/// Nothing now (jobsQuiet): 8 over, in the names' column (as the foot's words: jobs_all), 13 muted.
// kept across runs: a value (no field of it changes)
let jobs_quiet : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let jobs_quiet_at : @ui.Style = @ui.style(w=Full, pt=S2, pl=@sf.room_of(jobs_names_in))

///|
/// The names' column in the popover: a row's padding, a job's dot (8) and the 12 after it (job_row_inset, job_row_on).
let jobs_names_in : Double = @sf.text_in + job_dot_w + job_dot_gap

///|
let job_dot_w : Double = 8.0

///|
let job_dot_gap : Double = 12.0

///|
/// The popover's foot (jobsFoot): 6 under its groups, 4 apart; all of them a row 38 high, its words in the names'
/// column (a row's padding, its dot's 8 and the 12 after it: job_row_inset, job_row_on), muted, the words' ink on the
/// pointer's ground; clearing beside it.
// kept across runs: a value (no field of it changes)
let jobs_foot : @ui.Style = @ui.css("row w=Full mt=S1_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let jobs_all : @ui.Style = @ui.style(
  row=true,
  w=@sf.grow,
  h=@sf.jobs_row_h,
  pl=@sf.room_of(jobs_names_in),
  pr=S2_5,
  align=ACenter,
  // (in the popover's foot corner concentric with it; where it lies in none, as it scrolls under, a row's)
  radius=InnerOr(@sf.row_radius),
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let jobs_all_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let jobs_all_hot : @ui.TextStyle = jobs_all_words.then(@ui.text_style(color=Fg))

///|
/// Clearing what is over (jobsClear): 38 high, 12 in, its turning mark and words 6 apart, the pointer's ground on it;
/// in the popover in by the panel's words, 12.
// kept across runs: a value (no field of it changes)
let jobs_clear_style : @ui.Style = @ui.style(
  row=true,
  h=@sf.jobs_row_h,
  px=S3,
  gap=S1_5,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let jobs_clear_inset : @ui.Style = @ui.style(
  row=true,
  h=@sf.jobs_row_h,
  px=S2_5,
  gap=S1_5,
  align=ACenter,
  radius=Inner,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let jobs_clear_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let jobs_clear_words_sm : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// None at all (jobsEmpty): 26 by 20 in, in the middle, 4 apart; its title 13 in 500.
// kept across runs: a value (no field of it changes)
let jobs_empty : @ui.Style = @ui.css("w=Full py=S6 px=S5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let jobs_empty_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let jobs_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
/// The 任务 tab (jobsTab): its list (4 over, 8 at the sides and under), the job picked under it.
// kept across runs: a value (no field of it changes)
let jobs_tab_box : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let jobs_tab_list_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let jobs_tab_list : @ui.Style = @ui.css("w=Full pt=S1 px=S2 pb=S2")

///|
/// The job picked (jobDetail): a card across the tab's foot (in a panel's foot corners, concentric with them:
/// @sf.pane_foot_card), 14 at its start, on the paper; over and at its end as its head stands (job_detail_at).
// kept across runs: a value (no field of it changes)
let job_detail_box : @ui.Style = @ui.style(w=Full, h=@sf.grow, pl=S3_5, bg=Card)

///|
/// Where its head stands in it: its stop while it runs (round) in its top end corner as far in as makes it concentric
/// with it (capsule_in), the head's middle on the stop's (the choice beside it the head's tallest); else 10 over, 6 at
/// its end.
fn job_detail_at(running : Bool) -> @ui.Style {
  if !running {
    return job_detail_alone
  }
  let d = @sf.capsule_in(@sf.card_corner, job_stop_side)
  // (the head's middle the stop's: as much less over it as the choice is taller)
  let over = d - (dmax(@sf.segmented_height(), job_stop_side) - job_stop_side) / 2.0
  @ui.style(pt=@sf.room_of(over), pr=@sf.room_of(d))
}

///|
// kept across runs: a value (no field of it changes)
let job_detail_alone : @ui.Style = @ui.css("pt=S2_5 pr=S1_5")

///|
/// Its stop's side (job_detail_stop's S7).
let job_stop_side : Double = 28.0

///|
/// Its head (jobDetailHead): 8 apart, its name 13 in 600, its state 12 muted; the choice 120 wide; the stop 28.
// kept across runs: a value (no field of it changes)
let job_detail_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let job_detail_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let job_detail_state : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let job_detail_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let job_detail_choice : @ui.Style = @ui.css("row")


///|
// kept across runs: a value (no field of it changes)
let job_detail_stop : @ui.Style = @ui.css("w=S7 h=S7 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// Its command (jobDetailCommand): 4 over, 6 under, 11.5 mono on 1.5, subtle, a line.
// kept across runs: a value (no field of it changes)
let job_detail_command : @ui.Style = @ui.css("w=Full pt=S1 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let job_command_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, wrap=false, max_lines=1)

///|
/// What it said (jobDetailNotices): the rest of it, 8 over, 10 at its end; its last output 8 over, 12 under.
// kept across runs: a value (no field of it changes)
let job_detail_notices : @ui.Style = @ui.style(w=Full, h=@sf.grow, pt=S2, pr=S2_5)

///|
// kept across runs: a value (no field of it changes)
let job_detail_last : @ui.Style = @ui.css("w=Full pb=S3")

///|
/// Its output (jobOutput): the rest of it, 4 over, 8 under and at its end; 11.5 mono on 1.6, the words' ink.
// kept across runs: a value (no field of it changes)
let job_output_box : @ui.Style = @ui.style(w=Full, h=@sf.grow, mt=S1, mb=S2, pr=S2)

///|
// kept across runs: a value (no field of it changes)
let job_output_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let job_output_none : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted)
