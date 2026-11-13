// 连接, one page in every frame (web/src/pages/Connects.tsx ConnectList, Connects.css.ts; the narrow app's
// mobile/Connects.tsx), laid out by its width: at its head its title with what a connect is and 添加连接;
// under it the filter (全部 or 我的); the Slack apps made and not connected yet, each to go on with; then the connects,
// each its bot's picture, its name and its Slack workspace, how it runs, its station, who added it, how it is and its
// dot (wide: one list, each with its station's tag; narrow: a card a station, under its name). With none at all yet,
// the page is about adding the first (a profile first where no station has one). `only`: one station's (its page's
// 连接). Adding is the new connect's dialog (new_connect.mbt); menus and asking first, the presenters. Made once as
// nodes of the window's tree in every frame (page_node), what it shows bound to what the core says.

///|
/// 连接 (ConnectList, ConnectsScreen) made once as nodes in node `v` (page_node, laid out by the `width` its frame
/// gives it, narrow where none is given), of station `only` ("" every station's), in the frame it is given: its blocks
/// as the core's connects and stations views say them now, all of them or the viewer's as its filter says (kept while
/// the page is on the stack: @settings.connects_mine). What it does (添加连接) at its title's end, or where a frame's
/// bar names it, in that bar (`bar_actions`). `here`: who and where, as that changes; `stint`: its time on top (the
/// pictures asked for on it); `tips`: the window's, else its own over it.
pub fn connects_node(
  v : @view.View,
  src : Source,
  core : Core,
  here : () -> Here,
  only : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint~ : () -> Int,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
  bar_actions? : ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
) -> Unit {
  // (what is said of what the pointer rests on: the frame's, over the window; else drawn over the page in the page's own
  // node, each tip its holder over all of it there: history_node's)
  let tips = match tips {
    Some(t) => t
    None => @sf.TipLayer::new(fn() { Some(v) })
  }
  // (all of them or the viewer's: as the page left it while it is on the stack, a signal of that input)
  let mine : @signals.Signal[Bool] = @signals.signal(connects_mine.val, same=fn(a, b) { a == b })
  let set_mine = fn(m : Bool) {
    connects_mine.val = m
    mine.set(m)
  }
  let topic = fn() { (core.topic)("connects", { "scope": str(here().workspace), "mine": Json::boolean(mine.get()) }).get() }
  let stations = fn() {
    match @settings.stations_of(core, here()).value {
      Some(Array(a)) => if only == "" { a } else { a.filter(fn(x) { text(Some(x), "station") == only }) }
      _ => []
    }
  }
  let view = fn() { topic().value }
  let shown = fn() { items(view(), "items").filter(fn(x) { only == "" || text(Some(x), "station") == only }) }
  let wait = fn() { field(view(), "wait") }
  let loading = fn() { wait() is None || flag(wait(), "reading") }
  let station_of = fn(address : String) -> Json? {
    stations().iter().find_first(fn(s) { text(Some(s), "station") == address })
  }
  // the Slack apps the viewer made that no connect has taken yet, each on its station (the connects' `slackApps`: every
  // station's, said with it), with that station's row (its name and whether it is up; till that is read, its name)
  let waiting = fn() -> Array[(Json, Json)] {
    items(view(), "slackApps").filter_map(fn(x) {
      let address = text(Some(x), "station")
      if only != "" && address != only {
        return None
      }
      let s = match station_of(address) {
        Some(s) => s
        None => Json::object({ "station": Json::string(address), "name": Json::string(text(Some(x), "stationName")) })
      }
      Some((field(Some(x), "app").unwrap_or(Json::null()), s))
    })
  }
  // none at all yet (not only none of the viewer's): the page is about adding the first
  let first = fn() {
    !loading() && topic().error is None && shown().length() == 0 && !mine.get() && waiting().length() == 0
  }
  // a connect runs a profile's model: with none on any station (each read), the first step is a profile (the connects'
  // `noProfile`; one station's, by its overview's profiles alone)
  let no_profile = fn() {
    if only == "" {
      flag(view(), "noProfile")
    } else {
      match @settings.station_part(core, here(), only, "profiles") {
        Some(Array(a)) => a.length() == 0
        _ => false
      }
    }
  }
  // where one is added: the stations online
  let targets = fn() { stations().filter(fn(s) { flag(Some(s), "online") }) }
  let failing = fn() { items(wait(), "failing").length() > 0 }
  // (its primary action named as what it adds; narrow, the title's ＋)
  let actions = fn(l : @view.View) {
    l.show(fn() { targets().length() > 0 && !first() }, fn(a) {
      cn_add_node(a, src, core, here, targets, fn() { @sf.t("android-misc.bar.action.connects") }, false, round=@sf.look_node(a) is Narrow)
    })
  }
  match bar_actions {
    Some(f) => f(actions, fn(_) { @sf.button_height() })
    None => ()
  }
  @sf.page_node(
    v,
    fn() { @sf.t("android-settings.connects.title") },
    fn() {
      let out : Array[String] = []
      if first() {
        out.push(if no_profile() { "first-profile" } else { "first" })
      } else {
        out.push("filter")
      }
      if waiting().length() > 0 {
        out.push("waiting")
      }
      if !first() {
        if shown().length() == 0 && topic().error is None && (loading() || failing()) {
          out.push("reading")
        } else if shown().length() == 0 {
          out.push("none")
        } else {
          out.push("list")
          // what the list still waits on: a row's shape for a station not read yet, each failure said
          if flag(wait(), "reading") || failing() {
            out.push("more")
          }
        }
      }
      out
    },
    fn(b, key) {
      let look = @sf.look_node(b)
      let wide = look == Wide
      match key {
        "first-profile" =>
          cn_gutter_node(b, look, fn(g) {
            @sf.first_one_node(g, fn() { @sf.t("web-pages.connects.profileFirst") }, lead=fn() { @sf.t("web-pages.connects.profileFirstLead") }, fn(a) {
              @sf.button_node(a, fn() { @sf.t("web-pages.connects.goAddProfile") }, fn() { (core.push)(Profiles("")) }, tone=Primary)
              |> ignore
            })
          })
        "first" =>
          cn_gutter_node(b, look, fn(g) {
            @sf.first_one_node(g, fn() { @sf.t("web-pages.connects.addFirst") }, lead=fn() { @sf.t("web-pages.connects.addFirstLead") }, fn(a) {
              a.pick(fn() { targets().length() > 0 }, fn(p, some) {
                if some {
                  cn_add_node(p, src, core, here, targets, fn() { @sf.t("web-pages.connects.add") }, true)
                } else {
                  @sf.words_node(p, fn() {
                    @sf.t(if stations().length() > 0 { "web-pages.connects.noOnline" } else { "web-pages.connects.stationFirst" })
                  }, fn() { cn_note })
                  |> ignore
                }
              })
            })
          })
        "filter" =>
          b.box(fn(f) {
            @sf.style_node(f, fn() { if wide { cn_filter_room } else { cn_filter_room_narrow } })
            mine_filter_node(f, "connects-filter", "connects", fn() { mine.get() }, set_mine)
          })
          |> ignore
        "waiting" => {
          let rows = fn(g : @view.View) {
            g.each(waiting, fn(w) { text(Some(w.1), "station") + "/" + text(Some(w.0), "appId") }, fn(r, w) {
              cn_waiting_app_node(r, src, core, here, look, fn() { w.get().0 }, fn() { w.get().1 }, tips, stint)
            })
          }
          if wide {
            b.box(fn(t) {
              @sf.style_node(t, fn() { cn_quiet_room })
              @sf.words_node(t, fn() { @sf.t("web-pages.connects.waiting") }, fn() { cn_quiet }) |> ignore
            })
            |> ignore
            @sf.group_node(b, rows)
          } else {
            @sf.heading_node(b, fn() { @sf.t("web-pages.connects.waiting") })
            @sf.group_node(b, rows)
          }
        }
        "reading" =>
          cn_gutter_node(b, look, fn(g) {
            @sf.waiting_node(g, fn(s) { connects_sample_node(s, core, look, only, 3, tips, stint) }, note=fn() {
              let failing = failing_of(wait())
              { reading: failing.length() == 0, text: "", failing }
            })
          })
        "none" =>
          b.box(fn(n) {
            @sf.style_node(n, fn() { if wide { cn_none_room } else { cn_filter_room_narrow } })
            @sf.words_node(n, fn() {
              match topic().error {
                Some(e) => error_text(e)
                None => @sf.t(if mine.get() { "web-pages.connects.noneMine" } else { "web-pages.connects.none" })
              }
            }, fn() { if topic().error is Some(_) { cn_error } else { cn_note } })
            |> ignore
          })
          |> ignore
        "list" => connects_list_node(b, core, look, shown, only, station_of, tips, stint)
        _ =>
          cn_gutter_node(b, look, fn(g) {
            @sf.wait_more_node(g, fn() { { reading: flag(wait(), "reading"), text: "", failing: failing_of(wait()) } }, fn(s) {
              connects_sample_node(s, core, look, only, 1, tips, stint)
            })
          })
      }
    },
    on_back~,
    frame~,
    about=fn() { @sf.t("web-pages.connects.about", args=[("name", "still.fail")]) },
    actions~,
    said?,
    width?,
    tips~,
  )
}

