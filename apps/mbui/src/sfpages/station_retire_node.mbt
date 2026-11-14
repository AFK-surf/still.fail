// A station retired from a workspace (the core's copies.ts `retire`, `taking`; the station's replica/retire.ts): its
// chats moved onto another station of it that the one who manages it picks, then the station taken out (the user,
// 2026-11-13: 「要允许用户选择目标迁移 station」). Rarely done and not undone, so it is no row always in sight: its ⋯
// has 迁走聊天并移出… over 移出 while it may be (`canRetire`) and is online, once offered again (switched off for now:
// `station_retire_offered`). That opens one panel showing what goes and
// what stays as the station counts and names them (`copies.retirePreview`), not a paragraph about it (the owner,
// 2026-11-14: 「字太多了，应该用更结构化更所见即所得的方式设计 UI」), the station to move to chosen in it. While it goes,
// and while a station takes a retired one's chats in, it is a state of the station, not of its backups: one section at
// the top of its page, 迁移: where its chats go with what may be done of it now in the card's corner (取消, 重试; once
// done 移出 workspace, the person's own act, which may ask for their signature), then its steps a row each, then the
// accounts that could not go; a row for each station whose chats come here. Everything said is the core's; a press is a
// call to it.

///|
/// Its 迁移 (station_view_node's "moving", while `station_moving_shown`) in node `b`: this station being retired, its
/// head and steps; each retired one's chats coming here, a row. `manager`: the viewer manages it, so takes it out once
/// done.
fn station_moving_node(b : @view.View, core : Core, here : () -> Here, s : () -> Json?, manager : Bool) -> Unit {
  let address = text(@signals.untracked(s), "station")
  let copies = fn() { field(field(s(), "overview"), "copies") }
  let retire = fn() { field(copies(), "retire") }
  st_section_node(b, fn() { @sf.t("web-pages.stations.retire.section") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      // (where its chats go, and what may be done of it now in the card's corner: once done, take the station out; else
      // let it go and try a failed one again, either as its station says)
      let title = fn() { @sf.t("web-pages.stations.retire.to", args=[("name", text(retire(), "toName"))]) }
      g.show(fn() { retire() is Some(Object(_)) }, fn(r) {
        let can = fn() { (manager && flag(retire(), "done"), flag(retire(), "retriable"), flag(retire(), "cancellable")) }
        r.pick(can, fn(rr, k) {
          let (done, again, cancel) = k
          guard done || again || cancel else { said_row_node(rr, title) }
          let on = [("station", address)]
          @sf.corner_row_node(rr, title, fn(e) {
            e.box(fn(c) {
              c.row(Is(true)).gap(Is(ws_tail_gap)).lines_up(Is(Some(Middle))) |> ignore
              if done {
                @sf.button_node(c, fn() { @sf.t("web-pages.stations.retire.remove") }, fn() {
                  station_remove_ask(core, @signals.untracked(here), @signals.untracked(s))
                }, tone=Primary)
                |> ignore
                return
              }
              // (a failed one let go of too where its station says it can be: retrying alone could fail for good)
              if cancel {
                @sf.button_node(c, fn() { @sf.t("common.cancel") }, fn() {
                  @settings.act(core, @sf.t("web-pages.stations.retire.cancelWhat"), "copies.retireCancel", obj([("station", str(address))]))
                }, tone=Ghost, busy=fn() { is_doing(core, ["copies.retireCancel"], on) })
                |> ignore
              }
              if again {
                @sf.button_node(c, fn() { @sf.t("common.retry") }, fn() {
                  @settings.act(core, @sf.t("web-pages.stations.retire.againWhat"), "copies.retireAgain", obj([("station", str(address))]))
                }, tone=Primary, busy=fn() { is_doing(core, ["copies.retireAgain"], on) })
                |> ignore
              }
            })
            |> ignore
          })
        })
      })
      // (its steps, a row each: done, under way, failed with why, not yet)
      g.each(fn() { items(retire(), "steps") }, fn(x) { text(Some(x), "key") }, fn(row, x) {
        let step = fn() { Some(x.get()) }
        row.pick(fn() { text(step(), "state") }, fn(rr, state) {
          @sf.link_row_node(
            rr,
            fn() { text(step(), "label") },
            fn() {  },
            note=fn() { text(step(), "note") },
            goes=false,
            lacks=state == "failed",
            lead=LeadLine(fn(l) { retire_step_mark(l, state) }),
          )
        })
      })
      // (the accounts that could not go with it, a row of their own)
      g.show(fn() { field(retire(), "left") is Some(Object(_)) }, fn(r) {
        @sf.link_row_node(
          r,
          fn() { text(field(retire(), "left"), "label") },
          fn() {  },
          note=fn() { text(field(retire(), "left"), "note") },
          goes=false,
          lacks=true,
          lead=LeadLine(fn(l) { retire_step_mark(l, "failed") }),
        )
      })
      // (a retired station's chats coming here, a row each: whose, and where it stands)
      g.each(fn() { items(copies(), "taking") }, fn(x) { text(Some(x), "origin") }, fn(row, x) {
        row.pick(fn() { text(Some(x.get()), "level") == "amber" }, fn(rr, wrong) {
          @sf.link_row_node(
            rr,
            fn() { @sf.t("web-pages.stations.retire.from", args=[("name", text(Some(x.get()), "name"))]) },
            fn() {  },
            note=fn() { text(Some(x.get()), "line") },
            goes=false,
            lacks=wrong,
          )
        })
      })
    })
  })
}

