// A connect's Slack app on the desktop (still.fail web/src/pages/SlackApp.tsx SlackAppSection, ConfigTokenForm, AppFields,
// AppForm; SlackApp.css.ts): folded on its page (it is changed now and then), its look and permissions edited here and
// written into the app's manifest with the viewer's configuration token (`connect.putSlackApp`, given what the form
// started from: the core writes only what differs); without one, a way to add it. The permissions' sections are the
// core's (the slackApp topic's and the connect wizard's `sections`); the icon is drawn by the library (app_icon.mbt).

///|
/// A Slack app's look and permissions being edited (AppFields' settings, and what its look keeps): what is typed (its
/// fields' words: its name, what it is for, its colour) and picked, the icon made (a data URL, "" none) and why it could
/// not be, and how the icon is coming along; each as it is now, followed.
priv struct SaDraft {
  key : String
  /// the colour as it was last set (typed, or what was picked's)
  color : @signals.Signal[String]
  groups : @sf.LiveMap[String, Bool]
  icon : @signals.Signal[String]
  icon_error : @signals.Signal[String]
  /// the icon as shown (its picture's key), "" none
  shown : @signals.Signal[String]
  /// what was picked: an avatar's id, or a picture of the person's own (its key), "" neither
  picked : @signals.Signal[String]
  upload : @signals.Signal[String]
  upload_bg : @signals.Signal[String]
  /// the colour set by hand, not by what was picked
  colour_set : @signals.Signal[Bool]
  /// the picture being read to draw from: its source, how large, on what colour ("" none)
  reading : @signals.Signal[(String, Int, String)]
  mut asking : Bool
  mut started : Bool
  /// the permissions unfolded
  perms : @signals.Signal[Bool]
  name_field : @ui.Field
  desc_field : @ui.Field
  hex_field : @ui.Field
}

///|
/// The groups `settings` (a Slack app's, as the core has them) turns on.
fn sa_groups(settings : Json?) -> Map[String, Bool] {
  let groups : Map[String, Bool] = Map([])
  match field(settings, "groups") {
    Some(Object(m)) =>
      for g, v in m {
        groups[g] = v == Json::boolean(true)
      }
    _ => ()
  }
  groups
}

///|
/// A draft of `settings` (a Slack app's, as the core has them), its fields filled with them.
fn sa_draft(key : String, settings : Json?) -> SaDraft {
  {
    key,
    color: @signals.signal(text(settings, "backgroundColor")),
    groups: @sf.LiveMap::from(sa_groups(settings)),
    icon: @signals.signal(""),
    icon_error: @signals.signal(""),
    shown: @signals.signal(""),
    picked: @signals.signal(""),
    upload: @signals.signal(""),
    upload_bg: @signals.signal(""),
    colour_set: @signals.signal(false),
    reading: @signals.signal(("", 0, "")),
    asking: false,
    started: false,
    perms: @signals.signal(false),
    name_field: @ui.Field::new(text=text(settings, "name")),
    desc_field: @ui.Field::new(text=text(settings, "description")),
    hex_field: @ui.Field::new(text=text(settings, "backgroundColor")),
  }
}

///|
/// The draft `d` started again from `settings`, as it was first made of them (还原; Slack's settings changed).
fn sa_draft_reset(d : SaDraft, settings : Json?) -> Unit {
  @signals.start_batch()
  d.color.set(text(settings, "backgroundColor"))
  d.groups.clear()
  for g, v in sa_groups(settings) {
    d.groups[g] = v
  }
  d.icon.set("")
  d.icon_error.set("")
  d.shown.set("")
  d.picked.set("")
  d.upload.set("")
  d.upload_bg.set("")
  d.colour_set.set(false)
  d.reading.set(("", 0, ""))
  d.asking = false
  d.started = false
  d.perms.set(false)
  d.name_field.set(text(settings, "name"))
  d.desc_field.set(text(settings, "description"))
  d.hex_field.set(text(settings, "backgroundColor"))
  @signals.end_batch()
}

///|
/// What an app's look and permissions say of it, as the core takes its settings (the name in messages its name too).
fn sa_settings_of(name : String, description : String, color : String, groups : Map[String, Bool], settings : Json?) -> Json {
  let out : Map[String, Json] = Map([])
  for g, v in groups {
    out[g] = Json::boolean(v)
  }
  obj([
    ("name", str(name)),
    ("displayName", str(name)),
    ("description", str(description)),
    ("longDescription", str(text(settings, "longDescription"))),
    ("backgroundColor", str(color)),
    ("groups", Json::object(out)),
  ])
}

///|
/// What the draft says of the app, as the core takes its settings.
fn sa_settings(d : SaDraft, settings : Json?) -> Json {
  sa_settings_of(d.name_field.text(), d.desc_field.text(), d.color.get(), d.groups.copy(), settings)
}

///|
/// The drafts, by their form; the folds open, by station/connect; icons made, each its own picture's key.
// kept across runs: made as each form is first made; slack_app_reset empties it
let sa_drafts : Map[String, SaDraft] = Map([])

///|
// kept across runs: said by the fold's press; slack_app_reset empties it
let sa_open : Map[String, Bool] = Map([])

///|
/// What a form started from (its settings as text), by its key: a change there starts it again.
// kept across runs: said as each form starts; slack_app_reset empties it
let sa_started : Map[String, String] = Map([])

///|
/// The forms whose permissions Slack wants approved (their install links), by station/connect.
// kept across runs: said by 应用's answer; slack_app_reset empties it
let sa_approve : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
// kept across runs: counted by sa_icon_made; slack_app_reset puts it back
let sa_icons_made : Ref[Int] = Ref(0)

///|
fn slack_app_reset() -> Unit {
  sa_drafts.clear()
  sa_open.clear()
  sa_started.clear()
  sa_approve.clear()
  sa_icons_made.val = 0
  @sf.app_icons_reset()
}

///|
/// The connect's Slack app, folded (SlackAppSection), as nodes in `b`: a row of its own on a card, its title and what it
/// is for, that opens it (open as it was left, kept with its connect); open, the app as Slack has it under it (read
/// through the station: being read, none, no configuration token to write it with, or why it could not be read), its
/// form, and Slack's page of it. Apart from what follows, as a section is. `page_w`: how wide its page is; its tips in
/// `tips`.
fn slack_app_node(b : @view.View, core : Core, station : String, id : String, page_w : () -> Double, tips : @sf.TipLayer) -> Unit {
  let me = station + "/" + id
  let open : @signals.Signal[Bool] = @signals.signal(sa_open.get(me).unwrap_or(false), same=fn(a, b) { a == b })
  @sf.apart_node(b, fn(a) {
    @sf.group_node(a, fn(g) {
      g.pick(fn() { open.get() }, fn(r, now) {
        @sf.link_row_node(
          r,
          fn() { "Slack app" },
          fn() {
            sa_open[me] = !now
            open.set(!now)
          },
          note=fn() { @sf.t("web-pages.slackApp.foldNote") },
          value=fn() { if now { @sf.t("web-pages.profiles.collapse") } else { "" } },
          chevron=!now,
        )
      })
    })
    a.show(fn() { open.get() }, fn(i) { slack_app_open_node(i, core, station, id, page_w, tips) })
  })
  |> ignore
}