///|
/// The connects (`shown`, of station `only`, else every station's, as they are now) as nodes: wide, a list of them;
/// narrow, each station's under its name (one offline said so), as a card, each connect by its id (one made or taken
/// out comes and goes where it is: @sf.keyed_rows_node).
fn connects_list_node(
  b : @view.View,
  core : Core,
  look : Look,
  shown : () -> Array[Json],
  only : String,
  station_of : (String) -> Json?,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let key_of = fn(x : Json) { text(Some(x), "station") + "/" + text(field(Some(x), "connect"), "id") }
  match look {
    Wide =>
      @sf.list_card_node(b, fn(k) {
        k.each(shown, key_of, fn(r, x) {
          let address = @signals.untracked(fn() { text(Some(x.get()), "station") })
          cn_row_node(r, core, look, address, fn() { text(Some(x.get()), "stationName") }, fn() { station_of(address) }, fn() {
            field(Some(x.get()), "connect")
          }, tips, stint)
        })
      })
    Narrow => {
      // (the stations in the order their connects come, each once)
      let addresses = fn() {
        let out : Array[String] = []
        for x in shown() {
          let a = text(Some(x), "station")
          if !out.contains(a) {
            out.push(a)
          }
        }
        out
      }
      b.each(addresses, fn(a) { a }, fn(sb, a) {
        let address = a.untracked()
        let here_list = fn() { shown().filter(fn(x) { text(Some(x), "station") == address }) }
        let name = fn() {
          match here_list().get(0) {
            Some(x) => text(Some(x), "stationName")
            None => ""
          }
        }
        if only == "" {
          @sf.heading_node(sb, fn() {
            let sv = station_of(address)
            if sv is None || flag(sv, "online") {
              name()
            } else {
              @sf.t("android-settings.connects.offline", args=[("name", name())])
            }
          })
        }
        @sf.group_node(sb, fn(g) {
          @sf.keyed_rows_node(
            g,
            fn() {
              here_list().mapi(fn(i, x) {
                let id = text(field(Some(x), "connect"), "id")
                (if id != "" { id } else { "#" + i.to_string() }, x)
              })
            },
            fn(x) { x.0 },
            fn(r, x) {
              cn_row_node(r, core, look, address, name, fn() { station_of(address) }, fn() { field(Some(x.get().1), "connect") }, tips, stint)
            },
          )
        })
      })
    }
  }
}

