// A connect's Slack app on the desktop (ember web/src/pages/SlackApp.tsx SlackAppSection, ConfigTokenForm, AppFields,
// AppForm; SlackApp.css.ts): folded on its page (it is changed now and then), its look and permissions edited here and
// written into the app's manifest with the viewer's configuration token (`connect.putSlackApp`, given what the form
// started from: the core writes only what differs); without one, a way to add it. The permissions' sections are the
// core's (the slackApp topic's and the connect wizard's `sections`); the icon is drawn by the library (app_icon.mbt).

///|
/// A Slack app's look and permissions being edited (AppFields' settings, and what its look keeps): what is typed and
/// picked, the icon made (a data URL, "" none) and why it could not be, and how the icon is coming along.
priv struct SaDraft {
  key : String
  name : @signals.Signal[String]
  description : @signals.Signal[String]
  color : @signals.Signal[String]
  groups : Map[String, Bool]
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
  /// the picture being read to draw from: its source and how large, on what colour ("" none)
  reading : @signals.Signal[String]
  reading_px : @signals.Signal[Int]
  reading_bg : @signals.Signal[String]
  asking : @signals.Signal[Bool]
  started : @signals.Signal[Bool]
  /// the permissions unfolded
  perms : @signals.Signal[Bool]
  name_field : @ui.Field
  desc_field : @ui.Field
  hex_field : @ui.Field
}

///|
/// A draft of `settings` (a Slack app's, as the core has them), its fields filled with them.
fn sa_draft(key : String, settings : Json?) -> SaDraft {
  let groups : Map[String, Bool] = {}
  match field(settings, "groups") {
    Some(Object(m)) =>
      for g, v in m {
        groups[g] = v == Json::boolean(true)
      }
    _ => ()
  }
  {
    key,
    name: @signals.signal(text(settings, "name"), same=fn(a, b) { a == b }),
    description: @signals.signal(text(settings, "description"), same=fn(a, b) { a == b }),
    color: @signals.signal(text(settings, "backgroundColor"), same=fn(a, b) { a == b }),
    groups,
    icon: @signals.signal(""),
    icon_error: @signals.signal(""),
    shown: @signals.signal("", same=fn(a, b) { a == b }),
    picked: @signals.signal("", same=fn(a, b) { a == b }),
    upload: @signals.signal("", same=fn(a, b) { a == b }),
    upload_bg: @signals.signal("", same=fn(a, b) { a == b }),
    colour_set: @signals.signal(false, same=fn(a, b) { a == b }),
    reading: @signals.signal("", same=fn(a, b) { a == b }),
    reading_px: @signals.signal(0, same=fn(a, b) { a == b }),
    reading_bg: @signals.signal("", same=fn(a, b) { a == b }),
    asking: @signals.signal(false, same=fn(a, b) { a == b }),
    started: @signals.signal(false, same=fn(a, b) { a == b }),
    perms: @signals.signal(false, same=fn(a, b) { a == b }),
    name_field: @ui.Field::new(text=text(settings, "name")),
    desc_field: @ui.Field::new(text=text(settings, "description")),
    hex_field: @ui.Field::new(text=text(settings, "backgroundColor")),
  }
}

///|
/// What the draft says of the app, as the core takes its settings (the name in messages its name too).
fn sa_settings(d : SaDraft, settings : Json?) -> Json {
  let groups : Map[String, Json] = {}
  for g, v in d.groups {
    groups[g] = Json::boolean(v)
  }
  obj([
    ("name", str(d.name.get())),
    ("displayName", str(d.name.get())),
    ("description", str(d.description.get())),
    ("longDescription", str(text(settings, "longDescription"))),
    ("backgroundColor", str(d.color.get())),
    ("groups", Json::object(groups)),
  ])
}

///|
/// The drafts, by their form; the folds open, by station/connect; icons made, each its own picture's key.
// kept across runs: made as each form is first drawn; slack_app_reset empties it
let sa_drafts : Map[String, SaDraft] = {}

///|
// kept across runs: said by the fold's press; slack_app_reset empties it
let sa_open : Map[String, Bool] = {}

