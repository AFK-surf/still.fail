// 关于 and 更新日志, one page each in every frame (still.fail web/src/pages/About.tsx, Changelog.tsx, Changelog.css.ts; the
// narrow app's mobile/Settings.tsx AboutScreen, mobile/Changelog.tsx). 关于: this build, the way to a newer one,
// what changed; this machine's station's version and the way to its newer one, where the app looks after one here (本机
// Station); whether this device sends usage statistics and error reports (not where nothing is sent); still.fail's
// terms and privacy policy on its site; last, where the device keeps one, its performance record (性能记录: what
// warms it, kept on the device alone, @hostapi.perf_state; where the device has no share sheet, the way to its folder,
// where its logs are too: @hostapi.perf_opens). 更新日志: the core's `changelog`, a tab a part, by day,
// each change's lines with their kind before them, its version, what is not out yet; opened, what the last update
// brought is read (`changelog.seen`). Laid out by the page's width.

///|
/// 关于 (AboutPage; the narrow app's AboutScreen) made once as nodes (page_node,
/// laid out by the `width` its frame gives it, narrow where none is given) in node `v`: this build and the way to a newer one (how it
/// stands as the core's update says it, its bar coming and going with what is under way, the row growing and closing
/// round it), what changed; this machine's station and the way to its newer release (about_station_node); whether this
/// device sends usage statistics and error reports (where the build sends any:
/// the switch as the host has it, told as it is turned); still.fail's terms and privacy policy on its site; last, where
/// the device keeps one, its performance record (its switch as the host says it as it is turned here, the host telling
/// nothing of it otherwise: perf_turned; how much it holds as the host tells each write, @ui.perf_size; 分享记录 while
/// it holds anything; where the host opens its folder instead, 打开日志文件夹 always, for its logs are there whether the
/// record is kept or not).
pub fn about_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  // (this machine's station as its host says it, as it said it last, where the app looks after the station here
  // (local_station_managed: a Mac's, Windows', Linux's): a signal of that input, read again every few seconds from when
  // the page is made, as 本机 Station's page reads it, for it is added, stops and updates on its own time; "" elsewhere)
  let managed = @settings.local_station_managed()
  let host : @signals.Signal[String] = @signals.signal(if managed { @hostapi.app_said("local_station") } else { "" }, same=fn(a, b) {
    a == b
  })
  if managed {
    fn again(at : Double) -> Unit {
      v.at_moment(at + @settings.local_read_ms, later=true, fn() {
        host.set(@hostapi.app_said("local_station"))
        again(at + @settings.local_read_ms)
      })
      |> ignore
    }
    again(v.logic_at())
  }
  let station = fn() { Some(@json.parse(host.get()) catch { _ => Json::null() }) }
  // (what is said of what the pointer rests on, its station's row's: drawn over the page in its own node, station_node's)
  let tips = @sf.TipLayer::new(fn() { Some(v) })
  // (its blocks: the version's; this machine's station's where there is one (its data); the statistics' where the
  // build sends any; the terms'; the performance record's where the device keeps one)
  let blocks = fn() {
    let out = ["version"]
    if text(station(), "data") != "" {
      out.push("station")
    }
    if (core.reporting)() is Some(_) {
      out.push("reporting")
    }
    // (the web's iroh goes through relays alone and looks nothing up: no DHT there to turn off)
    if @ui.platform() != 4 {
      out.push("network")
    }
    out.push("legal")
    if @hostapi.perf_state() >= 0 {
      out.push("perf")
    }
    out
  }
  @sf.page_node(v, fn() { @sf.t("web-pages.settings.nav.about") }, on_back~, frame~, said?, width?, blocks, fn(b, key) {
    // (each a section of its own, its title shown on a wide page alone: heads=false)
    let section = fn(title : String, body : (@view.View) -> Unit) {
      @sf.section_node(b, fn() { @sf.t(title) }, heads=false, body)
    }
    match key {
      // this build, and what changed
      "version" =>
        section("web-pages.settings.nav.version", fn(s) {
          @sf.group_node(s, fn(g) {
            version_rows_node(g, core)
            @sf.link_row_node(g, fn() { @sf.t("web-pages.settings.nav.changelog") }, fn() { (core.push)(Changelog) })
          })
        })
      // this machine's station, under the app's own: its version and the way to its newer release
      "station" =>
        section("web-pages.localStation.title", fn(s) {
          @sf.group_node(s, fn(g) { about_station_node(g, core, station, tips) })
        })
      // a build that sends nothing has nothing to turn off (a card of words on a wide page)
      "reporting" =>
        section("web-pages.about.privacy", fn(s) {
          @sf.group_node(s, card=true, fn(g) {
            @sf.switch_row_node(
              g,
              fn() { @sf.t("common.telemetry.title") },
              fn() { (core.reporting)().unwrap_or(false) },
              fn(on) { (core.set_reporting)(on) },
              note=fn() { @sf.t("common.telemetry.note", args=[("name", @sf.product())]) },
            )
          })
        })
      // stations looked up in the Mainline DHT from this device (the core's `dht` pref, on unless turned off): off where
      // a company's filter marks the DHT as risky, the LAN's lookup kept
      "network" =>
        section("web-pages.about.network", fn(s) {
          @sf.group_node(s, card=true, fn(g) {
            @sf.switch_row_node(
              g,
              fn() { @sf.t("web-pages.about.dht.title") },
              fn() { @settings.pref(core, "dht") != "off" },
              fn(on) { @settings.set_pref(core, "dht", if on { "" } else { "off" }) },
              note=fn() { @sf.t("web-pages.about.dht.note") },
            )
          })
        })
      // on still.fail's site, in the browser
      "legal" =>
        section("web-pages.about.legal", fn(s) {
          @sf.group_node(s, fn(g) {
            for l in [("terms", "common.legal.terms"), ("privacy", "common.legal.privacy")] {
              @sf.link_row_node(g, fn() { @sf.t(l.1) }, fn() { (core.open_link)(@settings.legal_url(l.0)) }, out=true)
            }
          })
        })
      // this device's performance record, last and out of the way (where the device keeps one: iOS, Windows)
      _ =>
        section("web-pages.about.diagnostics", fn(s) {
          @sf.group_node(s, fn(g) {
            let opens = @hostapi.perf_opens()
            let on = fn() {
              perf_turned.get() |> ignore
              @hostapi.perf_state() == 1
            }
            // (how much it holds as the host says it wrote it, each write told: @ui.perf_size)
            let size = fn() {
              perf_turned.get() |> ignore
              @ui.perf_size()
            }
            @sf.switch_row_node(
              g,
              fn() { @sf.t("web-pages.about.perf.title") },
              on,
              fn(now) {
                @hostapi.set_perf(now)
                perf_turned.set(Some(now))
              },
              note=fn() {
                @sf.t(
                  if opens { "web-pages.about.perf.noteFolder" } else { "web-pages.about.perf.note" },
                  args=[("where", @hostapi.perf_where()), ("size", @sf.file_size(size()))],
                )
              },
            )
            if opens {
              @sf.link_row_node(g, fn() { @sf.t("web-pages.about.perf.open") }, acts=true, fn() {
                @hostapi.perf_open() |> ignore
              })
            } else {
              g.show(fn() { size() > 0.0 }, fn(r) {
                @sf.link_row_node(r, fn() { @sf.t("web-pages.about.perf.share") }, acts=true, fn() {
                  @hostapi.share("", "still.fail-perf.log", "text/plain", @hostapi.perf_read()) |> ignore
                })
              })
            }
          })
        })
    }
  })
}