///|
/// The connects to come while they are read (the library's Waiting, in its bones): `count` made-up ones on a station,
/// as connects_list_node makes them, through a core that answers nothing.
fn connects_sample_node(v : @view.View, core : Core, look : Look, only : String, count : Int, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  let name = @sf.sample_words(4)
  let shown = [8, 6, 10][:count].to_owned().map(fn(n) {
    Json::object({
      "station": "sample",
      "stationName": Json::string(name),
      "connect": {
        "id": Json::string("sample" + n.to_string()),
        "name": Json::string(@sf.sample_words(n)),
        "modeText": Json::string(@sf.sample_words(4)),
        "runtimeText": Json::string(@sf.sample_words(3)),
      },
    })
  })
  connects_list_node(v, core.quiet(), look, fn() { shown }, only, fn(_) { None }, tips, stint)
}

///|
/// 连接's primary action where the frame holds it (a phone's bar's notch): a connect added on the station online, the
/// only one at once, else one picked first; None while none is online.
pub fn connects_add(src : Source, core : Core, here : Here) -> ((@sf.Beside) -> Unit)? {
  let online = match @settings.stations_of(core, here).value {
    Some(Array(a)) => a.filter(fn(s) { flag(Some(s), "online") })
    _ => []
  }
  if online.length() == 0 {
    return None
  }
  Some(fn(from) {
    if online.length() == 1 {
      new_connect_dialog(src, core, here, text(Some(online[0]), "station"))
      return
    }
    let items : Array[@sf.MenuItem?] = online.map(fn(s) {
      let station = text(Some(s), "station")
      Some(@sf.menu_item_of(text(Some(s), "name"), fn() { new_connect_dialog(src, core, here, station) }))
    })
    @sf.menu(items, from~, title=@sf.t("web-pages.connects.whichStation"))
  })
}