///|
/// What a form started from (its settings as text), by its key: a change there starts it again.
// kept across runs: said as each form is drawn; slack_app_reset empties it
let sa_started : Map[String, String] = {}

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
/// The connect's Slack app, folded (SlackAppSection): its title and what it is for in the fold's line; open, the app as
/// Slack has it (read through the station: being read, none, no configuration token to write it with, or why it could
/// not be read), its form, and Slack's page of it.
fn slack_app_section(c : @ui.Ctx, core : Core, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let me = station + "/" + id
  let open = sa_open.get(me).unwrap_or(false)
  // folded: a row of its own that opens it; open, what it holds on a card under it, apart from what follows
  @sf.apart(c, fn() { slack_app_fold(c, core, station, id, me, open) })
}

///|
/// The Slack app's fold: its row, and open, what it holds.
fn slack_app_fold(c : @ui.Ctx, core : Core, station : String, id : String, me : String, open : Bool) -> Unit {
  @sf.group(c, fn() {
    if @sf.link_row(
        c,
        "slack-app-fold/" + me,
        "Slack app",
        note=@sf.t("web-pages.slackApp.foldNote"),
        value=if open { @sf.t("web-pages.profiles.collapse") } else { "" },
        chevron=!open,
      ) {
      sa_open[me] = !open
    }
  })
  if !open {
    return
  }
  let topic = (core.topic)("slackApp", { "station": str(station), "connect": str(id) })
  let view = topic.value
  let links = field(view, "links")
  match (topic.error, view) {
    (Some(e), _) => @sf.page_note(c, error_text(e), bad=true)
    (_, None) => @sf.page_note(c, @sf.t("web-pages.slackApp.loading"))
    (_, Some(_)) =>
      match text(view, "state") {
        "no_app" =>
          @sf.page_note(c, match opt_text(view, "error") {
            Some(e) => @sf.t("web-pages.slackApp.noApp", args=[("error", e)])
            None => @sf.t("web-pages.slackApp.notConnected")
          })
        "no_config_token" =>
          sa_token_card(c, core, station, me, @sf.t("web-pages.slackApp.needsToken"), @sf.t("web-pages.slackApp.needsTokenNote"), @sf.t(
              "web-pages.slackApp.addToken",
            ), false)
        "error" =>
          sa_token_card(c, core, station, me, @sf.t("web-pages.slackApp.readFailed", args=[("error", text(view, "error"))]), "", @sf.t(
              "web-pages.slackApp.replaceToken",
            ), true)
        _ => sa_form(c, core, station, id, field(view, "settings"), links, items(view, "sections"))
      }
  }
  match opt_text(links, "settings") {
    Some(url) if url != "" =>
      @sf.group(c, fn() {
        if @sf.link_row(c, "slack-app-open/" + me, @sf.t("web-pages.slackApp.openInSlack"), out=true) {
          (core.open_link)(url)
        }
      })
    _ => ()
  }
}