///|
/// This build and the way to a newer one as nodes, a row each on every screen: its name and version, a row going
/// nowhere, words of a length known, the row's alone; then, where newer builds are asked for here (not on iOS, nor run
/// from the sources), 自动更新 (its switch), then 检查更新, a row of its own always, in the link's ink as the update's
/// row (pressed, the update dialog asks still.fail cloud and says what it answered), apart from installing one
/// (2026-11-03 the user: 「检查更新和安装更新应该分开」); and under it, while a newer build is known, the update's row in its three stages (updates.mbt update_stands: 有新版本 <version>, 正在下载
/// <version>, 重启以更新到 <version>; 允许安装更新, 重试… beside them) and the line under them, pressed to do what is the
/// person's to do (else the update dialog opens and says how it goes); under them the bar while something is under
/// way, its room opening and closing as that begins and ends (a move as far as the bar's room, from where it is then).
/// (A spinner at its end while how far was not known, the bar only while it was, made the row taller and shorter again
/// as it went, 2026-10-28. A button at the row's end took what its words left: the name cut to 「still.fail…」 on a
/// phone, 2026-10-26.)
fn version_rows_node(g : @view.View, core : Core) -> Unit {
  // (its name as the core's preferences say it, still.fail where they say none)
  @sf.link_row_node(g, fn() {
    let product = text((core.topic)("prefs", Map([])).get().value, "productName")
    (if product == "" { @sf.product() } else { product }) + " " + build_version()
  }, fn() {  }, goes=false)
  let v = fn() { (core.version_now)() }
  // (whether newer builds come by themselves, on unless turned off, under what it is about: off, one is said in the
  // update's row and comes only as the person presses it, 2026-11-04 the user「自动更新应该有个设置，默认打开可以关闭」)
  g.show(fn() { v().asks }, fn(r) {
    @sf.switch_row_node(
      r,
      fn() { @sf.t("android-settings.version.auto") },
      fn() { @settings.pref(core, "appUpdate") != "off" },
      fn(on) {
        @settings.set_pref(core, "appUpdate", if on { "" } else { "off" })
        if on {
          (core.update_auto_on)()
        }
      },
      note=fn() { @sf.t("android-settings.version.auto.note", args=[("app", @sf.product())]) },
    )
  })
  // (what is done at once where it is, in the link's ink: checking, and the update's row under it)
  g.show(fn() { v().asks }, fn(r) {
    @sf.link_row_node(r, fn() { @sf.t("android-settings.version.check") }, fn() { (core.version_check)() }, acts=true)
  })
  g.show(fn() { v().asks && v().newer }, fn(r) {
    let open = @motion.Way::new(if @signals.untracked(fn() { v().going }) { 1.0 } else { 0.0 })
    r.reacts(fn() { v().going }, fn(going) {
      let to = if going { 1.0 } else { 0.0 }
      open.go(to, @motion.moved().per_unit(version_bar_room), at=r.cause_at())
    })
    let share = fn() {
      open.said()
      open.value_at(r.drawn_while(fn(t) { open.goes_at(t) }))
    }
    @sf.link_row_node(
      r,
      fn() { v().label },
      fn() { (core.version_tap)() },
      note=fn() { v().note },
      acts=true,
      below=fn(b) {
        b.box(fn(bar) {
          bar.grow(Is(1.0)) |> ignore
          @sf.progress_node(bar, fn() { v().part }, fn() { @ui.tree_theme().line }, fn() { @sf.theme().p.accent }) |> ignore
        })
        |> ignore
      },
      below_open=share,
    )
  })
}