///|
/// What sits on the page's ground as wide as its column, narrow 12 from its sides (as its cards are), `body` made in
/// it.
fn cn_gutter_node(b : @view.View, look : Look, body : (@view.View) -> Unit) -> Unit {
  match look {
    Wide => body(b)
    Narrow =>
      b.box(fn(g) {
        @sf.style_node(g, fn() { @sf.pg_card_room })
        body(g)
      })
      |> ignore
  }
}

///|
/// Adding one, `label` its words: on the one station online at once, else on one picked from a menu by it (which
/// station?), in the new connect's dialog (`targets`, as they are as it is pressed). `primary`: the first one's (a
/// solid button, its menu in its middle); `round`: the narrow title's ＋.
fn cn_add_node(
  parent : @view.View,
  src : Source,
  core : Core,
  here : () -> Here,
  targets : () -> Array[Json],
  label : () -> String,
  primary : Bool,
  round? : Bool = false,
) -> Unit {
  // (pressed: the button itself what its menu goes by)
  let press = fn(b : @view.View) {
    let h = @signals.untracked(here)
    let ts = @signals.untracked(targets)
    if ts.length() == 1 {
      new_connect_dialog(src, core, h, text(Some(ts[0]), "station"))
      return
    }
    guard ts.length() > 0 else { return }
    let items : Array[@sf.MenuItem?] = ts.map(fn(s) {
      let station = text(Some(s), "station")
      Some(@sf.menu_item_of(text(Some(s), "name"), fn() { new_connect_dialog(src, core, h, station) }))
    })
    let (x, y, w, hh) = b.placed_window_now()
    @sf.menu(items, from=At(x, y, w, hh), title=@sf.t("web-pages.connects.whichStation"), along=if primary { Middle } else { End })
  }
  if round {
    @sf.icon_button_opens_node(parent, "plus", label, press) |> ignore
  } else {
    @sf.button_opens_node(parent, label, press, tone=if primary { Primary } else { Plain }, icon="plus") |> ignore
  }
}