///|
/// A card saying the app wants a configuration token (none, or one Slack refused: `bad`), and the button that adds one
/// (in a dialog: ConfigTokenForm).
fn sa_token_card(c : @ui.Ctx, core : Core, station : String, me : String, words : String, note : String, action : String, bad : Bool) -> Unit {
  @sf.page_card(c, footed=true, fn() {
    @sf.card_lines(c, "", words=if bad { "" } else { words }, note~, bad=if bad { words } else { "" })
    @sf.card_foot(c, fn() {
      if @sf.button(c, action, key="slack-app-token/" + me) {
        config_token_dialog(core, station)
      }
    })
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
let sa_token_errors : Map[String, String] = {}

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
      if @sf.button(c, @sf.t("web-pages.slackApp.openApps"), key=key + "/apps", tone=Primary, icon="external") {
        (core.open_link)("https://api.slack.com/apps")
      }
    })
    sa_guide_step(c, 2, @sf.t("web-pages.slackApp.step2"), @sf.t("web-pages.slackApp.step2Note"), fn() {  })
    sa_guide_step(c, 3, @sf.t("web-pages.slackApp.step3"), @sf.t("web-pages.slackApp.step3Note", args=[("name", "still.fail")]), fn() {
      c.box(style=sa_input_row, fn() {
        c.box(style=sa_input_grow, fn() { @sf.input(c, key + "/token-input", placeholder="xoxe-1-…", secret=true, field=tf) |> ignore })
        |> ignore
        if @sf.button(
            c,
            @sf.t(if replacing { "web-pages.slackApp.useThis" } else { "web-pages.slackApp.add" }),
            key=key + "/add",
            tone=Primary,
            busy~,
            disabled=!ready,
          ) {
          add()
        }
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
/// The app's form (AppForm, a card): Slack asking for changed permissions to be approved (its page opened from it);
/// its look and permissions; why its icon could not be made; 还原 while changed, 应用 writing what changed (the core
/// compares it with what the form started from). Started again when Slack's settings change.
fn sa_form(c : @ui.Ctx, core : Core, station : String, id : String, settings : Json?, links : Json?, sections : Array[Json]) -> Unit {
  let me = station + "/" + id
  let key = "slack-app/" + me
  let start = match settings {
    Some(s) => s.stringify()
    None => ""
  }
  let d = match sa_drafts.get(key) {
    Some(d) if sa_started.get(key) == Some(start) => d
    _ => {
      let d = sa_draft(key, settings)
      sa_drafts[key] = d
      sa_started[key] = start
      d
    }
  }
  let busy = is_doing(core, ["connect.putSlackApp"], [("station", station), ("connect", id)])
  @sf.page_card(c, footed=true, fn() {
    match sa_approve.get(me) {
      Some(install) =>
        c.box(style=sa_blue.then(@ui.style(bg=Data(@sf.theme().p.blue_bg))), fn() {
          @sf.icon(c, "shield-check", size=cd_icon, color=@sf.theme().p.blue) |> ignore
          c.box(style=cd_effect_words, fn() { c.text(@sf.t("web-pages.slackApp.approveNote"), style=sa_blue_words) |> ignore })
          |> ignore
          if @sf.button(c, @sf.t("web-pages.slackApp.approve"), key=key + "/approve", tone=Primary) {
            sa_approve.remove(me)
            (core.open_link)(install)
          }
        })
        |> ignore
      None => ()
    }
    app_fields(c, core, d, sections, false, desk_column(c) - 2.0 * sa_card_in)
    if d.icon_error.get() != "" {
      @sf.card_lines(c, "", bad=d.icon_error.get())
    }
    let now = sa_settings(d, settings)
    let changed = now != sa_settings(sa_draft(key, settings), settings)
    let dirty = changed || d.icon.get() != ""
    @sf.card_foot(c, at_end=true, fn() {
      if dirty && @sf.button(c, @sf.t("web-pages.slackApp.revert"), key=key + "/revert", tone=Ghost) {
        sa_drafts.remove(key)
      }
      if @sf.button(c, @sf.t("web-pages.slackApp.apply"), key=key + "/apply", tone=Primary, busy~, disabled=!dirty) {
        let input = match now {
          Object(m) => {
            let m2 = Map::from_iter(m.iter())
            if d.icon.get() != "" {
              m2["icon"] = str(d.icon.get())
            }
            Json::object(m2)
          }
          other => other
        }
        (core.call)(
          "connect.putSlackApp",
          obj([("station", str(station)), ("connect", str(id)), ("input", input), ("from", settings.unwrap_or(Json::null()))]),
          fn(r) {
            match r {
              Ok(v) => {
                let rv = Some(v)
                let approve = flag(rv, "permissionsUpdated")
                d.icon.set("")
                d.icon_error.set(opt_text(rv, "iconError").unwrap_or(""))
                let install = text(field(rv, "links"), "install")
                if approve {
                  sa_approve[me] = if install != "" { install } else { text(links, "install") }
                  // (the desktop opens Slack's page in the system's browser, at any time)
                  (core.open_link)(sa_approve.get(me).unwrap_or(""))
                }
                (core.say)(@sf.t(if approve { "web-pages.slackApp.updatedApprove" } else { "web-pages.slackApp.updated" }))
              }
              Err(e) => (core.say)(error_text(e))
            }
          },
        )
      }
    })
  })
}

///|
/// An app's look and permissions (AppFields), by how often each is changed: its avatar and name up front, its
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
      d.reading.set("")
      match @sf.app_avatar_icon(a, bg, 0, 0, FixedArray::make(0, b'\x00')) {
        Some(icon) => sa_icon_made(d, icon)
        None => sa_icon_failed(d, @sf.t("web-pages.slackApp.drawFailed"))
      }
    } else {
      d.reading.set(@sf.avatars_base() + "/avatars/" + a.id + ".webp")
      d.reading_px.set(@sf.app_icon_px)
      d.reading_bg.set(bg)
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
  if fresh && !d.started.get() && all.length() > @sf.app_makers.length() {
    d.started.set(true)
    pick(find("general-helper").unwrap_or(all[0]))
  }
  if d.reading.get() != "" {
    match c.image_pixels(d.reading.get(), d.reading_px.get()) {
      PixelsComing => ()
      PixelsFailed => sa_icon_failed(d, @sf.t(if d.upload.get() != "" { "web-pages.slackApp.readImageFailed" } else { "web-pages.slackApp.drawFailed" }))
      PixelsRead(w, h, px) => {
        d.reading.set("")
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
              match @sf.app_avatar_icon(a, d.reading_bg.get(), w, h, px) {
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
    if d.asking.get() {
      return
    }
    let asked = (core.pick_picture)(fn(bytes) {
      d.asking.set(false)
      match bytes {
        Some(b) => {
          sa_icons_made.val += 1
          d.upload.set("mem:desk-slack-icon/own/\{sa_icons_made.val}")
          @ui.add_image(d.upload.get(), b)
          d.picked.set("")
          d.reading.set(d.upload.get())
          d.reading_px.set(@sf.app_own_px)
        }
        None => ()
      }
    })
    d.asking.set(asked)
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
    if hit(c, aid) {
      upload()
    }
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
            style=desk_note.then(@ui.text_style(color=Data(ink))),
          )
          |> ignore
        })
        |> ignore
      }
    })
    c.semantics(ab, Button, id=aid, label=@sf.t("web-pages.slackApp.upload"))
    @sf.tip(c, d.key + "/avatar-tip", aid, @sf.t("web-pages.slackApp.upload"))
    c.box(style=sa_look_main, fn() {
      let name = @sf.input(c, d.key + "/name", placeholder=@sf.t("web-pages.settings.workspace.name"), field=d.name_field).text
      d.name.set(name)
      let desc = @sf.input(c, d.key + "/desc", placeholder=@sf.t("web-pages.slackApp.descriptionPlaceholder"), field=d.desc_field).text
      d.description.set(desc)
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
          if cd_text_button(c, d.key + "/recommended", @sf.t("web-pages.slackApp.recommended")) {
            d.colour_set.set(false)
            colour(recommended)
            match find(d.picked.get()) {
              Some(a) => draw(a, recommended)
              None => ()
            }
          }
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
        if hit(c, tid) {
          pick(a)
        }
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
      if hit(c, pid) {
        d.perms.set(!d.perms.get())
      }
      let said = @sf.t("web-pages.slackApp.permissions", args=[("on", on.to_string()), ("all", every.length().to_string())])
      let pb = c.box(style=sa_perms_summary, id=pid, fn() {
        @sf.icon(c, if d.perms.get() { "chevron-down" } else { "chevron-right" }, size=cd_icon, color=t.p.muted) |> ignore
        c.text(said, style=sa_perms_said) |> ignore
      })
      c.semantics(pb, Button, id=pid, label=said, expanded=d.perms.get())
      if on < every.length() && cd_text_button(c, d.key + "/perms-all", @sf.t("web-pages.slackApp.allOn")) {
        for g in every {
          d.groups[g] = true
        }
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
            if cd_text_button(c, d.key + "/perm-section/" + text(sv, "title"), @sf.t(if all { "web-pages.settings.members.none" } else { "web-pages.settings.members.all" })) {
              for g in groups {
                let id = text(Some(g), "id")
                d.groups[id] = flag(Some(g), "fixed") || !all
              }
            }
          })
          |> ignore
          let mut i = 0
          while i < groups.length() {
            let row = groups[i:if i + 3 < groups.length() { i + 3 } else { groups.length() }].to_array()
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
      c.text(@sf.t("web-pages.slackApp.admin"), style=desk_note) |> ignore
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
  d.shown.set("mem:desk-slack-icon/\{sa_icons_made.val}")
  @ui.add_image(d.shown.get(), jpeg)
  d.icon.set(url)
  d.icon_error.set("")
}

///|
/// An icon that could not be made: why.
fn sa_icon_failed(d : SaDraft, words : String) -> Unit {
  d.reading.set("")
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
/// The fold (appFold: 28 over and under it; its line 6 by 0 in, 10 apart, its title in 600; its body 8 under it, 10
/// apart).
// kept across runs: a value (no field of it changes)
let sa_fold : @ui.Style = @ui.css("w=Full py=S7")

///|
// kept across runs: a value (no field of it changes)
let sa_fold_line : @ui.Style = @ui.css("row py=S1_5 gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sa_fold_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sa_fold_body : @ui.Style = @ui.css("w=Full pt=S2 gap=S2_5")

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
// kept across runs: a value (no field of it changes)
let sa_tile_on : @ui.Style = sa_tile.then(@ui.css("border=B2 border_color=Fg"))

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
