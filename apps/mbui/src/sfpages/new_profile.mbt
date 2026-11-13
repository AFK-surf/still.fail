// A new profile on a station (AddProfile, NewProfileScreen), one page in every frame: the providers in their groups
// (the station's own logins not used yet offered first; which online station it is added on chosen over them where
// there are more), then how to connect the one picked (its plan or a key) and the form. What is picked and typed, and
// what each step says, is the core's (`profileFlow`, `profile.flow.*`); a plan signed in (`login.new`, its steps
// relayed here, the profile made by the station once it is signed in), or a key checked first (`profile.flow.submit`:
// the profile made only if it works). Made once as nodes of the window's tree (page_node), laid out by the width its
// frame gives it. (The two pages it was, the desktop's and the phone's, are gone: designed from both, it is one.)

///|
/// Where the add page of a station begins, when it is come to with a provider and how (the web's addProfilePath with
/// its provider and `method`): told to its draft as that is opened.
// kept across runs: said by the pages that lead to it; reset (pages.mbt) empties it
pub let add_profile_start : Map[String, Array[(String, Json)]] = Map([])

///|
/// A new profile (AddProfile) on station `address` (another online one where it is not: the first), made once in node
/// `v`, laid out by the `width` its frame gives it, in the frame it is given: while the stations are read, the providers
/// in their bones; none online to add it on, back to where it was opened from, at the moment it is made. `src`: what
/// its core is of (settings_core's), what another station's choice asks that station's flow of before it opens.
pub fn new_profile_node(
  v : @view.View,
  core : Core,
  src : Source,
  here : () -> Here,
  address : String,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
) -> Unit {
  let online = fn() -> Array[Json]? {
    match @settings.stations_of(core, here()).value {
      Some(Array(list)) => Some(list.filter(fn(s) { flag(Some(s), "online") }))
      _ => None
    }
  }
  // (the station it is added on: "" while the stations are read, "~" none online)
  let station = fn() {
    match online() {
      None => ""
      Some(list) =>
        if list.iter().any(fn(s) { text(Some(s), "station") == address }) {
          address
        } else {
          match list.get(0) {
            Some(s) => text(Some(s), "station")
            None => "~"
          }
        }
    }
  }
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  v.pick(station, fn(p, at) {
    match at {
      "" =>
        @sf.page_node(p, fn() { @sf.t("android-settings.profile.add") }, on_back~, frame~, said?, width?, tips?, fn() { ["wait"] }, fn(
          b,
          _,
        ) {
          @sf.waiting_node(b, providers_sample_node, note=fn() { { reading: true, text: @sf.t("common.readingStations"), failing: [] } })
        })
      "~" => {
        // none online to add it on: back to the list
        p.at_moment(p.logic_at(), fn() { (core.pop)() }) |> ignore
        @sf.page_node(p, fn() { @sf.t("android-settings.profile.add") }, on_back~, frame~, said?, width?, tips?, fn() { [] }, fn(_, _) {  })
      }
      st => new_profile_flow_node(p, core, src, here, st, online, on_back, frame, said, width, tips)
    }
  })
}