///|
/// A connect in the list (its row's Link), `cv` as it is now: its picture, its name with its Slack workspace after it,
/// how it runs; at its end (wide) its station's tag and who added it, how it is (being deleted: a ring), its dot and
/// how it is. Pressed, its page.
fn cn_row_node(
  r : @view.View,
  core : Core,
  look : Look,
  station : String,
  station_name : () -> String,
  s : () -> Json?,
  cv : () -> Json?,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let id = fn() { text(cv(), "id") }
  let how = fn() {
    let model = match opt_text(field(cv(), "bind"), "model") {
      Some(m) => " · " + opt_text(cv(), "modelName").unwrap_or(m)
      None => ""
    }
    text(cv(), "modeText") + " · " + text(cv(), "runtimeText") + model
  }
  let on = fn() { [("station", station), ("id", id())] }
  let wide = look == Wide
  let end = fn(e : @view.View) {
    // (wide: where it runs and who made it, dropped before its name where the line has not the room)
    e.gap(Is(12.0)).fits(Is(wide)) |> ignore
    if wide {
      e.box(fn(f) {
        @sf.style_node(f, fn() { cn_facts })
        f.drops(Is(cn_drop_facts)) |> ignore
        cn_station_tag_node(f, station_name, s, stint)
        cn_owner_node(f, core, fn() { field(cv(), "createdBy") }, tips, stint)
      })
      |> ignore
    }
    doing_mark_node(e, fn() { is_doing(core, ["connect.delete"], on()) }, fn() { failed_of(core, ["connect.delete"], on()) }, tips~, size=doing_mark_end)
    e.box(fn(st) {
      @sf.style_node(st, fn() { cn_narrow_state })
      @sf.state_dot_node(st, fn() { text(cv(), "presence") })
      @sf.words_node(st, fn() { text(cv(), "statusText") }, fn() { cn_meta }) |> ignore
    })
    |> ignore
  }
  // (its lead a 28x28 face across the row's middle; a platform's mark said once on a row, where the row leads with it,
  // else before its team)
  @sf.link_row_node(
    r,
    fn() { text(cv(), "name") },
    fn() { (core.push)(Connect(station, @signals.untracked(id))) },
    note=how,
    note_cut=true,
    chevron=false,
    lead=LeadMade(fn(l) { cn_avatar_node(l, core, cv, stint) }),
    face=true,
    // its Slack workspace after its name (short of room, its name kept: its team leaves its line first)
    title_after=fn(a) {
      a.drops(Is(cn_drop_team)) |> ignore
      a.box(fn(t) {
        @sf.style_node(t, fn() { cn_team })
        t.show(fn() { opt_text(cv(), "botImage") is Some(_) }, fn(k) {
          cn_kind_node(k, fn() { text(cv(), "kind") }, cn_team_icon)
        })
        @sf.words_node(t, fn() { text(cv(), "team") }, fn() { cn_meta }) |> ignore
      })
      |> ignore
    },
    title_after_shown=fn() { opt_text(cv(), "team") is Some(_) },
    tail?=if wide { None } else { Some(end) },
    control?=if wide { Some(end) } else { None },
  )
}

///|
/// A connect as its people see it (ui.tsx ConnectAvatar, 28): its bot's picture; its kind's mark till that is said.
fn cn_avatar_node(l : @view.View, core : Core, cv : () -> Json?, stint : () -> Int) -> Unit {
  l.pick(fn() { opt_text(cv(), "botImage") is Some(_) }, fn(p, pictured) {
    if pictured {
      @sf.avatar_node(p, fn() { text(cv(), "id") }, fn() { text(cv(), "name") }, fn() {
        match opt_text(cv(), "botImage") {
          Some(image) => (core.picture)(image, stint())
          None => ""
        }
      }, cn_avatar_size)
    } else {
      p.box(fn(k) {
        @sf.style_node(k, fn() { cn_kind_box })
        cn_kind_node(k, fn() { text(cv(), "kind") }, cn_kind_size)
      })
      |> ignore
    }
  })
}

///|
/// What a connect connects to (ConnectKindIcon), as `kind` says it now: Slack's mark, Feishu's or Comma's (one colour:
/// in the page's ink).
fn cn_kind_node(parent : @view.View, kind : () -> String, size : Double) -> Unit {
  parent.pick(fn() { if kind() == "feishu" || kind() == "comma" { kind() } else { "slack" } }, fn(p, k) {
    if k == "comma" {
      @sf.drawable_node(p, "comma", size, tint=fn() { Some(@sf.theme().p.text) }) |> ignore
    } else {
      @sf.drawable_node(p, k, size) |> ignore
    }
  })
}

///|
/// Its station (cloud.css.ts stationTag: 1 by 8 in, a corner of 6 on the neutral ground, the meta's 12 in 500 muted;
/// its mark 11 before its name), as `s` says it now.
fn cn_station_tag_node(parent : @view.View, name : () -> String, s : () -> Json?, stint : () -> Int) -> Unit {
  parent.box(fn(t) {
    @sf.style_node(t, fn() { cn_tag })
    t.show(fn() { @sf.has_station_mark(text(s(), "emoji"), text(s(), "icon")) }, fn(m) {
      @sf.station_mark_node(m, fn() { text(s(), "emoji") }, fn() { text(s(), "icon") }, cn_team_icon, fn() { @sf.theme().p.muted }, stint)
    })
    @sf.words_node(t, name, fn() { cn_tag_words }) |> ignore
  })
  |> ignore
}

