// Station (web StationPage.tsx StationsNav, StationRow; mobile Stations.tsx; the core's `stations` topic): the
// workspace's stations, one list wherever it stands (`at`), drawn as it stands there: in a side column beside the
// page picked (the shell's sidebar) a row each, its mark, its name, at its end whether it is up (its agents at work, or
// when it was last seen), and while it is up what is left of its CPU, memory and disk and how this device reaches it
// (two lines, kept whatever it is, every row as high); across the whole page (its page of its own: a small screen's,
// or from settings) a card each, what the page is for being how they all are at a glance (the settings' station_card:
// its chip and agents at work, what of its load runs low, its network's speeds and totals, asleep offline). Pressed,
// its page. None in the workspace: the first to add.

///|
/// The workspace's stations, as the core lists them (None while they are read).
pub fn stations_listed(src : Source, w : Workspace) -> Array[Json]? {
  match (src.topic)("stations", { "scope": Json::string(w.id) }).value {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
/// The stations' lines standing `at`: a row each, the one `picked` chosen (its page beside the list), `pick` as one is
/// pressed; while they are read, the rows to come.
pub fn stations_lines(
  c : @ui.Ctx,
  src : Source,
  core : Core,
  w : Workspace,
  at : @sf.ListAt,
  picked : String?,
  pick : (String) -> Unit,
) -> Array[() -> Unit] {
  match stations_listed(src, w) {
    None => [fn() { @sf.waiting(c, dense=true, count=3) }]
    Some(listed) =>
      listed.mapi(fn(i, st) {
        let s = Some(st)
        let address = text(s, "station")
        // (as far in as the frame stands its list: a side column's in from its sides, a page's across it)
        fn() {
          if at == Whole {
            if @settings.station_card(c, core, st) {
              pick(address)
            }
            return
          }
          if @sf.nav_item(
                c,
                "stations/" + address,
                picked == Some(address),
                fn() { @sf.station_icon(c, text(s, "emoji"), text(s, "icon"), @sf.nav_mark_side, @sf.theme().p.text) },
                fn() { @sf.nav_title(c, text(s, "name")) },
                end=fn() { station_state(c, s) },
                lines=fn() { station_figures(c, src, s) },
                keep_lines=2,
                more=i + 1 < listed.length(),
                at~,
              ) {
            pick(address)
          }
        }
      })
  }
}

///|
/// Station as a page of its own (a small screen's: the bar's place, or pushed from settings): its list across the page,
/// 添加 station at its title's end where the frame does not hold it (a phone's bar's notch); none in the workspace yet,
/// the first to add.
pub fn stations_page(c : @ui.Ctx, src : Source, core : Core, here : Here, w : Workspace, frame : PageFrame) -> Unit {
  if stations_listed(src, w) is Some([]) {
    stations_first(c, src, core, here, w, frame)
    return
  }
  let key = "stations"
  let add = @settings.place_action(core, here, "stations")
  @sf.page(
    c,
    on_back=core.pop,
    frame~,
    key,
    "Station",
    stations_lines(c, src, core, w, Whole, None, fn(address) { (core.push)(Station(address)) }),
    listed=true,
    // (a place's top page under a phone's bar: its ＋ the bar's notch)
    actions?=match add {
      Some(run) if !frame.named =>
        Some(fn() {
          if @sf.icon_button(c, "plus", key="stations/add", round=true, label=@sf.t("web-pages.settings.stations.add")) {
            run(Of(c.id("stations/add")))
          }
        })
      _ => None
    },
  )
}

///|
/// None in the workspace (StationsFirst): its scene and the first to add (its managers': the others wait for one);
/// while they are read, said so.
pub fn stations_first(c : @ui.Ctx, src : Source, core : Core, here : Here, w : Workspace, frame : PageFrame) -> Unit {
  let t = @sf.theme()
  let read = stations_listed(src, w) is Some(_)
  @sf.page(c, on_back=core.pop, frame~, "stations-first", "Station", [
    fn() {
      if !read {
        @sf.waiting(c, shape=Cards, note={ reading: true, text: @sf.t("common.readingStations"), failing: [] })
        return
      }
      @sf.first_one(
        c,
        @sf.t("web-pages.settings.stations.add"),
        art=fn() { @sf.drawable(c, if t.dark { "illus_no_station_dark" } else { "illus_no_station" }, st_first_art_w) |> ignore },
        fn() {
          match @settings.place_action(core, here, "stations") {
            Some(add) =>
              if @sf.button(c, @sf.t("web-pages.settings.stations.add"), key="stations-first/add", tone=Primary, icon="plus") {
                add(Of(c.id("stations-first/add")))
              }
            None => @sf.page_note(c, @sf.t("web-pages.settings.stations.noneYet"))
          }
        },
      )
    },
  ])
}

///|
/// The first's scene's width (StationsFirst: 240).
let st_first_art_w : Double = 240.0