///|
/// How tall the room the update's bar opens is (row_below's 6 over it, the bar's 3): how far its opening moves.
let version_bar_room : Double = 9.0

///|
/// 关于's 本机 Station: the station here updates on its own, apart from the app, and its newer release was said only on
/// its own page, where it was missed (the user, 2026-11-10: 「关于菜单里面的那个更新，应该还有一个板块提及本机 station 的
/// 更新，这样子大家就不会漏掉了」). `host`: what its host says of it (本机 Station's word). While it is up in a workspace
/// of this account's, its row as its page's 软件与更新 has it (software_row_node: its version, a newer release and 更新
/// to it, how an update goes or why it failed, its 自动更新 for its workspace's managers), out of its software alone
/// (`stationPart`'s `updates`, its `station`), and why an update asked here failed under it. Otherwise (in no workspace
/// of this account's, away, its software not read yet) its version as its host says it, and while it is away, that its
/// update is seen once it is up.
fn about_station_node(g : @view.View, core : Core, host : () -> Json?, tips : @sf.TipLayer) -> Unit {
  // (its address in its workspace as the block is made, "" where it is in none: this_machine's)
  let address = this_machine()
  // (that workspace as this account is in it; none where it is not, and nothing of it asked then)
  let here = fn() -> Here? {
    guard address != "" else { return None }
    let h = @settings.here_of(core, @settings.workspace_of(address), "")
    if h.sub == "" {
      None
    } else {
      Some(h)
    }
  }
  // (its row in its workspace's stations)
  let row = fn() -> Json? {
    guard here() is Some(h) else { return None }
    match @settings.stations_of(core, h).value {
      Some(Array(rows)) => rows.iter().find_first(fn(r) { text(Some(r), "station") == address })
      _ => None
    }
  }
  // (its own software, while it is up)
  let own = fn() -> Json? {
    guard here() is Some(h) else { return None }
    guard flag(row(), "online") else { return None }
    match @settings.station_part(core, h, address, "updates") {
      Some(Array(updates)) => updates.iter().find_first(fn(u) { text(Some(u), "id") == "station" })
      _ => None
    }
  }
  // (its workspace's owners and admins: theirs to turn its 自动更新, as on its page)
  let manager = fn() {
    guard here() is Some(h) else { return false }
    let role = text(@settings.workspace_view(core, h).value, "role")
    role == "owner" || role == "admin"
  }
  g.pick(
    fn() {
      let up = own() is Some(_)
      (up, up && manager())
    },
    fn(r, k) {
      if k.0 {
        software_row_node(
          r,
          core,
          address,
          own,
          k.1,
          fn() {
            is_doing(core, ["software.updateAll"], [("station", address)]) ||
            is_doing(core, ["software.update"], [("station", address), ("id", "station")])
          },
          fn() { false },
          tips,
        )
      } else {
        said_row_node(
          r,
          fn() {
            match text(host(), "version") {
              "" => "Station"
              version => "Station " + version
            }
          },
          note=fn() {
            if row() is Some(_) && !flag(row(), "online") {
              @sf.t("web-pages.stations.softwareOffline")
            } else {
              ""
            }
          },
        )
      }
    },
  )
  // (why an update asked here failed, under it: as under its page's software)
  g.show(fn() { software_failed.get(address) is Some(_) }, fn(f) {
    f.box(fn(foot) {
      @sf.style_node(foot, fn() { sw_foot })
      @sf.words_node(foot, fn() { software_failed.get(address).unwrap_or("") }, fn() { sw_failed_line }) |> ignore
    })
    |> ignore
  })
}

///|
/// What 性能记录 was last turned to here (None: not turned here yet): what its row reads, so it is built again as it is
/// turned otherwise (the host's state is no signal).
// kept across runs: said as it is turned; changelog_reset puts it back
let perf_turned : @signals.Signal[Bool?] = @signals.signal(None, same=fn(a, b) { a == b })

///|
/// The changelog's part in view ("" the first), and the news last told read (as the core says it: told once, not again
/// each frame until the core has it, and news an update brings later told again).
// kept across runs: said by its tabs and as it opens; changelog_reset puts them back
let changelog_part : @signals.Signal[String] = @signals.signal("")

///|
// kept across runs: said as the page opens; changelog_reset puts it back
let changelog_seen : Ref[String] = Ref("")

///|
fn changelog_reset() -> Unit {
  changelog_part.set("")
  changelog_seen.val = ""
  perf_turned.set(None)
}

///|
/// How long each made-up change is (letters), day by day.
// kept across runs: a table, never written
let changelog_sample_lines : Array[Array[Int]] = [[18, 26, 12], [22, 15]]

///|
/// How wide each of the changelog's parts is at least in its choice, wide (item_w).
let cl_tab_w : Double = 120.0