///|
/// The add flow on station `station` (Flow) in node `v`: its draft (opened as it is first made, another station's
/// another draft), the step the core is at; a plan's sign-in started as its step comes (let go as it goes, unless it
/// made its profile), its profile come: on to its page, in this page's place. Back goes to the step before (the
/// providers), the system's back too; from the providers, to where it was opened from.
fn new_profile_flow_node(
  v : @view.View,
  core : Core,
  src : Source,
  here : () -> Here,
  station : String,
  online : () -> Array[Json]?,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  said : ((@sf.PageSaid) -> Unit)?,
  width : (() -> Double)?,
  tips : @sf.TipLayer?,
) -> Unit {
  let n = @settings.new_profile_opened(core, station, add_profile_start.get(station))
  add_profile_start.remove(station)
  let form = n.form
  let s = fn() { @settings.station_of(core, here(), station) }
  let topic = fn() { (core.topic)("profileFlow", { "station": str(station), "form": str(form) }).get() }
  let d = fn() { topic().value }
  let step = fn() { text(d(), "step") }
  let edit = fn(input : Array[(String, Json)]) {
    @settings.act(core, @sf.t("web-pages.addProfile.editAction"), "profile.flow.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]))
  }
  let sign = fn() { field(d(), "signIn") }
  let install = fn() { field(d(), "install") }
  let plan = fn() { step() == "connect" && text(d(), "method") == "plan" }
  let planning = fn() { plan() && !(install() is Some(Object(_))) && sign() is Some(Object(_)) }
  // a plan's sign-in starts as its step comes; left unfinished, let go as it goes
  v.reacts(planning, fn(on) {
    if on && !n.asked {
      let sv = @signals.untracked(sign)
      @settings.start_login(core, station, n, text(sv, "runtime"), text(sv, "access"))
    } else if !on && n.asked {
      @settings.drop_login(core, station, n)
    }
  })
  let pending = fn() { if n.login.get() == "" { None } else { @settings.pending_login(core, station, n.login.get()) } }
  // the sign-in made its profile: on to its page, in this page's place
  v.reacts(fn() { opt_text(pending(), "created") }, fn(made) {
    match made {
      Some(id) => {
        n.login.set("")
        (core.say)(@sf.t("web-pages.profiles.signedInAdded"))
        (core.in_place)(Profile(station, id))
      }
      None => ()
    }
  })
  let picking = fn() { !(d() is Some(Object(_))) || step() == "pick" }
  let leave = fn() {
    if @signals.untracked(picking) {
      on_back()
    } else {
      @settings.drop_login(core, station, n)
      edit([("provider", str(""))])
    }
  }
  // (back over it to the providers, whether or not the frame has a way back past them (BackLink's words): that step is
  // the page's own; past them, to where it was opened from, as the frame says)
  let frame = fn() -> PageFrame {
    let f = frame()
    if picking() {
      f
    } else {
      { ..f, back: Some(@sf.t("web-pages.addProfile.pick")) }
    }
  }
  // (the system's back, too: to the step before)
  v.show(fn() { !picking() }, fn(b) { b.takes_back(leave) |> ignore })
  @sf.page_node(
    v,
    fn() {
      match opt_text(d(), "title") {
        Some(x) => x
        None => @sf.t("android-settings.profile.add")
      }
    },
    on_back=leave,
    frame~,
    said?,
    width?,
    tips?,
    lead=fn() { text(d(), "hint") },
    fn() {
      if !(d() is Some(Object(_))) {
        return ["wait"]
      }
      match step() {
        "pick" => {
          let out = if online().unwrap_or([]).length() > 1 { ["stations"] } else { [] }
          out.push("machine")
          for g in items(d(), "groups") {
            out.push("group/" + text(Some(g), "id"))
          }
          out
        }
        "method" => ["method"]
        _ => if plan() { ["plan"] } else { ["form"] }
      }
    },
    fn(b, key) {
      match key {
        "wait" =>
          @sf.waiting_node(b, providers_sample_node, error=fn() {
            match topic().error {
              Some(e) => @settings.error_text(e)
              None => ""
            }
          })
        "stations" => new_profile_stations_node(b, core, src, station, online)
        "machine" =>
          machine_offers_node(
            b,
            core,
            station,
            s,
            fn() { field(field(s(), "overview"), "machineLogins") },
            fn(rt) { edit([("provider", str(if rt == "claude" { "anthropic" } else { "openai" })), ("method", str("plan"))]) },
            tips,
          )
        "method" => new_profile_methods_node(b, d, fn(id) { edit([("method", str(id))]) })
        "plan" => new_profile_plan_node(b, core, station, n, s, d, install)
        "form" => new_profile_form_node(b, core, station, n, d, edit)
        _ => {
          let gid = key.exact_view(start=6).to_owned()
          let group = fn() {
            let all = items(d(), "groups")
            match all.search_by(fn(g) { text(Some(g), "id") == gid }) {
              Some(i) => Some(all[i])
              None => None
            }
          }
          provider_group_node(b, group, fn(id) { edit([("provider", str(id))]) })
        }
      }
    },
  )
}

///|
/// Which station it is added on (its online ones, a choice each) in node `b`: another is another draft, its page in
/// this one's place. Pressed, that station's draft is opened and its flow asked (`src`), this page as it is meanwhile;
/// its page comes in this one's place once the flow is answered, whole in the frame it comes, what was asked handed to
/// it (sfbase's open_answered, press_wait: no page on its bones, no title, hint or providers coming in after it). The
/// choice shows the station pressed from the press's frame; back to this one where the wait is given up (this page
/// left, another pressed), that draft let go with it.
fn new_profile_stations_node(b : @view.View, core : Core, src : Source, station : String, online : () -> Array[Json]?) -> Unit {
  let list = fn() { online().unwrap_or([]) }
  // (the station pressed whose page is waited for, "" none; and what waits for it)
  let pressed : @signals.Signal[String] = @signals.signal("")
  let waiting : Ref[@sfbase.PressWait?] = Ref(None)
  b.box(fn(r) {
    @sf.style_node(r, fn() { ap_stations })
    @sf.labelled_field_node(r, fn() { @sf.t("web-pages.addProfile.station") }, fn(f) {
      @sf.page_choice_node(
        f,
        fn() { list().map(fn(s) { text(Some(s), "name") }) },
        fn() {
          let at = match pressed.get() {
            "" => station
            p => p
          }
          list().search_by(fn(s) { text(Some(s), "station") == at }).unwrap_or(0)
        },
        fn(i) {
          guard @signals.untracked(list).get(i) is Some(s) else { return }
          let other = text(Some(s), "station")
          guard other != pressed.untracked() else { return }
          // (the one pressed before: waited for no more)
          match waiting.val {
            Some(w) => {
              waiting.val = None
              w.give_up()
            }
            None => ()
          }
          if other == station {
            pressed.set("")
            return
          }
          pressed.set(other)
          let n = @settings.new_profile_opened(core, other, add_profile_start.get(other))
          let w = @sfbase.open_answered(
            src,
            [("profileFlow", { "station": str(other), "form": str(n.form) })],
            fn() { app.nav.replace(Setting(NewProfile(other))) },
            let_go=fn() {
              @settings.left(NewProfile(other))
              if pressed.untracked() == other {
                pressed.set("")
              }
            },
          )
          if w.waiting() {
            waiting.val = Some(w)
          }
        },
      )
    })
  })
  |> ignore
}

///|
/// A group of providers (`g`, as the core says it now) in node `b`, each by its mark and its name (pick_tiles_node);
/// one pressed, `pick` given its id.
fn provider_group_node(b : @view.View, g : () -> Json?, pick : (String) -> Unit) -> Unit {
  let providers = fn() { items(g(), "providers") }
  @sf.pick_tiles_node(
    b,
    fn() { text(g(), "title") },
    fn() { providers().map(fn(p) { (text(Some(p), "id"), text(Some(p), "name")) }) },
    fn(m, id) {
      let pv = fn() {
        let all = providers()
        match all.search_by(fn(p) { text(Some(p), "id") == id }) {
          Some(i) => Some(all[i])
          None => None
        }
      }
      provider_mark_node(m, fn() {
        (
          match text(pv(), "runtime") {
            "" => "claude"
            rt => rt
          },
          match text(pv(), "kind") {
            "" => "api-provider"
            k => k
          },
          text(pv(), "mark"),
        )
      }, ap_tile_glyph)
    },
    pick,
  )
}

///|
/// A provider's mark (provider_logo_node's) in node `m`, `size` across, by its runtime, its kind and its own mark as
/// `of` says them now.
fn provider_mark_node(m : @view.View, of : () -> (String, String, String), size : Double) -> Unit {
  m.pick(of, fn(l, k) { @sf.provider_logo_node(l, k.0, k.1, size, k.2) |> ignore })
}

///|
/// The providers while they are read, in their bones (waiting_node's sample): two groups of made-up ones, as
/// provider_group_node shows them.
fn providers_sample_node(b : @view.View) -> Unit {
  for g in [(4, 3), (5, 5)] {
    let providers = Array::makei(g.1, fn(i) {
      Json::object({ "id": Json::string("sample" + i.to_string()), "name": Json::string(@sf.sample_words(4 + i % 3)) })
    })
    let group = Some(Json::object({ "title": Json::string(@sf.sample_words(g.0)), "providers": Json::array(providers) }))
    provider_group_node(b, fn() { group }, fn(_) {  })
  }
}

///|
/// The two ways to connect a vendor that has both (methods) in node `b`, as the core says them (`d`'s choices): each
/// its title and what it is (ways_node), the plan's by the subscription's mark, a key's by the provider's.
fn new_profile_methods_node(b : @view.View, d : () -> Json?, choose : (String) -> Unit) -> Unit {
  let tile = fn() { field(d(), "tile") }
  @sf.ways_node(
    b,
    fn() { items(d(), "choices").map(fn(c) { (text(Some(c), "id"), text(Some(c), "title"), text(Some(c), "hint")) }) },
    choose,
    mark=fn(m, id) {
      provider_mark_node(m, fn() {
        let t = tile()
        let kind = if id == "plan" && text(t, "kind") != "opencode-go" && text(t, "id") != "moonshotai" {
          "subscription"
        } else {
          match text(t, "kind") {
            "" => "api-provider"
            k => k
          }
        }
        (text(field(d(), "signIn"), "runtime"), kind, text(t, "mark"))
      }, ap_way_glyph)
    },
  )
}

///|
/// A plan's sign-in (`d`'s connect step, its method the plan) in node `b`: the runtime it signs in with installed first
/// where the station has none (install_step_node); else what the person does in the browser (login_steps_node), or why
/// it did not go on and the way to start it again; what it will be usable for under it.
fn new_profile_plan_node(
  b : @view.View,
  core : Core,
  station : String,
  n : @settings.NewProfile,
  s : () -> Json?,
  d : () -> Json?,
  install : () -> Json?,
) -> Unit {
  let on = fn() { [("station", station), ("id", n.login.get())] }
  let job = fn() { field(if n.login.get() == "" { None } else { @settings.pending_login(core, station, n.login.get()) }, "job") }
  let state = fn() { text(job(), "state") }
  let failed = fn() { n.error.get() != "" || state() == "failed" || state() == "cancelled" }
  let copied : @signals.Signal[Bool] = @signals.signal(false)
  b.box(fn(f) {
    @sf.style_node(f, fn() { ap_form })
    f.pick(fn() { if install() is Some(Object(_)) { 0 } else if failed() { 1 } else { 2 } }, fn(q, what) {
      q.gap(Is(pf_card_gap)) |> ignore
      match what {
        0 => install_step_node(q, core, station, install)
        1 => {
          @sf.words_node(q, fn() {
            if n.error.get() != "" {
              n.error.get()
            } else {
              match opt_text(job(), "error") {
                Some(e) => e
                None => @sf.t("web-pages.profiles.signInUnfinished")
              }
            }
          }, fn() { ap_note_bad })
          |> ignore
          q.box(fn(r) {
            r.row(Is(true)) |> ignore
            @sf.button_node(r, fn() { @sf.t("web-pages.profiles.restart") }, fn() {
              // let go, then asked again at once
              @settings.drop_login(core, station, n)
              let sv = field(@signals.untracked(d), "signIn")
              @settings.start_login(core, station, n, text(sv, "runtime"), text(sv, "access"))
            })
            |> ignore
          })
          |> ignore
        }
        _ =>
          login_steps_node(
            q,
            core,
            job,
            fn() { text(field(d(), "signIn"), "provider") },
            fn() { is_doing(core, ["login.code"], on()) },
            fn(code, sent) {
              let id = n.login.untracked()
              if id != "" {
                @settings.act(
                  core,
                  @sf.t("web-pages.profiles.finish"),
                  "login.code",
                  obj([("station", str(station)), ("id", str(id)), ("code", str(code))]),
                  then=fn(_) { sent() },
                )
              }
            },
            copied,
            in_station=(fn() { text(s(), "name") }, fn() { is_doing(core, ["login.browser"], on()) }, fn(what) {
              let id = n.login.untracked()
              if id != "" {
                @settings.act(core, what, "login.browser", obj([("station", str(station)), ("id", str(id))]), then=fn(v) {
                  (core.open_screen)(station, text(Some(v), "screen"))
                })
              }
            }),
          )
      }
    })
    f.show(fn() { text(d(), "usesLine") != "" }, fn(u) {
      @sf.style_node(u, fn() { ap_uses_below })
      @sf.words_node(u, fn() { text(d(), "usesLine") }, fn() { pf_muted }) |> ignore
    })
  })
  |> ignore
}

///|
/// A plan's sign-in on a station without the runtime it signs in with (InstallStep, the core's `install`), on a card in
/// node `b`: installing it first, how that stands (a bar as far as it has gone), its button in the card's foot corner
/// where the viewer may (`software.update`); the sign-in starts once it is.
fn install_step_node(b : @view.View, core : Core, station : String, install : () -> Json?) -> Unit {
  let runtime = fn() { text(install(), "runtime") }
  let action = fn() { opt_text(install(), "action") }
  b.pick(fn() { action() is Some(_) }, fn(q, footed) {
    @sf.page_card_node(q, footed~, fn(k) {
      @sf.card_lines_node(
        k,
        fn() { text(install(), "title") },
        note=fn() {
          match opt_text(install(), "detail") {
            Some(_) => ""
            None =>
              match opt_text(install(), "note") {
                Some(x) => x
                None => @sf.t("web-pages.profiles.installThenSignIn")
              }
          }
        },
        bad=fn() { opt_text(install(), "detail").unwrap_or("") },
      )
      k.show(fn() { text(install(), "state") == "installing" }, fn(x) {
        x.box(fn(bar) {
          @sf.style_node(bar, fn() { ap_bar })
          @sf.progress_node(
            bar,
            fn() {
              if has(install(), "percent") && !(field(install(), "percent") is Some(Null)) {
                Some(number(install(), "percent") / 100.0)
              } else {
                None
              }
            },
            fn() { @ui.tree_theme().line },
            fn() { @sf.theme().p.accent },
          )
          |> ignore
        })
        |> ignore
      })
      if footed {
        // (last on its card: its button in its foot corner, concentric with it)
        @sf.card_foot_node(k, fn(f) {
          @sf.button_node(
            f,
            fn() { action().unwrap_or("") },
            fn() {
              let what = @signals.untracked(action).unwrap_or("")
              @settings.act(core, what, "software.update", obj([("station", str(station)), ("id", str(@signals.untracked(runtime)))]))
            },
            tone=Primary,
            busy=fn() { is_doing(core, ["software.update"], [("station", station), ("id", runtime())]) },
            card_words=true,
          )
          |> ignore
        })
      }
    })
  })
}

///|
/// The form of a key (ConnectForm) in node `b`, as the core's draft says it now (`d`): where the provider is (its
/// example as the placeholder), its region and protocol where it has a choice, the key (a secret's field: its hint, or
/// what is wrong with it); 验证并添加, made only if it works (`profile.flow.submit`). What is typed told to the core as
/// it is typed; each field begins with what the draft holds as the form is made.
fn new_profile_form_node(
  b : @view.View,
  core : Core,
  station : String,
  n : @settings.NewProfile,
  d : () -> Json?,
  edit : (Array[(String, Json)]) -> Unit,
) -> Unit {
  let form = n.form
  let pending = fn() { flag(d(), "pending") }
  let submitting = fn() { is_doing(core, ["profile.flow.submit"], [("station", station), ("form", form)]) }
  let submit = fn() {
    if flag(@signals.untracked(d), "canSubmit") && !@signals.untracked(submitting) {
      (core.call)("profile.flow.submit", obj([("station", str(station)), ("form", str(form))]), fn(r) {
        match r {
          Ok(v) => {
            (core.say)(@sf.t("web-pages.profiles.verifiedAdded"))
            (core.in_place)(Profile(station, text(Some(v), "id")))
          }
          // (what is wrong is the draft's own `error`, under the key)
          Err(_) => ()
        }
      })
    }
  }
  // (what is typed told to the core as it is typed, where it is not what the draft says already)
  let typed = fn(f : @ui.Field, key : String) {
    b.reacts(fn() { f.text() }, fn(now) {
      if now != text(@signals.untracked(d), key) {
        edit([(key, str(now))])
      }
    })
  }
  let endpoint = @ui.Field::new(text=text(@signals.untracked(d), "endpoint"))
  let key = @ui.Field::new(text=text(@signals.untracked(d), "key"))
  typed(endpoint, "endpoint")
  typed(key, "key")
  b.box(fn(f) {
    @sf.style_node(f, fn() { ap_form })
    f.show(fn() { flag(d(), "showEndpoint") }, fn(x) {
      @sf.labelled_field_node(x, fn() { @sf.t("common.provider.endpoint") }, hint=fn() { text(d(), "endpointHint") }, fn(c) {
        @sf.input_node(
          c,
          endpoint,
          placeholder_by=fn() {
            match text(d(), "endpointExample") {
              "" => "https://"
              x => x
            }
          },
          disabled=pending,
          submitted=fn(_) { submit() },
        )
        |> ignore
      })
    })
    let regions = fn() { items(d(), "regions") }
    f.show(fn() { regions().length() > 1 }, fn(x) {
      @sf.labelled_field_node(x, fn() { @sf.t("web-pages.addProfile.region") }, fn(c) {
        @sf.page_choice_node(
          c,
          fn() { regions().map(fn(r) { text(Some(r), "label") }) },
          fn() { regions().search_by(fn(r) { text(Some(r), "id") == text(d(), "region") }).unwrap_or(0) },
          fn(i) {
            match @signals.untracked(regions).get(i) {
              Some(r) => edit([("region", str(text(Some(r), "id")))])
              None => ()
            }
          },
        )
      })
    })
    let protocols = fn() { items(d(), "protocols") }
    f.show(fn() { protocols().length() > 1 }, fn(x) {
      @sf.labelled_field_node(x, fn() { @sf.t("web-pages.addProfile.protocol") }, fn(c) {
        @sf.page_choice_node(
          c,
          fn() { protocols().map(fn(p) { text(Some(p), "label") }) },
          fn() { protocols().search_by(fn(p) { text(Some(p), "id") == text(d(), "protocol") }).unwrap_or(0) },
          fn(i) {
            match @signals.untracked(protocols).get(i) {
              Some(p) if text(Some(p), "id") != text(@signals.untracked(d), "protocol") => edit([("protocol", str(text(Some(p), "id")))])
              _ => ()
            }
          },
        )
      })
    })
    f.show(fn() { flag(d(), "showKey") }, fn(x) {
      @sf.labelled_field_node(x, fn() { text(d(), "keyLabel") }, hint=fn() { text(d(), "keyHint") }, error=fn() { text(d(), "error") }, fn(c) {
        @sf.input_node(c, key, placeholder=@sf.t("android-settings.profile.keyPlaceholder"), secret=true, disabled=pending, submitted=fn(_) {
          submit()
        })
        |> ignore
      })
    })
    f.box(fn(r) {
      @sf.style_node(r, fn() { ap_submit })
      r.pick(fn() { flag(d(), "showKey") }, fn(y, keyed) {
        @sf.button_node(
          y,
          fn() { text(d(), "submitLabel") },
          submit,
          tone=Primary,
          icon=if keyed { "" } else { "plus" },
          busy=fn() { submitting() || pending() },
          disabled=fn() { !flag(d(), "canSubmit") },
        )
        |> ignore
      })
    })
    |> ignore
    f.show(fn() { text(d(), "usesLine") != "" }, fn(u) { @sf.words_node(u, fn() { text(d(), "usesLine") }, fn() { pf_muted }) |> ignore })
  })
  |> ignore
}

///|
/// The accounts this machine's own Claude Code and Codex are signed in with, not used yet (MachineLoginOffers), in node
/// `b`: one kept in a file used as it is (a profile on the machine's login, `profile.useMachineLogin`), one kept only in
/// the keychain offered as a sign-in with the same account (`sign_in`, by its runtime). A refused one is said so. Each a
/// card: its mark, words and allowance in a row 20 in, its button across its foot corners. `logins`: those of station
/// `s`'s overview (as its page has it, or that part alone where a list shows every station's).
fn machine_offers_node(
  b : @view.View,
  core : Core,
  station : String,
  s : () -> Json?,
  logins : () -> Json?,
  sign_in : (String) -> Unit,
  tips : @sf.TipLayer?,
) -> Unit {
  let offers = fn() {
    match logins() {
      Some(Array(a)) => a.filter(fn(l) { flag(Some(l), "offered") })
      _ => []
    }
  }
  b.show(fn() { offers().length() > 0 }, fn(x) {
    @sf.style_node(x, fn() { ap_offers })
    @sf.words_node(x, fn() {
      @sf.t("web-pages.profiles.machineSignedIn", args=[("station", if text(s(), "name") != "" { text(s(), "name") } else { @sf.t("web-main.machine.this") })])
    }, fn() { ap_group_head })
    |> ignore
    x.each(offers, fn(l) { text(Some(l), "runtime") }, fn(card, l) {
      let lv = fn() { Some(l.get()) }
      let rt = @signals.untracked(fn() { text(lv(), "runtime") })
      let quota = fn() { field(lv(), "quota") }
      card.pick(fn() { text(quota(), "state") == "blocked" }, fn(c, blocked) {
        @sf.style_node(c, fn() { if blocked { ap_offer } else { ap_offer_footed_style() } })
        c.box(fn(h) {
          @sf.style_node(h, fn() { ap_offer_head })
          h.box(fn(m) {
            @sf.style_node(m, fn() { ap_offer_mark })
            @sf.provider_logo_node(m, rt, "subscription", ap_offer_glyph, "") |> ignore
          })
          |> ignore
          // (short of room, its name kept: whether it is signed in leaves its line first, then its plan)
          h.box(fn(w) {
            @sf.style_node(w, fn() { ap_offer_text }, in_row=true)
            w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            w.box(fn(line) {
              @sf.style_node(line, fn() { pf_name_line })
              line.fits(Is(true)) |> ignore
              @sf.words_node(line, fn() { @settings.runtime_label(rt) }, fn() { ap_offer_title }) |> ignore
              line.show(fn() { text(lv(), "planText") != "" }, fn(t) {
                @sf.tag_node(t, fn() { text(lv(), "planText") })
                t.drops(Is(ap_drop_plan)) |> ignore
              })
              line.box(fn(p) {
                p.row(Is(true)).drops(Is(ap_drop_state)) |> ignore
                @sf.pill_node(
                  p,
                  fn() { if blocked { @sf.t("web-main.profile.blocked") } else { @sf.t("web-main.profile.machineSignedIn") } },
                  tone=if blocked { Red } else { Green },
                )
                |> ignore
              })
              |> ignore
            })
            |> ignore
            @sf.words_node(w, fn() { if text(lv(), "email") != "" { text(lv(), "email") } else { @sf.t("web-main.profile.signedIn") } }, fn() {
              ap_offer_line
            })
            |> ignore
            // why it cannot be used (what the provider said)
            w.show(fn() { blocked || text(quota(), "state") == "unavailable" }, fn(y) {
              @sf.words_node(y, fn() { text(quota(), "detail") }, fn() { if blocked { ap_note_bad } else { ap_note } }) |> ignore
            })
          })
          |> ignore
          @sf.quota_chips_node(h, quota, small=true, tips?)
        })
        |> ignore
        if !blocked {
          c.box(fn(f) {
            @sf.style_node(f, fn() { @sf.foot_across(@sf.button_height()) })
            f.pick(fn() { flag(lv(), "usable") }, fn(y, usable) {
              let button = if usable {
                @sf.button_node(
                  y,
                  fn() { @sf.t("web-pages.profiles.useThis") },
                  fn() {
                    (core.call)("profile.useMachineLogin", obj([("station", str(station)), ("runtime", str(rt))]), fn(r) {
                      match r {
                        Ok(v) => {
                          (core.say)(@sf.t("web-pages.profiles.machineAdded"))
                          (core.in_place)(Profile(station, text(Some(v), "id")))
                        }
                        Err(e) => (core.say)(@settings.error_text(e))
                      }
                    })
                  },
                  busy=fn() { is_doing(core, ["profile.useMachineLogin"], [("station", station), ("runtime", rt)]) },
                  across=true,
                )
              } else {
                @sf.button_node(y, fn() { @sf.t("web-pages.profiles.signIn") }, fn() { sign_in(rt) }, across=true)
              }
              match tips {
                Some(t) =>
                  @sf.tip_node(t, button, fn() {
                    if usable {
                      @sf.t("web-pages.profiles.useMachineTip")
                    } else {
                      @sf.t("web-pages.profiles.keychainTip", args=[("name", "still.fail")])
                    }
                  })
                  |> ignore
                None => ()
              }
            })
          })
          |> ignore
        }
      })
    })
  })
}

///|
/// The profiles' place with none to pick yet (ProfilesFirst; the place's, profiles_place_node's) in node `v`: the first
/// to add, each station of the workspace a line (how it stands, its name; online, 添加 profile, the primary where it is
/// the only one; else that it is offline), an online one's own logins not used yet under it (machine_offers_node: one
/// signed in again as its vendor's plan on the add page).
pub fn profiles_first_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
  tips? : @sf.TipLayer,
) -> Unit {
  let stations = fn() {
    match @settings.stations_of(core, here()).value {
      Some(Array(list)) => list
      _ => []
    }
  }
  let profiles = fn() { (core.topic)("profiles", { "scope": str(here().workspace) }).get().value }
  @sf.page_node(v, fn() { "Profile" }, on_back~, frame~, said?, width?, tips?, fn() { ["first"] }, fn(b, _) {
    @sf.first_one_node(
      b,
      fn() { @sf.t("web-pages.settings.profiles.addFirst") },
      lead=fn() { @sf.t("web-pages.settings.profiles.lead", args=[("name", "still.fail")]) },
      art=fn(a) { a.pick(fn() { @sf.theme().dark }, fn(x, dark) { @sf.drawable_node(x, if dark { "illus_no_profile_dark" } else { "illus_no_profile" }, pf_first_art_w) |> ignore }) },
      fn(a) {
        a.box(fn(l) {
          @sf.style_node(l, fn() { pf_first_stations })
          l.each(stations, fn(st) { text(Some(st), "station") }, fn(row, st) {
            let address = @signals.untracked(fn() { text(Some(st.get()), "station") })
            let sv = fn() { Some(st.get()) }
            let online = fn() { flag(sv(), "online") }
            @sf.style_node(row, fn() { pf_first_station })
            row.box(fn(line) {
              @sf.style_node(line, fn() { pf_first_row })
              @sf.state_dot_node(line, fn() { if online() { "online" } else { "offline" } })
              @sf.words_node(line, fn() { text(sv(), "name") }, fn() { pf_first_name }).grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              line.pick(fn() { if online() { Some(stations().length() == 1) } else { None } }, fn(e, at) {
                match at {
                  Some(only) =>
                    @sf.button_node(
                      e,
                      fn() { @sf.t("web-pages.settings.profiles.add") },
                      fn() { (core.push)(NewProfile(address)) },
                      tone=if only { Primary } else { Plain },
                      icon="plus",
                    )
                    |> ignore
                  None => @sf.words_node(e, fn() { @sf.t("web-pages.settings.profiles.offlineAdd") }, fn() { pf_first_offline }) |> ignore
                }
              })
            })
            |> ignore
            row.show(online, fn(m) {
              // (its logins offered, as the profiles' list the place holds says them)
              machine_offers_node(m, core, address, sv, fn() { Some(Json::array(@settings.profiles_offers_of(profiles(), address))) }, fn(rt) {
                // the machine's login signed in again as its vendor's plan, on the add page
                add_profile_start[address] = [("provider", str(if rt == "claude" { "anthropic" } else { "openai" })), ("method", str("plan"))]
                (core.push)(NewProfile(address))
              }, tips)
            })
          })
        })
        |> ignore
      },
    )
  })
}