///|
/// Who added it (`by`, as it is now): their picture 16 and name (theirs said as the viewer's), 6 apart, the meta's 12,
/// who they are by their id over it while it is pointed at (but this machine's own, in `tips`); none said, so in the
/// subtle ink.
fn cn_owner_node(parent : @view.View, core : Core, by : () -> Json?, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  let shown = fn() { field(by(), "shown") }
  parent.pick(fn() { shown() is Some(Object(_)) }, fn(p, said) {
    if !said {
      @sf.words_node(p, fn() { @sf.t("web-main.owner.none") }, fn() { cn_owner_none }) |> ignore
      return
    }
    let o = p.box(fn(o) {
      @sf.style_node(o, fn() { cn_owner_box })
      // (short of room, its name goes on in lines, as an old view's words in a row do)
      o.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      @sf.avatar_node(o, fn() { text(by(), "id") }, fn() { text(shown(), "name") }, fn() {
        match text(shown(), "picture") {
          "" => ""
          pic => (core.picture)(pic, stint())
        }
      }, cn_owner_size)
      @sf.words_node(o, fn() {
        let name = text(shown(), "name")
        if flag(shown(), "mine") { @sf.t("web-main.owner.you", args=[("name", name)]) } else { name }
      }, fn() { cn_owner_words })
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    @sf.tip_node(tips, o, fn() { if text(by(), "id") == "local" { "" } else { text(by(), "id") } }, within=true) |> ignore
  })
}

///|
/// A Slack app made and not connected yet (WaitingApp), `a` and its station `s` as they are now: Slack's mark, its
/// name and workspace, where it stands; its station's tag (wide); 继续 while its station is online (else that it is
/// not), dropped from under ⋯ (asked first).
fn cn_waiting_app_node(
  r : @view.View,
  src : Source,
  core : Core,
  here : () -> Here,
  look : Look,
  a : () -> Json,
  s : () -> Json,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let av = fn() { Some(a()) }
  let sv = fn() { Some(s()) }
  let station = fn() { text(sv(), "station") }
  let online = fn() { flag(sv(), "online") }
  let app_id = fn() { text(av(), "appId") }
  let where_ = fn() {
    if flag(av(), "installed") {
      @sf.t("web-pages.connects.installedNeedsToken", args=[
        ("team", first_text(av(), ["installedTeam", "team"], @sf.t("android-settings.flow.team"))),
      ])
    } else if has(av(), "install") {
      @sf.t("web-pages.connects.notInstalled")
    } else {
      @sf.t("web-pages.connects.needsToken")
    }
  }
  let on = fn() { [("station", station()), ("appId", app_id())] }
  let dropping = fn() { is_doing(core, ["slack.dropApp"], on()) }
  let drop = fn() {
    let (name, st, id) = @signals.untracked(fn() { (text(av(), "name"), station(), app_id()) })
    confirm(
      @sf.t("web-pages.settings.stations.removeConfirm", args=[("name", name)]),
      @sf.t("web-pages.connects.removeBody", args=[("name", "still.fail")]),
      @sf.t("android-settings.members.remove"),
      danger=true,
      fn() {
        @settings.act(
          core,
          @sf.t("android-settings.waiting.removeWhat"),
          "slack.dropApp",
          obj([("station", str(st)), ("appId", str(id))]),
          done=@sf.t("android-settings.members.removed"),
        )
      },
    )
  }
  @sf.link_row_node(
    r,
    fn() { text(av(), "name") },
    fn() {  },
    note=where_,
    note_cut=true,
    goes=false,
    lead=LeadMade(fn(l) {
      l.box(fn(k) {
        @sf.style_node(k, fn() { cn_kind_box })
        @sf.drawable_node(k, "slack", cn_waiting_mark) |> ignore
      })
      |> ignore
    }),
    face=true,
    // its Slack workspace after its name, no mark again (the row leads with Slack's: a platform's mark said once)
    title_after=fn(t) {
      t.drops(Is(cn_drop_team)) |> ignore
      @sf.words_node(t, fn() { text(av(), "team") }, fn() { cn_meta }) |> ignore
    },
    title_after_shown=fn() { opt_text(av(), "team") is Some(_) },
    control=fn(e) {
      let wide = look == Wide
      e.gap(Is(12.0)).fits(Is(wide)) |> ignore
      if wide {
        e.box(fn(f) {
          @sf.style_node(f, fn() { cn_facts })
          f.drops(Is(cn_drop_facts)) |> ignore
          cn_station_tag_node(f, fn() { text(sv(), "name") }, sv, stint)
        })
        |> ignore
      }
      e.show(fn() { !online() }, fn(w) {
        @sf.words_node(w, fn() { @sf.t("web-pages.connects.stationOffline") }, fn() { cn_meta }) |> ignore
      })
      doing_mark_node(e, dropping, fn() { failed_of(core, ["slack.dropApp"], on()) }, tips~, size=doing_mark_end)
      e.show(online, fn(c) {
        @sf.style_node(c, fn() { cn_actions })
        let go = fn() {
          let (st, id) = @signals.untracked(fn() { (station(), app_id()) })
          new_connect_dialog(src, core, @signals.untracked(here), st, made_app=id)
        }
        if wide {
          @sf.button_node(c, fn() { @sf.t("web-pages.connects.continue") }, go) |> ignore
        } else {
          @sf.tap_text_node(c, fn() { @sf.t("web-pages.connects.continue") }, go)
        }
        // dropped from under ⋯ (its menu), asked again first; it stays in Slack
        c.show(fn() { !dropping() }, fn(m) { cn_more_node(m, drop) })
      })
    },
  )
}

///|
/// A waiting app's ⋯ (an icon button: 32, its corner 12, the hover's ground under the pointer): pressed, its menu by
/// it, at its end, of one thing, taking it away (`drop`, asked first).
fn cn_more_node(parent : @view.View, drop : () -> Unit) -> Unit {
  parent.box(fn(m) {
    @sf.style_node(m, fn() { cn_more })
    m
    .ground(By(fn() { if m.pointed() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-pages.connects.removeHere"))) }))
    |> ignore
    @sf.presses_node(m, fn() {
      let (x, y, w, h) = m.placed_window_now()
      @sf.menu([Some(@sf.menu_item_of(@sf.t("web-pages.connects.removeHere"), drop, danger=true))], from=At(x, y, w, h), along=End)
    })
    @sf.icon_node(m, "more", cn_more_icon, By(fn() { @sf.theme().p.muted })) |> ignore
  })
  |> ignore
}

///|
/// A list's filter on the page (components.tsx MineFilter, not compact; History.css.ts mineFilterBtn, mineFilterWide)
/// as a node in `parent`: a 32 high button 8 in, the field's line round it; its funnel 16 and what it shows in the
/// muted ink, the words' under the hand or while open, never marked for what it shows; pressed, its menu of choices by
/// it (all or the viewer's, the shown checked), at its end, open till one is chosen or it is dismissed (the hand,
/// Escape, a press outside it), said so as it opens and as it goes (mine_filter_shown). `of`: what it filters
/// (`connects`), as its words name it; `mine` what it shows now, `set` told the other as it is chosen.
fn mine_filter_node(parent : @view.View, key : String, of : String, mine : () -> Bool, set : (Bool) -> Unit) -> Unit {
  let t = fn() { @sf.theme() }
  let open : @signals.Signal[Bool] = @signals.signal(mine_filter_open.get(key).unwrap_or(false), same=fn(a, b) { a == b })
  let named = fn() { if mine() { @sf.t("web-main.filter." + of + ".mine") } else { @sf.t("web-main.filter.all") } }
  parent.box(fn(b) {
    let lit = fn() { @sf.lit_node(b) || open.get() }
    @sf.style_node(b, fn() { mine_filter_box })
    b
    .edge(By(fn() { (1.0, @ui.tree_theme().color(Line)) }))
    .ground(By(fn() { if lit() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() {
      Some(@view.said(Button, label=@sf.t("web-main.filter." + of + ".named", args=[("named", named())]), expanded=open.get()))
    }))
    |> ignore
    @sf.presses_node(b, fn() {
      if open.untracked() {
        return
      }
      let now = @signals.untracked(mine)
      let closed = fn() {
        mine_filter_open[key] = false
        open.set(false)
      }
      // (chosen, the menu closes without its gone: closed here)
      let pick = fn(m : Bool) {
        closed()
        if m != now {
          set(m)
        }
      }
      let (x, y, w, h) = b.placed_window_now()
      mine_filter_open[key] = true
      open.set(true)
      @sf.menu(
        [
          Some(@sf.menu_item_of(@sf.t("web-main.filter." + of + ".all"), fn() { pick(false) }, chosen=!now)),
          Some(@sf.menu_item_of(@sf.t("web-main.filter." + of + ".mine"), fn() { pick(true) }, chosen=now)),
        ],
        from=At(x, y, w, h),
        along=End,
        gone=closed,
      )
    })
    @sf.icon_node(b, "filter", mine_filter_icon, By(fn() { if lit() { t().p.text } else { t().p.muted } })) |> ignore
    @sf.words_node(b, named, fn() { if lit() { mine_filter_lit_words } else { mine_filter_words } }) |> ignore
  })
  |> ignore
}

///|
/// Which filter's menu is open, by its key.
// kept across runs: said by its button as its menu opens and goes; reset empties it
let mine_filter_open : Map[String, Bool] = Map([])

///|
/// Whether filter `key`'s menu is open (tests).
pub fn mine_filter_shown(key : String) -> Bool {
  mine_filter_open.get(key).unwrap_or(false)
}

///|
let mine_filter_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let mine_filter_box : @ui.Style = @ui.css("row h=S8 min_w=S8 px=S2 gap=S1_5 align=ACenter radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let mine_filter_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mine_filter_lit_words : @ui.TextStyle = mine_filter_words.then(@ui.text_style(color=Fg))


///|
/// The sizes: its picture 28, its kind's mark 17 in a 20 square (a waiting app's 18), the team's and the tag's
/// marks 11, the owner's picture 16, ⋯ 16.
let cn_avatar_size : Double = 28.0

///|
let cn_kind_size : Double = 17.0

///|
let cn_waiting_mark : Double = 18.0

///|
let cn_team_icon : Double = 11.0

///|
let cn_owner_size : Double = 16.0

///|
let cn_more_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let cn_kind_box : @ui.Style = @ui.css("w=S7 h=S7 align=ACenter justify=JCenter")

///|
/// The filter, as wide as what it says, 8 further under the head than the head's own room, where the web's is
/// (pageHead: 28 under it), and 12 over the list; the waiting apps' title (sectionTitleQuiet: the meta's 12 in 500 muted, 6 under).
// kept across runs: a value (no field of it changes)
let cn_filter_room : @ui.Style = @ui.css("w=Full pt=S2 pb=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let cn_quiet_room : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let cn_quiet : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_none_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let cn_error : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let cn_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// Its Slack workspace after its name (connectTeam: 8 after it, its mark 4 from its name, the meta's 12 muted).
// kept across runs: a value (no field of it changes)
let cn_team : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cn_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// Its team after its name, whole or not at all where its line has not the room.
let cn_drop_team : Int = 1

///|
/// What leaves a connect's row first, short of room: where it runs and who made it.
let cn_drop_facts : Int = 1

///|
/// Its station and who added it (connectFacts: 10 apart).
// kept across runs: a value (no field of it changes)
let cn_facts : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cn_tag : @ui.Style = @ui.css("row px=S2 py=SPx gap=S1 align=ACenter radius=Md bg=Neutral")

///|
// kept across runs: a value (no field of it changes)
let cn_tag_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_box : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let cn_owner_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let cn_owner_none : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let cn_actions : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// ⋯ (an icon button: 32, round).
// kept across runs: a value (no field of it changes)
let cn_more : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")


///|
/// Narrow: the filter in the page's room, 10 under; a row's line under its name (the secondary's, on one line);
/// how it is at its end, its dot before the words.
// kept across runs: a value (no field of it changes)
let cn_filter_room_narrow : @ui.Style = @ui.css("w=Full pb=S2_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let cn_narrow_state : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")
