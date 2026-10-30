// The services and background jobs left up a long while (an hour), across the chats of the workspace's stations, so
// none is forgotten running (ember web/src/OpenJobs.tsx OpenJobs, OpenJobs.css.ts): web services and background jobs,
// each under its heading, three of a group and the rest folded under 还有 N 个; nothing at all while there are none.
// Each leads to its chat (a service opens there, in its 任务 tab) and stops from here. The core puts them together (its
// `longJobs` view); shown in the list the sidebar's foot opens (lists.mbt) and in 待处理's panel (attention.mbt).

///|
/// The groups opened past their first three, by their key.
let open_jobs_all : Map[String, Bool] = {}

///|
fn open_jobs_reset() -> Unit {
  open_jobs_all.clear()
}

///|
/// Rows shown before the rest folds under 还有 N 个 (SHOWN).
let open_jobs_shown : Int = 3

///|
/// The workspace's long jobs (OpenJobs): each group under its heading; nothing while there are none.
fn open_jobs(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let groups = items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups")
  if groups.length() == 0 {
    return
  }
  c.box(style=open_jobs_box, fn() {
    for g in groups {
      let gv = Some(g)
      let key = text(gv, "key")
      let list = items(gv, "jobs")
      if list.length() == 0 {
        continue
      }
      let shown = if open_jobs_all.contains(key) || list.length() <= open_jobs_shown + 1 {
        list
      } else {
        list[:open_jobs_shown].to_array()
      }
      @sf.panel_group(c, label=text(gv, "head"), fn() {
        for j in shown {
          open_job(c, src, Some(j))
        }
        if shown.length() < list.length() {
          let id = c.id("open-jobs/more/" + key)
          if c.clicked(id) {
            open_jobs_all[key] = true
          }
          let label = @sf.t("web-main.jobs.more", args=[("n", (list.length() - shown.length()).to_string())])
          let b = c.box(style=open_jobs_more, id~, fn() {
            c.text(label, style=if c.lit(id) { open_jobs_more_lit } else { open_jobs_more_words }) |> ignore
          })
          c.semantics(b, Button, id~, label~)
        }
      })
    }
  })
  |> ignore
}