// ── styles ─────────────────────────────────────────

///|
let ap_tile_glyph : Double = 16.0

///|
/// A way's mark before its title, narrow (the phone's choice row's).
let ap_way_glyph : Double = 18.0

///|
let ap_offer_glyph : Double = 18.0

///|
/// The station it is added on (stations: 24 over what follows).
// kept across runs: a value (no field of it changes)
let ap_stations : @ui.Style = @ui.css("w=Full pb=S6")

///|
// kept across runs: a value (no field of it changes)
let ap_group_head : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, w=Full)

///|
/// A note under what it tells of (the card's, the form's: the meta's muted), in red where it says what is wrong.
// kept across runs: a value (no field of it changes)
let ap_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ap_note_bad : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, w=Full)

///|
/// An offer's words beside its mark (2 apart): its name strong on its line, its account under it on one line, cut.
// kept across runs: a value (no field of it changes)
let ap_offer_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ap_offer_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ap_offer_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// The form (form: 18 apart).
// kept across runs: a value (no field of it changes)
let ap_form : @ui.Style = @ui.css("w=Full gap=S4_5")

///|
// kept across runs: a value (no field of it changes)
let ap_submit : @ui.Style = @ui.css("row w=Full")

///|
/// What it will be usable for, under a plan's steps (usesBelow: 14 apart from them).
// kept across runs: a value (no field of it changes)
let ap_uses_below : @ui.Style = @ui.css("w=Full pt=S3_5")