///|
/// A step's mark before its words in `l`, by its `state`, each in the icons' square: done a check, under way a
/// spinner, failed a mark in the warning's ink, not yet a hollow circle.
fn retire_step_mark(l : @view.View, state : String) -> Unit {
  match state {
    "now" => @sf.spinner_node(l, size=st_row_glyph) |> ignore
    "done" => @sf.icon_node(l, "check-circle", st_row_glyph, By(fn() { @sf.theme().p.text })) |> ignore
    "failed" => @sf.icon_node(l, "info", st_row_glyph, By(fn() { @sf.theme().p.warn_ink })) |> ignore
    // (a hollow circle in the muted ink, in the icons' square, as round as theirs)
    _ =>
      l.box(fn(sq) {
        @sf.style_node(sq, fn() { retire_todo_square })
        sq.box(fn(ring) { @sf.style_node(ring, fn() { retire_todo_ring }) }) |> ignore
      })
      |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let retire_todo_square : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let retire_todo_ring : @ui.Style = @ui.css("w=S3 h=S3 radius=Full border=B1 border_color=Muted")

///|
/// Whether its page has 迁移 now: it is being retired, or a retired one's chats come here.
fn station_moving_shown(s : Json?) -> Bool {
  let copies = field(field(s, "overview"), "copies")
  field(copies, "retire") is Some(Object(_)) || items(copies, "taking").length() > 0
}

///|
/// Whether its ⋯ offers 迁走聊天并移出… at all. Off (左子健, 2026-11-14: 「我怀疑这个功能根本不能给用户用」, after its
/// first real use; the station refuses starting one too, station/src/replica/module.ts `RETIRE_STARTS`): 迁移 and the
/// panel stay for a retirement already under way. On again once the fixes have passed their drill.
let station_retire_offered : Bool = false

///|
/// Its ⋯'s 迁走聊天并移出… (station_menu_items'), for one who manages it, while it is offered at all
/// (`station_retire_offered`), it is online and may be retired (`canRetire`); None otherwise.
fn station_retire_item(core : Core, here : Here, s : Json?) -> @sf.MenuItem? {
  guard station_retire_offered && flag(s, "online") && flag(field(field(s, "overview"), "copies"), "canRetire") else {
    return None
  }
  Some(@sf.menu_item_of(@sf.t("web-pages.stations.retire.menu"), icon="move", fn() { station_retire_start(core, here, s) }))
}

///|
/// 迁走聊天并移出… pressed: what retiring it would take along and leave asked of its station (`copies.retirePreview`),
/// its panel opened once that is answered (sfbase's press_wait), never on its bones; a station that cannot say is said so.
fn station_retire_start(core : Core, here : Here, s : Json?) -> Unit {
  let address = text(s, "station")
  let answer : @signals.Signal[Result[Json, Json]?] = @signals.signal(None)
  (core.call)("copies.retirePreview", obj([("station", str(address))]), fn(r) { answer.set(Some(r)) })
  @sfbase.press_wait(fn() { answer.get() is Some(_) }, fn() {
    match answer.untracked() {
      Some(Ok(preview)) => station_retire_panel(core, here, s, preview)
      Some(Err(e)) =>
        @sf.confirm(
          @sf.t("web-pages.stations.retire.title", args=[("station", text(s, "name"))]),
          text(Some(e), "message"),
          @sf.t("web-pages.stations.retire.noneOk"),
          fn() {  },
        )
      None => ()
    }
  })
  |> ignore
}

///|
/// The panel that starts retiring station `s` (a dialog in the middle of the window, a sheet on 小屏): the station its
/// chats go to, chosen in it among the workspace's other whole stations online (the one there is chosen already); what
/// goes along and what stays, a row each kind, counted and named as the station's `preview` (RetirePreview) says them;
/// 开始迁移 once one is chosen, then `copies.retire`.
pub fn station_retire_panel(core : Core, here : Here, s : Json?, preview : Json) -> Unit {
  let address = text(s, "station")
  let p = Some(preview)
  let others = match @settings.stations_of(core, here).value {
    Some(Array(a)) =>
      a.filter(fn(x) {
        let at = text(Some(x), "station")
        flag(Some(x), "online") && at != address && @settings.rig_at(core, here, at) is None
      })
    _ => []
  }
  let choices = others.map(fn(x) { (text(Some(x), "id"), text(Some(x), "name")) })
  let to : @signals.Signal[String] = @signals.signal(if choices.length() == 1 { choices[0].0 } else { "" }, same=fn(a, b) { a == b })
  let to_name = fn() {
    match choices.iter().find_first(fn(c) { c.0 == to.get() }) {
      Some(c) => c.1
      None => ""
    }
  }
  // (which they are: three at most, the rest said by the count at the row's end)
  let names = fn(key : String) {
    let all = items(p, key).map(fn(x) { text(Some(x), "name") })
    let shown = all[:@cmp.minimum(3, all.length())].to_owned().join(@sf.t("web-main.list.separator"))
    if all.length() > 3 { @sf.t("web-pages.stations.retire.more", args=[("names", shown)]) } else { shown }
  }
  let count = fn(n : Int) { @sf.t("web-pages.stations.retire.count", args=[("n", n.to_string())]) }
  let chats = number(p, "chats").to_int()
  let archived = number(p, "archived").to_int()
  let outside = number(p, "outside").to_int()
  let home = flag(p, "home")
  let accounts = items(p, "accounts")
  let stay_accounts = items(p, "accountsStay")
  let jobs = items(p, "jobs")
  let connects = items(p, "connects")
  // (a kind of thing: its name and how many on its line, which under it, as wide as the row)
  let kind = fn(v : @view.View, title : String, n : Int, note : String) { retire_kind_node(v, title, count(n), note) }
  @sf.panel_nodes(
    @sf.t("web-pages.stations.retire.title", args=[("station", text(s, "name"))]),
    from=Unanchored,
    form=true,
    fn(v, _) {
      // where they go: the station chosen, or none up to choose
      ws_way_row_node(
        v,
        fn() { @sf.t("web-pages.stations.retire.toRow") },
        fn() { if choices.is_empty() { @sf.t("web-pages.stations.retire.noneOnline") } else { "" } },
        fn(e) {
          if !choices.is_empty() {
            @sf.chooser_node(
              e,
              fn() { if to.get() == "" { @sf.t("web-pages.stations.retire.choose") } else { to_name() } },
              fn() { choices },
              fn() { to.get() },
              fn(id) { to.set(id) },
            )
            |> ignore
          }
        },
      )
      // what goes along, each kind as the station counts and names it
      ws_way_label_node(v, fn() {
        if to.get() == "" {
          @sf.t("web-pages.stations.retire.going")
        } else {
          @sf.t("web-pages.stations.retire.goingTo", args=[("name", to_name())])
        }
      })
      v.box(fn(g) {
        if chats > 0 {
          kind(g, @sf.t("web-pages.stations.retire.chats"), chats, if archived > 0 {
            @sf.t("web-pages.stations.retire.archived", args=[("n", archived.to_string())])
          } else {
            ""
          })
        }
        if connects.length() > 0 {
          kind(g, @sf.t("web-pages.stations.retire.connects"), connects.length(), names("connects"))
        }
        if home && accounts.length() > 0 {
          kind(g, @sf.t("web-pages.stations.retire.accounts"), accounts.length(), names("accounts"))
        }
      })
      |> ignore
      // what stays on it, where anything does
      if jobs.length() > 0 || stay_accounts.length() > 0 || outside > 0 {
        ws_way_label_node(v, fn() { @sf.t("web-pages.stations.retire.staying") })
        v.box(fn(g) {
          if jobs.length() > 0 {
            kind(g, @sf.t("web-pages.stations.retire.jobs"), jobs.length(), names("jobs"))
          }
          if stay_accounts.length() > 0 {
            kind(g, @sf.t("web-pages.stations.retire.accounts"), stay_accounts.length(), names("accountsStay"))
          }
          if outside > 0 {
            kind(g, @sf.t("web-pages.stations.retire.outside"), outside, @sf.t("web-pages.stations.retire.outsideNote"))
          }
        })
        |> ignore
      }
      // (what cannot be shown as a row, quiet, on the rows' line)
      v.box(fn(f) {
        @sf.style_node(f, fn() { @sf.panel_words_in_node(f).then(ws_way_label_at) })
        @sf.words_node(f, fn() { @sf.t("web-pages.stations.retire.foot") }, fn() { @sf.meta }) |> ignore
      })
      |> ignore
    },
    foot=fn(v, close) {
      @sf.foot_spacer_node(v)
      @sf.button_node(v, fn() { @sf.t("common.cancel") }, close, tone=Ghost) |> ignore
      @sf.button_node(
        v,
        fn() { @sf.t("web-pages.stations.retire.start") },
        fn() {
          let id = to.untracked()
          guard id != "" else { return }
          close()
          @settings.act(core, @sf.t("web-pages.stations.retire.what"), "copies.retire", obj([("station", str(address)), ("to", str(id))]))
        },
        tone=DangerSolid,
        disabled=fn() { to.get() == "" },
      )
      |> ignore
    },
  )
}

///|
/// A kind of thing retiring a station takes along or leaves, in its panel (station_retire_panel's) in `parent`: `title`
/// and how many (`value`) on its line, which they are (`note`) under it, quiet, as wide as the row; on the line the ways
/// panel's rows are (ws_way_row_node's).
fn retire_kind_node(parent : @view.View, title : String, value : String, note : String) -> Unit {
  parent.box(fn(r) {
    @sf.style_node(r, fn() { @sf.panel_words_in_node(r).then(retire_kind_box) })
    r.box(fn(line) {
      @sf.style_node(line, fn() { retire_kind_line })
      @sf.words_node(line, fn() { title }, fn() { ws_way_title }).grow(Is(1.0)).shrink(Is(1.0)) |> ignore
      @sf.words_node(line, fn() { value }, fn() { @sf.meta }) |> ignore
    })
    |> ignore
    if note != "" {
      @sf.words_node(r, fn() { note }, fn() { @sf.meta }) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let retire_kind_box : @ui.Style = @ui.css("w=Full gap=S0_5 py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let retire_kind_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")