///|
/// A job (openJob): its dot in the icons' 16 column, its name over where it is, how long it has been up at its end;
/// pointed at (or to a finger, always), its stop over the time. The row leads to its chat, a service to its 任务 tab
/// there.
fn open_job(c : @ui.Ctx, src : Source, job : Json?) -> Unit {
  let station = text(job, "station")
  let id = text(job, "id")
  let row = c.id("open-job/" + station + "/" + id)
  let chat = field(job, "chat")
  let chat_station = match opt_text(chat, "station") {
    Some(s) if s != "" => s
    _ => station
  }
  let leads = chat is Some(Object(_)) && chat_station != ""
  if leads && c.clicked(row) {
    let r : ChatRef = { station: chat_station, session: text(chat, "id"), title: text(chat, "title"), station_name: "" }
    open_chat_ref(r)
    if flag(job, "service") {
      pick_job(id)
      side_change(src, r, "open", Some("jobs"))
    }
  }
  let stop = c.id("open-job-stop/" + station + "/" + id)
  let (stopping, failed) = job_stopping(src, station, job)
  // (no hover to tell: the stop shows over the time)
  let over = @sf.pointed_or_finger(c, c.lit(row) || c.lit(stop) || stopping || c.has_focus(stop))
  c.box(style=open_job_box, fn() {
    let b = c.box(style=open_job_row, id=row, fn() {
      c.box(style=open_job_mark, fn() { job_dot(c, text(job, "tone")) }) |> ignore
      c.box(style=open_job_text, fn() {
        c.text(text(job, "name"), style=open_job_name) |> ignore
        c.text(text(job, "whereText"), style=open_job_where) |> ignore
      })
      |> ignore
      c.text(text(job, "age"), style=if over { open_job_age_hidden } else { open_job_age }) |> ignore
    })
    if leads {
      c.semantics(b, Link, id=row, label=text(job, "name"))
    }
    if over {
      c.layer(fn() {
        c.box(style=open_job_stop_at, fn() {
          if !stopping && c.clicked(stop) {
            job_stop(src, station, job)
          }
          let label = @sf.t("web-main.jobs.stopNamed", args=[("name", text(job, "name"))])
          let s = c.box(style=if c.lit(stop) && !stopping { open_job_stop_lit } else { open_job_stop }, id=stop, fn() {
            if stopping || failed is Some(_) {
              @settings.doing_mark(c, stopping, failed)
            } else {
              @sf.icon(c, "stop", size=open_job_stop_icon, color=if c.lit(stop) {
                @sf.theme().p.red
              } else {
                @sf.theme().p.muted
              })
              |> ignore
            }
          })
          c.semantics(s, Button, id=stop, label~)
          @sf.tip(c, "open-job-stop/" + station + "/" + id, stop, @sf.t("web-main.jobs.stop"), side=Top)
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A chat gone to from beside the list (a job's row): its page the one open, the chats' place under it; on the tape
/// shown in the page (show_page), the chat already open too.
fn open_chat_ref(r : ChatRef) -> Unit {
  @sfbase.show_chosen()
  match app.nav.top() {
    Chat(open) if open.station == r.station && open.session == r.session => return
    _ => ()
  }
  @sfbase.history_push()
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.replace(Home)
  app.nav.push(Chat(r))
}

///|
/// The list the sidebar's foot opens (openJobsPop): 280 wide, at most 420 high.
let open_jobs_pop_w : Double = 280.0

///|
let open_jobs_pop_most : Double = 420.0

///|
/// The stop's icon (JobStop: 14).
let open_job_stop_icon : Double = 14.0

///|
/// The groups (openJobs), each a small panel's group (@sf.panel_group: its heading's room over it).
// kept across runs: a value (no field of it changes)
let open_jobs_box : @ui.Style = @ui.css("w=Full")

///|
/// A job (openJob): what its stop stands over.
// kept across runs: a value (no field of it changes)
let open_job_box : @ui.Style = @ui.css("w=Full")

///|
/// Its row (openJobRow): 5 by 10 in, its parts 10 apart, concentric with the panel, the hover grey pointed at.
// kept across runs: a value (no field of it changes)
let open_job_row : @ui.Style = @ui.css("row w=Full px=S2_5 py=S1_25 gap=S2_5 radius=Inner align=ACenter hovered{bg=Hover}")

///|
/// The dot, in the 16 column the icons of the rows under it take (openJobMark).
// kept across runs: a value (no field of it changes)
let open_job_mark : @ui.Style = @ui.css("w=S4 align=ACenter justify=JCenter")

///|
/// Its name over where it is (openJobText).
// kept across runs: a value (no field of it changes)
let open_job_text : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its name (openJobName: the ui's size, cut short).
// kept across runs: a value (no field of it changes)
let open_job_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, max_lines=1)

///|
/// Where it is (openJobWhere: the meta's size, muted, cut short).
// kept across runs: a value (no field of it changes)
let open_job_where : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, max_lines=1)

///|
/// How long it has been up (openJobAge: the meta's size, muted); hidden under its stop.
// kept across runs: a value (no field of it changes)
let open_job_age : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let open_job_age_hidden : @ui.TextStyle = open_job_age.then(@ui.text_style(color=Clear))

///|
/// Where its stop is (openJobStop: 6 from its right, in its middle).
// kept across runs: a value (no field of it changes)
let open_job_stop_at : @ui.Style = @ui.css("w=Full h=Full pr=S1_5 align=AEnd justify=JCenter")

///|
/// Its stop (openJobStop): 24 square, an option's corner; red on the hover grey pointed at.
// kept across runs: a value (no field of it changes)
let open_job_stop : @ui.Style = @ui.css("w=S6 h=S6 radius=Xl align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let open_job_stop_lit : @ui.Style = open_job_stop.then(@ui.css("bg=Hover"))

///|
/// 还有 N 个 (openJobsMore: the meta's size, muted, the text's pointed at), its words where a row's are.
// kept across runs: a value (no field of it changes)
let open_jobs_more : @ui.Style = @ui.style(px=S2_5, py=@sf.room_of(@sf.menu_row_over))

///|
// kept across runs: a value (no field of it changes)
let open_jobs_more_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let open_jobs_more_lit : @ui.TextStyle = open_jobs_more_words.then(@ui.text_style(color=Fg))