///|
/// An install's bar (as far as it has gone, 4 over and under).
// kept across runs: a value (no field of it changes)
let ap_bar : @ui.Style = @ui.css("w=Full py=S1")

///|
/// The machine's own logins (machineLogins: 4 apart, its heading over them; 28 under them).
// kept across runs: a value (no field of it changes)
let ap_offers : @ui.Style = @ui.css("w=Full pb=S7 gap=S1")

///|
/// A login of the machine's own (machineLogin): a card of the ladder's, its words 20 in, its mark in its top corner
/// (round by the ladder's there: mbui works it out), its button across its foot corners (@sf.card_foot_in).
// kept across runs: a value (no field of it changes)
let ap_offer : @ui.Style = @ui.css("w=Full gap=S3 radius=Xl3 bg=Card").then(@ui.style(p=@sf.room_of(@sf.card_pad)))

///|
/// With its button: its foot as far in as makes the button concentric with its corner (the theme's button height).
fn ap_offer_footed_style() -> @ui.Style {
  ap_offer.then(@sf.foot_pad(@sf.button_height()))
}

///|
// kept across runs: a value (no field of it changes)
let ap_offer_head : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
/// An offer's mark: 32 on the neutral ground in the card's corner, where the ladder's small block's corner (10) is
/// concentric with the card's (@sf.card_mark_out).
// kept across runs: a value (no field of it changes)
let ap_offer_mark : @ui.Style = @ui.css("w=S8 h=S8 bg=Neutral align=ACenter justify=JCenter").then(
  @ui.style(radius=@sf.small_radius),
).then(@sf.card_mark_out)

///|
/// What leaves a machine's login's line first, short of room: whether it is signed in, then its plan.
let ap_drop_state : Int = 1

///|
let ap_drop_plan : Int = 2

///|
/// The art over the first profile to add.
let pf_first_art_w : Double = 240.0

///|
/// Each station a row (firstStations: 28 apart, at the start; firstStationRow: 10 apart; its name semibold, taking the
/// room; its machine's logins 14 under it).
// kept across runs: a value (no field of it changes)
let pf_first_stations : @ui.Style = @ui.css("w=Full gap=S7 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let pf_first_station : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let pf_first_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pf_first_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let pf_first_offline : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)