///|
/// The Slack app's fold open (slack_app_node's) in `i`: the app as Slack has it, as the station reads it now; its page
/// in Slack under it where Slack gives one.
fn slack_app_open_node(i : @view.View, core : Core, station : String, id : String, page_w : () -> Double, tips : @sf.TipLayer) -> Unit {
  let topic = fn() { (core.topic)("slackApp", { "station": str(station), "connect": str(id) }).get() }
  let view = fn() { topic().value }
  let links = fn() { field(view(), "links") }
  let error = fn() {
    match topic().error {
      Some(e) => error_text(e)
      None => ""
    }
  }
  i.pick(
    fn() {
      if topic().error is Some(_) {
        "failed"
      } else if view() is None {
        "reading"
      } else {
        match text(view(), "state") {
          "no_app" => "no_app"
          "no_config_token" => "no_config_token"
          "error" => "error"
          _ => "form"
        }
      }
    },
    fn(p, k) {
      match k {
        "failed" => @sf.page_note_node(p, error, bad=fn() { true })
        "reading" => @sf.page_note_node(p, fn() { @sf.t("web-pages.slackApp.loading") })
        "no_app" =>
          @sf.page_note_node(p, fn() {
            match opt_text(view(), "error") {
              Some(e) => @sf.t("web-pages.slackApp.noApp", args=[("error", e)])
              None => @sf.t("web-pages.slackApp.notConnected")
            }
          })
        "no_config_token" =>
          sa_token_card_node(
            p,
            core,
            station,
            fn() { @sf.t("web-pages.slackApp.needsToken") },
            fn() { @sf.t("web-pages.slackApp.needsTokenNote") },
            fn() { @sf.t("web-pages.slackApp.addToken") },
            false,
          )
        "error" =>
          sa_token_card_node(
            p,
            core,
            station,
            fn() { @sf.t("web-pages.slackApp.readFailed", args=[("error", text(view(), "error"))]) },
            fn() { "" },
            fn() { @sf.t("web-pages.slackApp.replaceToken") },
            true,
          )
        _ => sa_form_node(p, core, station, id, fn() { field(view(), "settings") }, links, fn() { items(view(), "sections") }, page_w, tips)
      }
    },
  )
  let settings_url = fn() { opt_text(links(), "settings").unwrap_or("") }
  i.show(fn() { settings_url() != "" }, fn(o) {
    @sf.group_node(o, fn(g) {
      @sf.link_row_node(g, fn() { @sf.t("web-pages.slackApp.openInSlack") }, fn() { (core.open_link)(@signals.untracked(settings_url)) }, out=true)
    })
  })
}

///|
/// A card saying the app wants a configuration token (none, or one Slack refused: `bad`), and the button that adds one
/// (in a dialog: ConfigTokenForm), as nodes in `p`.
fn sa_token_card_node(
  p : @view.View,
  core : Core,
  station : String,
  words : () -> String,
  note : () -> String,
  action : () -> String,
  bad : Bool,
) -> Unit {
  @sf.page_card_node(p, footed=true, fn(k) {
    @sf.card_lines_node(k, fn() { "" }, words=fn() { if bad { "" } else { words() } }, note~, bad=fn() { if bad { words() } else { "" } })
    @sf.card_foot_node(k, fn(f) { @sf.button_node(f, action, fn() { config_token_dialog(core, station) }, card_words=true) |> ignore })
  })
}

///|
/// A Slack workspace's app configuration token added, in a dialog (SlackAppSection's Dialog: ConfigTokenForm).
fn config_token_dialog(core : Core, station : String) -> Unit {
  let key = "config-token/" + (desk_dialogs.val + 1).to_string()
  open_dialog(@sf.t("web-pages.slackApp.addTokenTitle"), wide=true, fn(c, shut) {
      config_token_form(c, core, station, key, fn() { shut() })
    }, fn(_, _) {  })
}

///|
/// What a configuration token form went through: why the station refused it ("" none).
// kept across runs: said by its call's answer; slack_app_reset leaves it (keyed by the dialog's own key)
let sa_token_errors : Map[String, String] = Map([])

