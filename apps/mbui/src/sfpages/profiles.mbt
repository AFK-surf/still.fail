// Profile (web ProfilesNav.tsx; mobile Profiles.tsx; the core's `profiles` topic): the workspace's profiles, one list
// wherever it stands, drawn as it stands there: in a side column beside the profile picked (the shell's sidebar) a
// section a kind of account, a row an account (its maker's mark, its name, how it is where that is not simply fine,
// what is left of its allowance or where it is and who uses it), then each station's own logins not made profiles yet;
// across the whole page (its page of its own: a small screen's, or from settings, a station's alone) as the settings
// draw them there (their profiles_blocks: a section a kind, a card an account, its allowance, the machine's logins).

///|
/// The profiles' rows in a side column (ProfilesNav): the one `picked` chosen (its page beside the list), `pick` as one
/// is pressed; a station's own login not a profile yet offered (`offer`: a new profile there).
pub fn profiles_rows(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  picked : @settings.Route?,
  pick : (@settings.Route) -> Unit,
  offer : (String) -> Unit,
) -> Unit {
  let list = items((src.topic)("profiles", { "scope": Json::string(w.id) }).value, "items")
  let mut group = ""
  for i, e in list {
    let e = Some(e)
    // (another row under it: the next of its group)
    let more = i + 1 < list.length() && text(Some(list[i + 1]), "group") == text(e, "group")
    if text(e, "group") != group {
      group = text(e, "group")
      @sf.list_heading(c, text(e, "groupTitle"), Side)
    }
    let p = field(e, "profile")
    let route = @settings.Route::Profile(text(e, "station"), text(field(e, "profile"), "id"))
    let usable = flag(e, "usable")
    // how it is where that is not simply fine, as the core says it, in its tone (ProfilesNav.tsx ProfileRow): what
    // needs a look in colour
    let trouble = text(field(e, "state"), "text")
    let tone = text(field(e, "state"), "tone")
    // where it is and who uses it
    let used = items(p, "usedBy").length()
    let facts = [
      text(e, "where"),
      if used > 0 {
        @sf.t("web-pages.settings.profiles.usedBy", args=[("n", used.to_string())])
      } else {
        ""
      },
    ].filter(fn(x) { x != "" })
    let facts = facts.join(" · ")
    if @sf.nav_item(
        c,
        "profiles/" + text(e, "key"),
        picked == Some(route),
        fn() { @sf.maker_mark(c, text(p, "providerMark"), text(p, "runtime"), @sf.nav_mark_side) |> ignore },
        fn() { @sf.nav_title(c, text(p, "name"), away=!usable) },
        lines=fn() {
          @sf.list_row_line(c, fn() {
            if trouble != "" {
              c.text(trouble, style=@sf.nav_meta().then(pr_trouble_ink(tone))) |> ignore
            }
            // what is left of its allowance has the line to itself (a key's balance where its provider says
            // one); else where it is and who uses it, cut where the row runs out
            let quota = field(p, "quota")
            let ok = text(quota, "state") == "ok"
            if ok && items(quota, "windows").length() > 0 {
              @sf.quota_chips(c, quota, small=true, gap=4.0, key="profiles/" + text(e, "key"))
            } else if ok && text(quota, "creditsText") != "" {
              c.text(text(quota, "creditsText"), style=@sf.nav_meta()) |> ignore
            } else {
              if trouble != "" && facts != "" {
                c.text("·", style=@sf.nav_meta()) |> ignore
              }
              c.text(facts, style=@sf.nav_meta().then(pr_fill)) |> ignore
            }
          })
        },
        more~,
      ) {
      pick(route)
    }
  }
  // each station's own logins, not profiles yet
  for s in stations_listed(src, w).unwrap_or([]) {
    let s = Some(s)
    if !flag(s, "online") {
      continue
    }
    let station = text(s, "station")
    let offers = items(field(s, "overview"), "machineLogins").filter(fn(l) {
      flag(Some(l), "offered") && text(field(Some(l), "quota"), "state") != "blocked"
    })
    if offers.length() == 0 {
      continue
    }
    @sf.list_heading(c, @sf.t("web-pages.profiles.machineSignedIn", args=[("station", text(s, "name"))]), Side)
    for j, l in offers {
      let l = Some(l)
      if @sf.nav_item(
          c,
          "profiles/machine/" + station + "/" + text(l, "runtime"),
          false,
          fn() { @sf.maker_mark(c, "", text(l, "runtime"), @sf.nav_mark_side) |> ignore },
          fn() { @sf.nav_title(c, @settings.runtime_label(text(l, "runtime"))) },
          lines=fn() {
            @sf.list_row_line(c, fn() {
              c.box(style=pr_grow, fn() { c.text(text(l, "email"), style=@sf.nav_meta()) |> ignore }) |> ignore
              c.text(@sf.t("android-settings.machine.use"), style=@sf.nav_meta().then(pr_use)) |> ignore
            })
          },
          more=j + 1 < offers.length(),
        ) {
        offer(station)
      }
    }
  }
}

///|
/// Profile as a page of its own (a small screen's: the bar's place; from settings; a station's, `only`): what the
/// settings draw across a page, 添加 Profile at its title's end where the frame does not hold it (a phone's bar's
/// notch).
pub fn profiles_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, only : String) -> Unit {
  let add = @settings.place_action(core, here, "profiles")
  @sf.page(
    c,
    on_back=core.pop,
    frame~,
    "profiles/" + only,
    @sf.t("android-misc.bar.place.profiles"),
    @settings.profiles_blocks(c, core, here, only),
    listed=true,
    // (a place's top page under a phone's bar: its ＋ the bar's notch)
    actions?=match add {
      Some(run) if !frame.named =>
        Some(fn() {
          if @sf.icon_button(c, "plus", key="profiles/add", round=true, label=@sf.t("web-pages.settings.profiles.add")) {
            run(Of(c.id("profiles/add")))
          }
        })
      _ => None
    },
  )
}

///|
/// What is wrong, in its tone (ProfilesNav.css.ts trouble): amber, red, or muted (neutral).
fn pr_trouble_ink(tone : String) -> @ui.TextStyle {
  match tone {
    "red" => pr_trouble_red
    "neutral" => pr_trouble_neutral
    _ => pr_trouble_amber
  }
}

///|
// kept across runs: a value (no field of it changes)
let pr_trouble_red : @ui.TextStyle = @ui.text_style(color=Danger)

///|
// kept across runs: a value (no field of it changes)
let pr_trouble_amber : @ui.TextStyle = @ui.text_style(color=WarnInk)

///|
// kept across runs: a value (no field of it changes)
let pr_trouble_neutral : @ui.TextStyle = @ui.text_style(color=Muted)

///|
/// The words that give way first (SidebarList.css.ts fill).
// kept across runs: a value (no field of it changes)
let pr_fill : @ui.TextStyle = @ui.text_style(w=Cut)

///|
/// 使用此账号 (ProfilesNav MachineLoginRow): the accent's words.
// kept across runs: a value (no field of it changes)
let pr_use : @ui.TextStyle = @ui.text_style(color=AccentText)

///|
// kept across runs: a value (no field of it changes)
let pr_grow : @ui.Style = @ui.style(w=@sf.grow, clip=true)