///|
/// Adding a Slack workspace's app configuration token by its refresh token (ConfigTokenForm): three steps, each a
/// number in a circle, its title and what to do (Slack's apps page opened from the first; the token pasted in the
/// third, added at once as it is pasted whole). `flow`: the connect wizard's (its station and form), which keeps the
/// token and says whether it is ready and what is wrong with it; else the station checks it as it is added.
/// `replacing`: its button's words say it is used instead.
fn config_token_form(
  c : @ui.Ctx,
  core : Core,
  station : String,
  key : String,
  saved : () -> Unit,
  flow? : (Json?, () -> Unit, (String) -> Unit),
  replacing? : Bool = false,
) -> Unit {
  let tf = field_of(key + "/token")
  let token = tf.text().trim(chars=" \t\n").to_owned()
  // (with the wizard: its view, how it is told to add it, how each change is told)
  let (ready, wrong, busy) = match flow {
    Some((view, _, _)) =>
      (
        flag(view, "configReady"),
        opt_text(view, "configError").unwrap_or(""),
        is_doing(core, ["connect.flow.config"], [("station", station)]),
      )
    None => (token != "", sa_token_errors.get(key).unwrap_or(""), is_doing(core, ["slack.addConfigToken"], [("station", station)]))
  }
  let add = fn() {
    match flow {
      Some((_, act, _)) => act()
      None => {
        sa_token_errors.remove(key)
        (core.call)("slack.addConfigToken", obj([("station", str(station)), ("refreshToken", str(token))]), fn(r) {
          match r {
            Ok(_) => {
              tf.set("")
              (core.say)(@sf.t("web-pages.slackApp.tokenAdded"))
              saved()
            }
            Err(e) => sa_token_errors[key] = error_text(e)
          }
        })
      }
    }
  }
  match flow {
    Some((_, _, edit)) =>
      if sa_started.get(key + "/config").unwrap_or("") != token {
        sa_started[key + "/config"] = token
        c.tell(key + "/config", fn() { edit(token) })
      }
    None => ()
  }
  c.box(style=sa_guide, fn() {
    sa_guide_step(c, 1, @sf.t("web-pages.slackApp.step1"), @sf.t("web-pages.slackApp.step1Note"), fn() {
      @sf.button(c, @sf.t("web-pages.slackApp.openApps"), key=key + "/apps", tone=Primary, icon="external", on_press=fn() {
        (core.open_link)("https://api.slack.com/apps")
      }) |> ignore
    })
    sa_guide_step(c, 2, @sf.t("web-pages.slackApp.step2"), @sf.t("web-pages.slackApp.step2Note"), fn() {  })
    sa_guide_step(c, 3, @sf.t("web-pages.slackApp.step3"), @sf.t("web-pages.slackApp.step3Note", args=[("name", "still.fail")]), fn() {
      c.box(style=sa_input_row, fn() {
        c.box(style=sa_input_grow, fn() { @sf.input(c, key + "/token-input", placeholder="xoxe-1-…", secret=true, field=tf) |> ignore })
        |> ignore
        @sf.button(
          c,
          @sf.t(if replacing { "web-pages.slackApp.useThis" } else { "web-pages.slackApp.add" }),
          key=key + "/add",
          tone=Primary,
          busy~,
          disabled=!ready,
          on_press=fn() {
            add()
          },
        ) |> ignore
      })
      |> ignore
      if wrong != "" {
        c.text(wrong, style=desk_note_bad) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// One of the guide's steps (tokenGuide li: its number in a 24 circle on the neutral ground, the meta's 12 in 600
/// muted, 36 in; its title in 600, what to do muted, what it holds under them).
fn sa_guide_step(c : @ui.Ctx, n : Int, title : String, note : String, body : () -> Unit) -> Unit {
  c.box(style=sa_step, fn() {
    c.box(style=sa_step_number, fn() { c.text(n.to_string(), style=sa_step_number_words) |> ignore }) |> ignore
    c.box(style=sa_step_body, fn() {
      c.text(title, style=desk_strong) |> ignore
      c.text(note, style=desk_muted) |> ignore
      body()
    })
    |> ignore
  })
  |> ignore
}

///|
/// The app's form (AppForm, a card) as nodes in `p`: Slack asking for changed permissions to be approved (its page
/// opened from it); its look and permissions; why its icon could not be made; 还原 while changed, 应用 writing what
/// changed (the core compares it with what the form started from). Started again when Slack's settings change.
fn sa_form_node(
  p : @view.View,
  core : Core,
  station : String,
  id : String,
  settings : () -> Json?,
  links : () -> Json?,
  sections : () -> Array[Json],
  page_w : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  let me = station + "/" + id
  let key = "slack-app/" + me
  let start = fn() {
    match settings() {
      Some(s) => s.stringify()
      None => ""
    }
  }
  let started = @signals.untracked(start)
  let d = match sa_drafts.get(key) {
    Some(d) if sa_started.get(key) == Some(started) => d
    _ => {
      let d = sa_draft(key, @signals.untracked(settings))
      sa_drafts[key] = d
      sa_started[key] = started
      d
    }
  }
  // (Slack's settings changed: the form started again from them)
  p.reacts(start, fn(now) {
    if sa_started.get(key) != Some(now) {
      sa_started[key] = now
      sa_draft_reset(d, @signals.untracked(settings))
    }
  })
  let busy = fn() { is_doing(core, ["connect.putSlackApp"], [("station", station), ("connect", id)]) }
  let now = fn() { sa_settings(d, settings()) }
  let dirty = fn() {
    let s = settings()
    now() != sa_settings_of(text(s, "name"), text(s, "description"), text(s, "backgroundColor"), sa_groups(s), s) ||
    d.icon.get() != ""
  }
  @sf.page_card_node(p, footed=true, fn(k) {
    k.show(fn() { sa_approve.get(me) is Some(_) }, fn(a) {
      a.box(fn(b) {
        @sf.style_node(b, fn() { sa_blue })
        b.ground(By(fn() { @sf.theme().p.blue_bg })) |> ignore
        @sf.icon_node(b, "shield-check", cd_icon, By(fn() { @sf.theme().p.blue })) |> ignore
        b.box(fn(w) {
          @sf.style_node(w, fn() { cd_effect_words }, in_row=true)
          @sf.words_node(w, fn() { @sf.t("web-pages.slackApp.approveNote") }, fn() { sa_blue_words }) |> ignore
        })
        |> ignore
        @sf.button_node(
          b,
          fn() { @sf.t("web-pages.slackApp.approve") },
          fn() {
            let install = sa_approve.get(me).unwrap_or("")
            sa_approve.remove(me)
            (core.open_link)(install)
          },
          tone=Primary,
        )
        |> ignore
      })
      |> ignore
    })
    app_fields_node(k, core, d, sections, fn() { sa_column(page_w()) - 2.0 * sa_card_in }, tips)
    k.show(fn() { d.icon_error.get() != "" }, fn(e) { @sf.card_lines_node(e, fn() { "" }, bad=fn() { d.icon_error.get() }) })
    @sf.card_foot_node(k, at_end=true, fn(f) {
      f.show(dirty, fn(r) {
        @sf.button_node(r, fn() { @sf.t("web-pages.slackApp.revert") }, fn() { sa_draft_reset(d, @signals.untracked(settings)) }, tone=Ghost)
        |> ignore
      })
      @sf.button_node(
        f,
        fn() { @sf.t("web-pages.slackApp.apply") },
        fn() {
          let (input0, from, links_now) = @signals.untracked(fn() { (now(), settings(), links()) })
          let input = match input0 {
            Object(m) => {
              let m2 = Map::from_iter(m.iter())
              let icon = d.icon.untracked()
              if icon != "" {
                m2["icon"] = str(icon)
              }
              Json::object(m2)
            }
            other => other
          }
          (core.call)(
            "connect.putSlackApp",
            obj([("station", str(station)), ("connect", str(id)), ("input", input), ("from", from.unwrap_or(Json::null()))]),
            fn(r) {
              match r {
                Ok(v) => {
                  let rv = Some(v)
                  let approve = flag(rv, "permissionsUpdated")
                  d.icon.set("")
                  d.icon_error.set(opt_text(rv, "iconError").unwrap_or(""))
                  let install = text(field(rv, "links"), "install")
                  if approve {
                    sa_approve[me] = if install != "" { install } else { text(links_now, "install") }
                    // (the desktop opens Slack's page in the system's browser, at any time)
                    (core.open_link)(sa_approve.get(me).unwrap_or(""))
                  }
                  (core.say)(@sf.t(if approve { "web-pages.slackApp.updatedApprove" } else { "web-pages.slackApp.updated" }))
                }
                Err(e) => (core.say)(error_text(e))
              }
            },
          )
        },
        tone=Primary,
        busy~,
        disabled=fn() { !dirty() },
      )
      |> ignore
    })
  })
}

///|
/// An app's look and permissions (app_fields', as nodes) in `k`: its heading; its avatar (pressed, a picture of the
/// person's own), its name, what it is for and its colour (following what was picked until set by hand, and back to it);
/// the avatars to start from (still.fail's buddies, the model makers); the permissions folded. `width`: how wide it is
/// drawn now; its tips in `tips`.
fn app_fields_node(
  k : @view.View,
  core : Core,
  d : SaDraft,
  sections : () -> Array[Json],
  width : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  @sf.app_buddies_ask(fn(done) { (core.call)("buddies", obj([]), done) })
  let all = fn() { @sf.app_buddies_now() + @sf.app_makers }
  let find = fn(id : String) { @signals.untracked(all).iter().find_first(fn(a) { a.id == id }) }
  let colour = fn(bg : String) {
    d.color.set(bg)
    d.hex_field.set(bg)
  }
  // an avatar drawn on `bg`: a mark at once, a buddy once its picture is read
  let draw = fn(a : @sf.AppAvatar, bg : String) {
    if a.mark != "" {
      d.reading.set(("", 0, ""))
      match @sf.app_avatar_icon(a, bg, 0, 0, FixedArray::make(0, b'\x00')) {
        Some(icon) => sa_icon_made(d, icon)
        None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
      }
    } else {
      d.reading.set((@sf.avatars_base() + "/avatars/" + a.id + ".webp", @sf.app_icon_px, bg))
    }
  }
  let pick = fn(a : @sf.AppAvatar) {
    d.picked.set(a.id)
    d.upload.set("")
    let bg = if d.colour_set.untracked() { d.color.untracked() } else { a.bg }
    colour(bg)
    draw(a, bg)
  }
  // the picture being read, its pixels drawn into the icon once they are here (or why they could not be)
  k.pick(fn() { d.reading.get() }, fn(r, rd) {
    let (src, px, bg) = rd
    guard src != "" else { return }
    let read = @ui.tree_image_pixels(r, src, px)
    let state = fn() {
      match read() {
        None => 0
        Some(PixelsRead(_, _, _)) => 1
        Some(_) => 2
      }
    }
    r.reacts(state, fn(s) {
      match (s, @signals.untracked(read)) {
        (1, Some(PixelsRead(w, h, pixels))) => {
          let own = d.upload.untracked() != ""
          d.reading.set(("", 0, ""))
          if own {
            let icon = @sf.app_own_icon(w, h, pixels)
            let edge = @pixels.edge_colour(@sf.app_icon_px, @sf.app_icon_px, icon.pixels())
            d.upload_bg.set(edge)
            sa_icon_made(d, icon)
            if !d.colour_set.untracked() {
              colour(edge)
            }
          } else {
            match find(d.picked.untracked()) {
              Some(a) =>
                match @sf.app_avatar_icon(a, bg, w, h, pixels) {
                  Some(icon) => sa_icon_made(d, icon)
                  None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
                }
              None => ()
            }
          }
        }
        (2, _) => {
          let own = d.upload.untracked() != ""
          sa_icon_failed(d, @sf.t(if own { "web-pages.slackApp.readImageFailed" } else { "web-pages.slackApp.drawFailed" }))
        }
        _ => ()
      }
    })
  })
  // a picture of their own, from the system's picker
  let upload = fn() {
    if d.asking {
      return
    }
    let asked = (core.pick_picture)(fn(bytes) {
      d.asking = false
      match bytes {
        Some(b) => {
          sa_icons_made.val += 1
          let own = "mem:desk-slack-icon/own/\{sa_icons_made.val}"
          @ui.add_image(own, b)
          d.upload.set(own)
          d.picked.set("")
          d.reading.set((own, @sf.app_own_px, ""))
        }
        None => ()
      }
    })
    d.asking = asked
    if !asked {
      sa_icon_failed(d, @sf.t("web-pages.slackApp.readImageFailed"))
    }
  }
  // (typed in its colour's field: set by hand, what was picked drawn on it)
  k.reacts(fn() { d.hex_field.text().trim(chars=" ").to_owned() }, fn(typed) {
    if typed != d.color.untracked() {
      d.color.set(typed)
      d.colour_set.set(true)
      if @sf.hex_color(typed) is Some(_) {
        match find(d.picked.untracked()) {
          Some(a) => draw(a, typed)
          None => ()
        }
      }
    }
  })
  let ground = fn() { @sf.hex_color(d.color.get()).unwrap_or(@sf.theme().p.neutral_bg) }
  // (what it says on the colour chosen: a near black or white, whichever reads on it; the muted grey on none)
  let ink = fn() {
    match @sf.hex_color(d.color.get()) {
      Some(v) => @ui.ink_on(v, [0x24272BFFL, 0xFFFFFFFFL])
      None => @sf.theme().p.muted
    }
  }
  // its heading (as the phone's look: 头像), over what has a ground: so a card's corner it begins in holds words
  @sf.card_lines_node(k, fn() { @sf.t("android-settings.slack.icon") })
  k.box(fn(l) {
    @sf.style_node(l, fn() { sa_look })
    // its avatar (appAvatar: 136, the settings' corner, on the neutral ground behind its colour): pressed, a picture
    let ab = l.box(fn(a) {
      @sf.style_node(a, fn() { sa_avatar }, in_row=true)
      a.ground(By(ground)).clips(Is(true)) |> ignore
      @sf.presses_node(a, upload)
      a.says(By(fn() { Some(@view.said(Button, label=@sf.t("web-pages.slackApp.upload"))) })) |> ignore
      a.pick(fn() { d.shown.get() }, fn(s, shown) {
        if shown != "" {
          s.box(fn(img) {
            img
            .over(Is(true))
            .image(Is(Some((shown, "", @sf.app_icon_px))))
            .image_covers(Is(true))
            .image_fades(Is(false))
            |> ignore
          })
          |> ignore
        } else {
          s.box(fn(e) {
            @sf.style_node(e, fn() { sa_avatar_empty })
            @sf.icon_node(e, "image-upload", sa_upload_icon, By(ink)) |> ignore
            @sf.words_node(e, fn() { @sf.t("web-pages.slackApp.keep") }, fn() { sa_avatar_words }).ink(By(ink)) |> ignore
          })
          |> ignore
        }
      })
    })
    @sf.tip_node(tips, ab, fn() { @sf.t("web-pages.slackApp.upload") }) |> ignore
    l.box(fn(m) {
      @sf.style_node(m, fn() { sa_look_main }, in_row=true)
      @sf.input_node(m, d.name_field, placeholder=@sf.t("web-pages.settings.workspace.name")) |> ignore
      @sf.input_node(m, d.desc_field, placeholder=@sf.t("web-pages.slackApp.descriptionPlaceholder")) |> ignore
      m.box(fn(c) {
        @sf.style_node(c, fn() { sa_colour })
        c.box(fn(w) {
          @sf.style_node(w, fn() { sa_swatch }, in_row=true)
          w.ground(By(ground)) |> ignore
        })
        |> ignore
        c.box(fn(h) {
          @sf.style_node(h, fn() { sa_hex }, in_row=true)
          @sf.input_node(h, d.hex_field, label=@sf.t("web-pages.slackApp.color")) |> ignore
        })
        |> ignore
        // what was picked's own colour, after one set by hand
        let recommended = fn() {
          match d.picked.get() {
            "" => d.upload_bg.get()
            id =>
              match all().iter().find_first(fn(a) { a.id == id }) {
                Some(a) => a.bg
                None => d.upload_bg.get()
              }
          }
        }
        c.show(fn() { d.colour_set.get() && recommended() != "" && recommended().to_lower() != d.color.get().to_lower() }, fn(r) {
          cd_text_button_node(r, fn() { @sf.t("web-pages.slackApp.recommended") }, fn() {
            let bg = @signals.untracked(recommended)
            d.colour_set.set(false)
            colour(bg)
            match find(d.picked.untracked()) {
              Some(a) => draw(a, bg)
              None => ()
            }
          })
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  sa_avatar_picker_node(k, d, all, width, pick, tips)
  sa_permissions_node(k, d, sections, tips)
}

///|
/// The avatars to start from (sa_avatar_picker's, as nodes) in `k`: 15 to a line in the room `width` says, fewer where
/// it is less, 6 apart, 16 over them, 10 under; each square, edged in the line (the one picked ringed in the ink, the
/// field's hover grey under the pointer), its picture or its maker's mark; named by its tip.
fn sa_avatar_picker_node(
  k : @view.View,
  d : SaDraft,
  all : () -> Array[@sf.AppAvatar],
  width : () -> Double,
  pick : (@sf.AppAvatar) -> Unit,
  tips : @sf.TipLayer,
) -> Unit {
  let side = fn() { (width() - sa_tile_gap * (sa_tile_columns - 1).to_double()) / sa_tile_columns.to_double() }
  k.box(fn(p) {
    @sf.style_node(p, fn() { sa_picker })
    p.box(fn(r) {
      @sf.style_node(r, fn() { sa_picker_row })
      r.wraps(Is(Some(sa_tile_gap))) |> ignore
      r.each(fn() { all().map(fn(a) { a.id }) }, fn(id) { id }, fn(t, id) {
        let id = id.untracked()
        guard @signals.untracked(all).iter().find_first(fn(a) { a.id == id }) is Some(a) else { return }
        let label = if a.label.has_prefix("android-") { @sf.t(a.label) } else { a.label }
        let tile = t.box(fn(b) {
          let on = fn() { d.picked.get() == a.id }
          // (its edge: picked, sa_tile_on's; under the pointer, sa_tile_lit's, its hovered{border_color=FieldHover})
          @sf.style_node(b, fn() { if on() { sa_tile_on } else if b.pointed() { sa_tile_lit } else { sa_tile } })
          b
          .width(By(fn() { Some(side()) }))
          .height(By(fn() { Some(side()) }))
          .ground(Is(@sf.hex_color(a.bg).unwrap_or(@sf.icon_fallback)))
          .clips(Is(true))
          .says(By(fn() { Some(@view.said(Button, label~, selected=on())) }))
          |> ignore
          @sf.presses_node(b, fn() { pick(a) })
          if a.mark != "" {
            b.pick(side, fn(m, w) {
              @sf.drawable_node(m, a.mark, w * sa_mark_share, tint?=if a.mono { Some(fn() { Some(sa_white) }) } else { None }) |> ignore
            })
          } else {
            b.box(fn(img) {
              img
              .over(Is(true))
              .scale(Is(sa_thumb_scale))
              .image(Is(Some((@sf.avatars_base() + "/avatars/" + a.id + ".thumb.webp", "", 256))))
              .image_covers(Is(true))
              |> ignore
            })
            |> ignore
          }
        })
        @sf.tip_node(tips, tile, fn() { label }) |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The permissions, folded (sa_permissions', as nodes) in `k`: how many are on of all; all turned on from its line
/// while some are off; open, each section its title and 全选 / 全不选 (the first group stays on), its groups three to a
/// line, each a box to tick and its name (需管理员 beside those only admins allow), what it allows on hover; the first a
/// tick without a box. Nothing while there are none.
fn sa_permissions_node(k : @view.View, d : SaDraft, sections : () -> Array[Json], tips : @sf.TipLayer) -> Unit {
  let every = fn() {
    let out : Array[String] = []
    for s in sections() {
      for g in items(Some(s), "groups") {
        out.push(text(Some(g), "id"))
      }
    }
    out
  }
  let on = fn() { every().filter(fn(g) { d.groups.get(g).unwrap_or(false) }).length() }
  k.show(fn() { every().length() > 0 }, fn(p) {
    p.box(fn(b) {
      @sf.style_node(b, fn() { sa_perms })
      b.box(fn(l) {
        @sf.style_node(l, fn() { sa_perms_line })
        let said = fn() { @sf.t("web-pages.slackApp.permissions", args=[("on", on().to_string()), ("all", every().length().to_string())]) }
        l.box(fn(s) {
          @sf.style_node(s, fn() { sa_perms_summary }, in_row=true)
          @sf.presses_node(s, fn() { d.perms.set(!d.perms.untracked()) })
          s.says(By(fn() { Some(@view.said(Button, label=said(), expanded=d.perms.get())) })) |> ignore
          @sf.icon_node(s, "chevron-right", cd_icon, By(fn() { @sf.theme().p.muted }), name_now=fn() {
            if d.perms.get() {
              "chevron-down"
            } else {
              "chevron-right"
            }
          })
          |> ignore
          @sf.words_node(s, said, fn() { sa_perms_said }) |> ignore
        })
        |> ignore
        l.show(fn() { on() < every().length() }, fn(a) {
          cd_text_button_node(a, fn() { @sf.t("web-pages.slackApp.allOn") }, fn() {
            for g in @signals.untracked(every) {
              d.groups[g] = true
            }
          })
        })
      })
      |> ignore
      b.show(fn() { d.perms.get() }, fn(o) {
        o.box(fn(ss) {
          @sf.style_node(ss, fn() { sa_perm_sections })
          ss.each(fn() { sections().mapi(fn(i, s) { (i, s) }) }, fn(x) { text(Some(x.1), "title") + "\u{1}" + x.0.to_string() }, fn(sec, x) {
            let sv = Some(@signals.untracked(fn() { x.get().1 }))
            let groups = items(sv, "groups")
            let all = fn() { groups.iter().all(fn(g) { d.groups.get(text(Some(g), "id")).unwrap_or(false) }) }
            sec.box(fn(s) {
              @sf.style_node(s, fn() { sa_perm_section })
              s.box(fn(h) {
                @sf.style_node(h, fn() { sa_perm_head })
                @sf.words_node(h, fn() { text(sv, "title") }, fn() { sa_perm_title }) |> ignore
                cd_text_button_node(h, fn() { @sf.t(if all() { "web-pages.settings.members.none" } else { "web-pages.settings.members.all" }) }, fn() {
                  let was = @signals.untracked(all)
                  for g in groups {
                    d.groups[text(Some(g), "id")] = flag(Some(g), "fixed") || !was
                  }
                })
              })
              |> ignore
              let mut i = 0
              while i < groups.length() {
                let row = groups[i:if i + 3 < groups.length() { i + 3 } else { groups.length() }].to_owned()
                s.box(fn(r) {
                  @sf.style_node(r, fn() { sa_perm_row })
                  for g in row {
                    sa_permission_node(r, d, Some(g), tips)
                  }
                  // (three to a line, a short line's room kept)
                  for _ in row.length()..<3 {
                    r.box(fn(e) { @sf.style_node(e, fn() { sa_perm_label }, in_row=true) }) |> ignore
                  }
                })
                |> ignore
                i = i + 3
              }
            })
            |> ignore
          })
        })
        |> ignore
      })
    })
    |> ignore
  })
}

///|
/// A group of permissions (sa_permission's, as nodes) in `r`: its box ticked (the first, always on: a tick without a
/// box), its name, 需管理员 beside one only admins allow, the pointer's ground on it; what it allows over it while it is
/// pointed at (the core's tip).
fn sa_permission_node(r : @view.View, d : SaDraft, g : Json?, tips : @sf.TipLayer) -> Unit {
  let id = text(g, "id")
  let item = r.box(fn(b) {
    @sf.style_node(b, fn() { sa_perm_item }, in_row=true)
    b.ground(By(fn() { if b.pointed() { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    if flag(g, "fixed") {
      @sf.icon_node(b, "check", cd_kind_icon, By(fn() { @sf.theme().p.accent })) |> ignore
    } else {
      @sf.check_node(b, fn() { d.groups.get(id).unwrap_or(false) }, fn(on) { d.groups[id] = on }, fn() { text(g, "label") })
    }
    b.box(fn(l) {
      @sf.style_node(l, fn() { sa_perm_label }, in_row=true)
      @sf.words_node(l, fn() { text(g, "label") }, fn() { sa_perm_words }) |> ignore
    })
    |> ignore
    if opt_text(g, "admin") is Some(_) {
      @sf.words_node(b, fn() { @sf.t("web-pages.slackApp.admin") }, fn() { sa_admin_words }) |> ignore
    }
  })
  @sf.tip_node(tips, item, fn() { text(g, "tip") }) |> ignore
}

///|
/// Words to press beside a row's (cd_text_button's, as a node) in `parent`: the meta's 13 underlined, muted, the
/// words' ink under the pointer; `press` done as they are pressed.
fn cd_text_button_node(parent : @view.View, label : () -> String, press : () -> Unit) -> Unit {
  parent.box(fn(b) {
    @sf.presses_node(b, press)
    b.says(By(fn() { Some(@view.said(Button, label=label())) })) |> ignore
    b.box(fn(w) {
      w
      .words_runs(By(fn() { [@ui.span(label(), underline=true)] }), look=@ui.style_words(cd_text_button_words))
      .ink(By(fn() { @ui.style_ink(if b.pointed() { cd_text_button_lit } else { cd_text_button_words }) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How wide a page `w` wide leaves its column (settings_page's desk_column, a page's width given).
fn sa_column(w : Double) -> Double {
  dmin(desk_column_most, dmin(w - 2.0 * desk_lane_in, desk_lane_most) - 2.0 * desk_column_in)
}

///|
/// An app's look and permissions (AppFields: the new connect's dialog's; app_fields_node the page's), by how often each is changed: its avatar and name up front, its
/// description and colour (following the avatar until set by hand, and back to it); the avatars to start from (still.
/// fail's buddies, the model makers); the permissions folded, by section, each named with what it allows on hover
/// (those only Slack's admins allow marked so; the first always on). `fresh`: a new app, which starts as the general
/// helper. `width`: how wide it is drawn.
fn app_fields(c : @ui.Ctx, core : Core, d : SaDraft, sections : Array[Json], fresh : Bool, width : Double) -> Unit {
  let t = @sf.theme()
  let all = @sf.app_buddies(c, fn(done) { (core.call)("buddies", obj([]), done) }) + @sf.app_makers
  let find = fn(id : String) { all.iter().find_first(fn(a) { a.id == id }) }
  let colour = fn(bg : String) {
    d.color.set(bg)
    d.hex_field.set(bg)
  }
  // an avatar drawn on `bg`: a mark at once, a buddy once its picture is read
  let draw = fn(a : @sf.AppAvatar, bg : String) {
    if a.mark != "" {
      d.reading.set(("", 0, ""))
      match @sf.app_avatar_icon(a, bg, 0, 0, FixedArray::make(0, b'\x00')) {
        Some(icon) => sa_icon_made(d, icon)
        None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
      }
    } else {
      d.reading.set((@sf.avatars_base() + "/avatars/" + a.id + ".webp", @sf.app_icon_px, bg))
    }
  }
  let pick = fn(a : @sf.AppAvatar) {
    d.picked.set(a.id)
    d.upload.set("")
    let bg = if d.colour_set.get() { d.color.get() } else { a.bg }
    colour(bg)
    draw(a, bg)
  }
  // a new app starts as the general helper (else the first avatar), on its colour
  if fresh && !d.started && all.length() > @sf.app_makers.length() {
    d.started = true
    pick(find("general-helper").unwrap_or(all[0]))
  }
  let (reading, reading_px, reading_bg) = d.reading.get()
  if reading != "" {
    match c.image_pixels(reading, reading_px) {
      PixelsComing => ()
      PixelsFailed => sa_icon_failed(d, @sf.t(if d.upload.get() != "" { "web-pages.slackApp.readImageFailed" } else { "web-pages.slackApp.drawFailed" }))
      PixelsRead(w, h, px) => {
        d.reading.set(("", 0, ""))
        if d.upload.get() != "" {
          let icon = @sf.app_own_icon(w, h, px)
          d.upload_bg.set(@pixels.edge_colour(@sf.app_icon_px, @sf.app_icon_px, icon.pixels()))
          sa_icon_made(d, icon)
          if !d.colour_set.get() {
            colour(d.upload_bg.get())
          }
        } else {
          match find(d.picked.get()) {
            Some(a) =>
              match @sf.app_avatar_icon(a, reading_bg, w, h, px) {
                Some(icon) => sa_icon_made(d, icon)
                None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
              }
            None => ()
          }
        }
      }
    }
  }
  // a picture of their own, from the system's picker
  let upload = fn() {
    if d.asking {
      return
    }
    let asked = (core.pick_picture)(fn(bytes) {
      d.asking = false
      match bytes {
        Some(b) => {
          sa_icons_made.val += 1
          let own = "mem:desk-slack-icon/own/\{sa_icons_made.val}"
          @ui.add_image(own, b)
          d.upload.set(own)
          d.picked.set("")
          d.reading.set((own, @sf.app_own_px, ""))
        }
        None => ()
      }
    })
    d.asking = asked
    if !asked {
      sa_icon_failed(d, @sf.t("web-pages.slackApp.readImageFailed"))
    }
  }
  // its heading (as the phone's look: 头像), over what has a ground: so a card's corner it begins in holds words, and
  // the avatar and the fields under it stand clear of it
  c.text(@sf.t("android-settings.slack.icon"), style=desk_strong) |> ignore
  c.box(style=sa_look, fn() {
    // its avatar (appAvatar: 136, the settings' corner, on the neutral ground behind its colour): pressed, a picture
    let aid = c.id(d.key + "/avatar")
    c.on_press(aid, fn() {
      upload()
    })
    let ground = match @sf.hex_color(d.color.get()) {
      Some(v) => v
      None => t.p.neutral_bg
    }
    // (what it says on the colour chosen: a near black or white, whichever reads on it; the muted grey on none)
    let ink = match @sf.hex_color(d.color.get()) {
      Some(v) => @ui.ink_on(v, [0x24272BFFL, 0xFFFFFFFFL])
      None => t.p.muted
    }
    let ab = c.box(style=sa_avatar.then(@ui.style(bg=Data(ground))), id=aid, fn() {
      if d.shown.get() != "" {
        c.image(d.shown.get(), w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L, fade=false) |> ignore
      } else {
        c.box(style=sa_avatar_empty, fn() {
          @sf.icon(c, "image-upload", size=sa_upload_icon, color=ink) |> ignore
          c.text(
            @sf.t(if fresh { "web-pages.slackApp.uploadShort" } else { "web-pages.slackApp.keep" }),
            style=sa_avatar_words.then(@ui.text_style(color=Data(ink))),
          )
          |> ignore
        })
        |> ignore
      }
    })
    c.semantics(ab, Button, id=aid, label=@sf.t("web-pages.slackApp.upload"))
    @sf.tip(c, d.key + "/avatar-tip", aid, @sf.t("web-pages.slackApp.upload"))
    c.box(style=sa_look_main, fn() {
      // (what is typed is its field's: the draft's name and what it is for, sa_settings)
      @sf.input(c, d.key + "/name", placeholder=@sf.t("web-pages.settings.workspace.name"), field=d.name_field) |> ignore
      @sf.input(c, d.key + "/desc", placeholder=@sf.t("web-pages.slackApp.descriptionPlaceholder"), field=d.desc_field) |> ignore
      c.box(style=sa_colour, fn() {
        c.box(style=sa_swatch.then(@ui.style(bg=Data(ground))), fn() {  }) |> ignore
        c.box(style=sa_hex, fn() {
          let typed = @sf.input(c, d.key + "/hex", field=d.hex_field).text.trim(chars=" ").to_owned()
          // typed in its field: set by hand
          if typed != d.color.get() {
            d.color.set(typed)
            d.colour_set.set(true)
            if @sf.hex_color(typed) is Some(_) {
              match find(d.picked.get()) {
                Some(a) => draw(a, typed)
                None => ()
              }
            }
          }
        })
        |> ignore
        // what was picked's own colour, after one set by hand
        let recommended = match find(d.picked.get()) {
          Some(a) => a.bg
          None => d.upload_bg.get()
        }
        if d.colour_set.get() && recommended != "" && recommended.to_lower() != d.color.get().to_lower() {
          cd_text_button(c, d.key + "/recommended", @sf.t("web-pages.slackApp.recommended"), on_press=fn() {
            d.colour_set.set(false)
            colour(recommended)
            match find(d.picked.get()) {
              Some(a) => draw(a, recommended)
              None => ()
            }
          })
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  sa_avatar_picker(c, d, all, width, pick)
  sa_permissions(c, d, sections)
}

///|
/// The avatars to start from (avatarPicker: 15 to a line, fewer where the room is less, 6 apart, 16 over them, 10
/// under; avatarTile: square, edged in the line, a corner of 9, its picture 1.18 times it, a maker's mark in white
/// where it is drawn in one colour; the one picked ringed in the ink), each named by its tip.
fn sa_avatar_picker(c : @ui.Ctx, d : SaDraft, all : Array[@sf.AppAvatar], width : Double, pick : (@sf.AppAvatar) -> Unit) -> Unit {
  let gap = sa_tile_gap
  let side = (width - gap * (sa_tile_columns - 1).to_double()) / sa_tile_columns.to_double()
  // (as many to a line as the room takes, 15 where it is as wide as a dialog's: on a phone's sheet a line of 15 ran
  // past its edge)
  c.box(style=sa_picker, fn() {
    c.box(style=sa_picker_row, flow=true, line_gap=gap, fn() {
      for a in all {
        let tid = c.id(d.key + "/avatar/" + a.id)
        c.on_press(tid, fn() {
          pick(a)
        })
        let ground = @sf.hex_color(a.bg).unwrap_or(@sf.icon_fallback)
        let on = d.picked.get() == a.id
        let tb = c.box(
          style=(if on { sa_tile_on } else { sa_tile }).then(@ui.style(w=Fixed(side), h=Fixed(side), bg=Data(ground))),
          id=tid,
          fn() {
            if a.mark != "" {
              @sf.drawable(c, a.mark, side * sa_mark_share, tint?=if a.mono { Some(sa_white) } else { None }) |> ignore
            } else {
              let thumb = c.image(@sf.avatars_base() + "/avatars/" + a.id + ".thumb.webp", w=Fill(1.0), h=Fill(1.0), fit=FitCover, bg=0L)
              c.look(thumb, @ui.look(scale=sa_thumb_scale))
            }
          },
        )
        let label = if a.label.has_prefix("android-") { @sf.t(a.label) } else { a.label }
        c.semantics(tb, Button, id=tid, label~, selected=on)
        @sf.tip(c, d.key + "/avatar-tip/" + a.id, tid, label)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The permissions, folded (appPerms): how many are on of all; all turned on from its line while some are off; open,
/// each section its title and 全选 / 全不选 (the first group stays on), its groups three to a line, each a box to tick
/// and its name (需管理员 beside those only admins allow), what it allows on hover; the first a tick without a box.
fn sa_permissions(c : @ui.Ctx, d : SaDraft, sections : Array[Json]) -> Unit {
  let t = @sf.theme()
  let every : Array[String] = []
  for s in sections {
    for g in items(Some(s), "groups") {
      every.push(text(Some(g), "id"))
    }
  }
  if every.length() == 0 {
    return
  }
  let on = every.filter(fn(g) { d.groups.get(g).unwrap_or(false) }).length()
  c.box(style=sa_perms, fn() {
    c.box(style=sa_perms_line, fn() {
      let pid = c.id(d.key + "/perms")
      c.on_press(pid, fn() {
        d.perms.set(!d.perms.get())
      })
      let said = @sf.t("web-pages.slackApp.permissions", args=[("on", on.to_string()), ("all", every.length().to_string())])
      let pb = c.box(style=sa_perms_summary, id=pid, fn() {
        @sf.icon(c, if d.perms.get() { "chevron-down" } else { "chevron-right" }, size=cd_icon, color=t.p.muted) |> ignore
        c.text(said, style=sa_perms_said) |> ignore
      })
      c.semantics(pb, Button, id=pid, label=said, expanded=d.perms.get())
      if on < every.length() {
        cd_text_button(c, d.key + "/perms-all", @sf.t("web-pages.slackApp.allOn"), on_press=fn() {
          for g in every {
            d.groups[g] = true
          }
        })
      }
    })
    |> ignore
    if !d.perms.get() {
      return
    }
    c.box(style=sa_perm_sections, fn() {
      for s in sections {
        let sv = Some(s)
        let groups = items(sv, "groups")
        let all = groups.iter().all(fn(g) { d.groups.get(text(Some(g), "id")).unwrap_or(false) })
        c.box(style=sa_perm_section, fn() {
          c.box(style=sa_perm_head, fn() {
            c.text(text(sv, "title"), style=sa_perm_title) |> ignore
            cd_text_button(c, d.key + "/perm-section/" + text(sv, "title"), @sf.t(if all { "web-pages.settings.members.none" } else { "web-pages.settings.members.all" }), on_press=fn() {
              for g in groups {
                let id = text(Some(g), "id")
                d.groups[id] = flag(Some(g), "fixed") || !all
              }
            })
          })
          |> ignore
          let mut i = 0
          while i < groups.length() {
            let row = groups[i:if i + 3 < groups.length() { i + 3 } else { groups.length() }].to_owned()
            c.box(style=sa_perm_row, fn() {
              for g in row {
                sa_permission(c, d, Some(g))
              }
              // (three to a line, a short line's room kept)
              for _ in row.length()..<3 {
                c.box(style=sa_perm_label, fn() {  }) |> ignore
              }
            })
            |> ignore
            i = i + 3
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A group of permissions: its box ticked (the first, always on: a tick without a box), its name, 需管理员 beside one
/// only admins allow; what it allows on hover (the core's tip).
fn sa_permission(c : @ui.Ctx, d : SaDraft, g : Json?) -> Unit {
  let t = @sf.theme()
  let id = text(g, "id")
  let iid = c.id(d.key + "/perm/" + id)
  c.box(style=sa_perm_item, id=iid, fn() {
    if flag(g, "fixed") {
      @sf.icon(c, "check", size=cd_kind_icon, color=t.p.accent) |> ignore
    } else {
      let now = @kit.checkbox(c, d.key + "/perm-box/" + id, if d.groups.get(id).unwrap_or(false) { On } else { Off }, label=text(
          g, "label",
        ))
      if now.response.changed {
        d.groups[id] = now.value == On
      }
    }
    c.box(style=sa_perm_label, fn() { c.text(text(g, "label"), style=sa_perm_words) |> ignore }) |> ignore
    if opt_text(g, "admin") is Some(_) {
      c.text(@sf.t("web-pages.slackApp.admin"), style=sa_admin_words) |> ignore
    }
  })
  |> ignore
  @sf.tip(c, d.key + "/perm-tip/" + id, iid, text(g, "tip"))
}

///|
/// An icon made: shown in the look, and kept as it goes to Slack.
fn sa_icon_made(d : SaDraft, icon : @pixels.Canvas) -> Unit {
  let (jpeg, url) = @sf.app_icon_jpeg(icon)
  sa_icons_made.val += 1
  let shown = "mem:desk-slack-icon/\{sa_icons_made.val}"
  @ui.add_image(shown, jpeg)
  d.shown.set(shown)
  d.icon.set(url)
  d.icon_error.set("")
}

///|
/// An icon that could not be made: why.
fn sa_icon_failed(d : SaDraft, words : String) -> Unit {
  d.reading.set(("", 0, ""))
  d.icon.set("")
  d.icon_error.set(words)
}

///|
/// The sizes: the avatar 136 (its upload mark 20), the avatars 15 to a line 6 apart (a mark 55% of its tile, a
/// buddy's picture 1.18 times it), the card's padding 20.
let sa_upload_icon : Double = 20.0

///|
let sa_tile_columns : Int = 15

///|
let sa_tile_gap : Double = 6.0

///|
let sa_mark_share : Double = 0.55

///|
let sa_thumb_scale : Double = 1.18

///|
let sa_card_in : Double = 20.0

///|
let sa_white : Int64 = 0xFFFFFFFFL

///|
/// The guide (tokenGuide: its steps 18 apart).
// kept across runs: a value (no field of it changes)
let sa_guide : @ui.Style = @ui.css("w=Full gap=S4_5")

///|
// kept across runs: a value (no field of it changes)
let sa_step : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let sa_step_number : @ui.Style = @ui.css("w=S6 h=S6 radius=Full bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sa_step_number_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sa_step_body : @ui.Style = @ui.style(w=@sf.grow, gap=S1, align=AStart)

///|
/// The token's line (inputRow: the field as wide as is left, its button after it, 8 apart, 6 under the words).
// kept across runs: a value (no field of it changes)
let sa_input_row : @ui.Style = @ui.css("row w=Full pt=S1_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_input_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Slack asking for approval (callout blue: 12 by 14 in, 10 apart, a corner of 14, in the blue's ink).
// kept across runs: a value (no field of it changes)
let sa_blue : @ui.Style = @ui.css("row w=Full px=S3_5 py=S3 gap=S2_5 radius=Xl1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_blue_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
/// Its look (appLook: the avatar 136 and the rest, 16 apart; appLookMain: 8 apart; appColour: 8 apart, the swatch 28,
/// the hex field 96).
// kept across runs: a value (no field of it changes)
let sa_look : @ui.Style = @ui.css("row w=Full gap=S4 align=AStretch")

///|
// kept across runs: a value (no field of it changes)
let sa_avatar : @ui.Style = @ui.css("w=S32 h=S32 radius=Xl3 clip border=B1 border_color=Line align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sa_avatar_empty : @ui.Style = @ui.css("gap=S1 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let sa_look_main : @ui.Style = @ui.style(w=@sf.grow, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let sa_colour : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_swatch : @ui.Style = @ui.css("w=S7 h=S7 radius=Lg border=B1 border_color=Border")

///|
// kept across runs: a value (no field of it changes)
let sa_hex : @ui.Style = @ui.css("w=S24")

///|
// kept across runs: a value (no field of it changes)
let sa_picker : @ui.Style = @ui.css("w=Full pt=S4 pb=S2_5 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sa_picker_row : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sa_tile : @ui.Style = @ui.css("radius=Lg clip border=B1 border_color=Line align=ACenter justify=JCenter hovered{border_color=FieldHover}")

///|
/// A tile under the pointer (sa_tile's hovered, as a node takes it).
// kept across runs: a value (no field of it changes)
let sa_tile_lit : @ui.Style = sa_tile.then(@ui.css("border_color=FieldHover"))

///|
// kept across runs: a value (no field of it changes)
let sa_tile_on : @ui.Style = sa_tile.then(@ui.css("border=B2 border_color=Fg"))

///|
/// What the avatar says while it has no picture (keep, upload: a note's words, in what reads on its colour), and 需管理员
/// beside a group only admins allow (a note's words): the dialog's look and the page's alike.
// kept across runs: a value (no field of it changes)
let sa_avatar_words : @ui.TextStyle = desk_note

///|
// kept across runs: a value (no field of it changes)
let sa_admin_words : @ui.TextStyle = desk_note

///|
/// The permissions (appPerms: the ui's 13; its line muted, 6 down; permSections 4 apart, 8 under it; a section's head
/// its title (h4) and its toggle; permGrid three to a line, 8 apart).
// kept across runs: a value (no field of it changes)
let sa_perms : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let sa_perms_line : @ui.Style = @ui.css("row w=Full py=S1_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_perms_summary : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_perm_sections : @ui.Style = @ui.css("w=Full pt=S2 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let sa_perm_section : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let sa_perm_head : @ui.Style = @ui.css("row w=Full pt=S2 gap=S2 align=ACenter justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let sa_perm_title : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sa_perm_row : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A group (modelPoolItem: a third of the line, 32 high, 8 by 6 in, 8 apart, the pointer's ground on it).
// kept across runs: a value (no field of it changes)
let sa_perm_item : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("row h=S8 px=S2 gap=S2 radius=Lg align=ACenter hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let sa_perm_label : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sa_perm_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false)

///|
/// What a fold's line says beside its title (the ui's 13 muted, in a line).
// kept across runs: a value (no field of it changes)
let sa_perms_said : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)
