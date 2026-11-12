// 本机 Station (apps/desktop/src/main.ts localStation), one page in every frame: this
// machine's station whoever runs it (the service the installer made, a process started by hand), as the system says
// it (@ui.local_station), shown as a workspace's stations are: its dot, its name and
// how it is, 启动 where it is stopped, its menu (停止 or 启动, 重启, 更新到最新版, 打开日志, its data shown); under
// them who runs it, its version, its workspace, its data, in lines as the room has them; the installer's progress and
// what went wrong in it. None here: 添加这台 Mac where the app adds one. (The phone's copy, its rows a list each, is
// gone: a station is shown the one way everywhere.)

///|
/// 本机 Station (LocalStationPage), made once in node `v` as wide as `width` gives it, in the frame it is given: the
/// host asked again every few seconds from when it is made (it starts, stops and updates on its own time; a moment
/// said each time, not a frame's build), and again as soon as something is done to it from here.
pub fn local_station_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  // (what the host says of it, as it said it last: a signal of that input, read again at each moment it is asked)
  let host : @signals.Signal[String] = @signals.signal(@ui.local_station(), same=fn(a, b) { a == b })
  let asked = fn() { host.set(@ui.local_station()) }
  fn again(at : Double) -> Unit {
    v.at_moment(at + @settings.local_read_ms, later=true, fn() {
      asked()
      again(at + @settings.local_read_ms)
    })
    |> ignore
  }
  again(v.logic_at())
  let s = fn() {
    let parsed = @json.parse(host.get()) catch { _ => Json::null() }
    Some(parsed)
  }
  let pc = @settings.local_machine_pc()
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.localStation.title") },
    on_back~,
    frame~,
    said?,
    width?,
    about=fn() {
      @sf.t(if pc { "web-pages.localStation.leadPc" } else { "web-pages.localStation.lead" }, args=[("name", "still.fail")])
    },
    fn() { if text(s(), "data") == "" { ["none"] } else { ["card"] } },
    fn(b, key) {
      if key == "none" {
        local_none_node(b, core, s, pc, asked)
      } else {
        local_card_node(b, core, s, pc, asked)
      }
    },
  )
}

fn local_add_foot_node(
  k : @view.View,
  core : Core,
  adds : () -> Bool,
  pc : Bool,
  asked : () -> Unit,
) -> Unit {
  k.show(adds, fn(f) {
    f.box(fn(a) {
      @sf.style_node(a, fn() { vt_actions.then(@sf.foot_across(@sf.button_height())) })
      @sf.button_node(
        a,
        fn() { @sf.t(if pc { "web-pages.settings.thisPc.add" } else { "web-pages.settings.thisMac.add" }) },
        fn() {
          (core.local_install)(true)
          asked()
        },
        tone=Primary,
        card_words=true,
      )
      |> ignore
    })
    |> ignore
  })
}

///|
/// None here (no data): the installer at work where it is, else that there is none; what went wrong; 添加这台 Mac (it
/// downloads one, joins it and runs it as a service) in the card's foot corner where the app adds one.
fn local_none_node(b : @view.View, core : Core, s : () -> Json?, pc : Bool, asked : () -> Unit) -> Unit {
  let doing = fn() { text(s(), "doing") }
  let adds = fn() { doing() == "" && @settings.local_station_managed() }
  // (添加这台 Mac last, in the card's foot corner: concentric with it, out past its words: the library's footed card)
  b.pick(adds, fn(c, footed) { @sf.page_card_node(c, footed~, fn(k) {
    k.pick(fn() { doing() }, fn(w, d) {
      if d != "" {
        local_progress_node(w, s, fn() { d })
      } else {
        @sf.words_node(w, fn() { @sf.t("desktop.local.noService") }, fn() { desk_muted }) |> ignore
      }
    })
    local_failed_node(k, s)
    local_add_foot_node(k, core, adds, pc, asked)
  }) })
}

///|
/// The station's card (StationCards card): its head (its dot, its name and how it is, 启动 where it is stopped and can
/// be, its ⋯), its facts, the installer's progress, what went wrong, and 添加这台 Mac where unattached or removed.
fn local_card_node(b : @view.View, core : Core, s : () -> Json?, pc : Bool, asked : () -> Unit) -> Unit {
  let doing = fn() { text(s(), "doing") }
  let working = fn() { doing() != "" }
  let running = fn() { text(s(), "runner") != "none" }
  let adds = fn() {
    if doing() != "" || !@settings.local_station_managed() {
      return false
    }
    let ws = field(s(), "workspace")
    !(ws is Some(Object(_))) || flag(ws, "removed")
  }
  let act = fn(a : String) {
    let now = @signals.untracked(s)
    match a {
      "update" => (core.local_install)(false)
      "start" => local_start(core, now)
      _ => @ui.local_station_act(a)
    }
    asked()
  }
  b.box(fn(k) {
    @sf.style_node(k, fn() { if adds() { ls_card.then(@sf.foot_pad(@sf.button_height())) } else { ls_card } })
    k.box(fn(head) {
      @sf.style_node(head, fn() { ls_head }, in_row=false)
      @sf.state_dot_node(head, fn() { if working() { "busy" } else if running() { "online" } else { "offline" } })
      head.box(fn(title) {
        @sf.style_node(title, fn() { ls_title }, in_row=true)
        @sf.words_node(title, fn() { local_station_name(s(), pc) }, fn() { ls_name }) |> ignore
        @sf.words_node(title, fn() { local_state(s()) }, fn() { ls_state }) |> ignore
      })
      |> ignore
      // (words alone, on its name's line: the line as high as with none, its ⋯ concentric in the card's corner)
      head.show(fn() { !running() && !working() && local_startable(s()) }, fn(e) {
        @sf.line_end_node(e, fn(l) {
          @sf.button_node(l, fn() { @sf.t("web-pages.localStation.start") }, fn() { act("start") }, tone=Ghost) |> ignore
        })
      })
      local_more_node(head, s, act)
    })
    |> ignore
    // its facts (cardFoot): who runs it, its version, its workspace, its data, past its dot, in lines as the room has
    // them
    local_past_dot_node(k, fn(u) {
      u.box(fn(f) {
        @sf.style_node(f, fn() { ls_foot }, in_row=false)
        f.wraps(Is(Some(0.0))) |> ignore
        f.each(fn() { local_facts(s(), pc) }, fn(line) { line }, fn(w, line) {
          @sf.words_node(w, fn() { line.get() }, fn() { ls_fact }) |> ignore
        })
      })
      |> ignore
    })
    k.show(fn() { doing() == "install" || doing() == "update" }, fn(p) {
      local_past_dot_node(p, fn(u) { local_progress_node(u, s, doing) })
    })
    k.show(fn() { text(s(), "failed") != "" }, fn(p) { local_past_dot_node(p, fn(u) { local_failed_node(u, s) }) })
    local_add_foot_node(k, core, adds, pc, asked)
  })
  |> ignore
}

///|
/// Its ⋯ (an icon button, a block in the card's top right corner): pressed, its menu beside it (停止 or 启动, 重启,
/// 更新到最新版, 打开日志, its data shown), lined up at its end; open till it is chosen from or dismissed (the hand,
/// Escape, a press outside it), local_menu said so as it opens and as it goes.
fn local_more_node(head : @view.View, s : () -> Json?, act : (String) -> Unit) -> Unit {
  let t = fn() { @sf.theme() }
  let open : @signals.Signal[Bool] = @signals.signal(local_menu.val)
  let more : Ref[@view.View?] = Ref(None)
  let press = fn() {
    guard more.val is Some(m) else { return }
    let now = @signals.untracked(s)
    let working = text(now, "doing") != ""
    let running = text(now, "runner") != "none"
    let items : Array[@sf.MenuItem?] = []
    let item = fn(key : String, label : String, icon : String, disabled : Bool) {
      items.push(Some(@sf.menu_item_of(label, icon~, disabled~, fn() { act(key) })))
    }
    if running {
      item("stop", @sf.t("web-pages.localStation.stop"), "stop", working)
      if text(now, "runner") != "other" {
        item("restart", @sf.t("web-pages.localStation.restart"), "refresh", working)
      }
    } else {
      item("start", @sf.t("web-pages.localStation.start"), "play", working || !local_startable(now))
    }
    // brought up to the latest release (the installer), not one started by hand
    if text(now, "runner") != "other" && @settings.local_station_managed() {
      item("update", @sf.t("web-pages.localStation.update"), "refresh", working)
    }
    items.push(None)
    item("log", @sf.t("web-pages.localStation.openLog"), "file-text", false)
    item("folder", @settings.local_folder_label(), "folder", false)
    let (x, y, w, h) = m.placed_window_now()
    local_menu.val = true
    open.set(true)
    @sf.menu(items, from=At(x, y, w, h), along=End, gone=fn() {
      local_menu.val = false
      open.set(false)
    })
  }
  more.val = Some(
    head.box(fn(m) {
      @sf.style_node(m, fn() { ls_more_at })
      m
      .ground(By(fn() { if m.pointed() { @ui.tree_theme().color(Hover) } else { 0L } }))
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.menu.more"), expanded=open.get())) }))
      |> ignore
      @sf.presses_node(m, press)
      @sf.icon_node(m, "more", ws_more_icon, By(fn() { t().p.muted })) |> ignore
    }),
  )
}

///|
/// What stands under its head past its dot (cardFoot's margin: the dot and the head's gap after it), `body` made in it.
fn local_past_dot_node(k : @view.View, body : (@view.View) -> Unit) -> Unit {
  k.box(fn(r) {
    @sf.style_node(r, fn() { ls_past })
    r.box(fn(d) { @sf.style_node(d, fn() { ls_dot_room }, in_row=true) }) |> ignore
    r.box(fn(u) {
      @sf.style_node(u, fn() { ls_under }, in_row=true)
      body(u)
    })
    |> ignore
  })
  |> ignore
}

///|
/// Its name: its station's in its workspace, else this machine's.
fn local_station_name(s : Json?, pc : Bool) -> String {
  match text(field(s, "workspace"), "stationName") {
    "" => @sf.t(if pc { "web-pages.localStation.thisPc" } else { "web-pages.localStation.thisMac" })
    n => n
  }
}

///|
/// How it is: what is being done to it, else 运行中 or 已停止.
fn local_state(s : Json?) -> String {
  let doing = text(s, "doing")
  if doing != "" {
    @sf.t("web-pages.localStation.doing." + doing)
  } else if text(s, "runner") != "none" {
    @sf.t("web-pages.localStation.running")
  } else {
    @sf.t("web-pages.localStation.stopped")
  }
}

///|
/// Its facts, those it has: who runs it, its version, its workspace, its data.
fn local_facts(s : Json?, pc : Bool) -> Array[String] {
  ignore(pc)
  let service = field(s, "service") is Some(_)
  let workspace = field(s, "workspace")
  let run_by = match text(s, "runner") {
    "service" => service_name(s)
    "other" => @sf.t("web-pages.localStation.byHand")
    "app" => @sf.t("web-pages.localStation.byApp", args=[("name", "still.fail")])
    // stopped: its service's; with none, nothing runs it (this app runs none of its own)
    _ => if service { service_name(s) } else { "" }
  }
  let place = if !(workspace is Some(Object(_))) {
    @sf.t("web-pages.localStation.noWorkspace")
  } else {
    let ws = match text(workspace, "name") {
      "" => text(workspace, "id")
      n => n
    }
    @sf.t(if flag(workspace, "removed") { "web-pages.localStation.removed" } else { "web-pages.localStation.inWorkspace" }, args=[("workspace", ws)])
  }
  [run_by, text(s, "version"), place, text(s, "data")].filter(fn(l) { l != "" })
}

///|
/// Which service runs it (launchd, systemd, a task), as the host says.
fn service_name(s : Json?) -> String {
  match text(field(s, "service"), "kind") {
    "" => @sf.t("web-pages.localStation.service.launchd")
    k => @sf.t("web-pages.localStation.service." + k)
  }
}

///|
/// The installer at work (install, update) as `doing` says: what it does and how far, a bar as far, the step it last
/// said.
fn local_progress_node(v : @view.View, s : () -> Json?, doing : () -> String) -> Unit {
  let known = fn() { field(s(), "percent") is Some(_) }
  let percent = fn() { number(s(), "percent") }
  @sf.words_node(v, fn() {
    @sf.t("web-pages.localStation.doing." + doing()) + (if known() { " · \{percent().to_int()}%" } else { "" })
  }, fn() { desk_muted })
  |> ignore
  v.box(fn(b) {
    @sf.style_node(b, fn() { ls_bar })
    @sf.progress_node(b, fn() { if known() { Some(percent() / 100.0) } else { None } }, fn() { @ui.tree_theme().line }, fn() {
      @sf.theme().p.accent
    })
    |> ignore
  })
  |> ignore
  v.show(fn() { text(s(), "said") != "" }, fn(w) { @sf.words_node(w, fn() { text(s(), "said") }, fn() { desk_note }) |> ignore })
}

///|
/// What went wrong with the last act (warn: red), where something did.
fn local_failed_node(v : @view.View, s : () -> Json?) -> Unit {
  v.show(fn() { local_failed_words(s()) != "" }, fn(w) { @sf.words_node(w, fn() { local_failed_words(s()) }, fn() { ls_warn }) |> ignore })
}

///|
/// What went wrong with the last act, in words ("" nothing).
fn local_failed_words(s : Json?) -> String {
  match text(s, "failed") {
    "busy" => @sf.t("desktop.local.busy")
    "byHand" => @sf.t("desktop.local.byHand")
    "noService" => @sf.t("desktop.local.noService")
    e => e
  }
}

///|
/// Whether the station here can be started from here: by its service; with none (still.fail's desktop app ran it from
/// its own bundle, gone with that app; its service taken away), where the app looks after the station here, by the
/// installer without a token, which makes it one as it is and starts it (更新到最新版's, local_station_carry_on's): a
/// station in a workspace, the installer's `update` refusing one in none.
fn local_startable(s : Json?) -> Bool {
  field(s, "service") is Some(_) ||
  (text(field(s, "workspace"), "id") != "" && @settings.local_station_managed())
}

///|
/// 启动 the station here (local_startable): its service started, else the installer without a token.
fn local_start(core : Core, s : Json?) -> Unit {
  if field(s, "service") is Some(_) {
    @ui.local_station_act("start")
  } else {
    (core.local_install)(false)
  }
}

///|
/// The station here as its host says it, where it is the station at `address` (the page of one in a workspace, the
/// stations' row) and is not running, but can be started from here (stopped, or being started, installed or updated):
/// 启动 offered for it there, not a try at reaching it again. None for any other.
pub fn local_stopped(address : String) -> Json? {
  local_stopped_in(address, @ui.local_station())
}

///|
/// The station here as `said` (the host's words for it) has it, where it is the station at `address` and is not running
/// but can be started from here (local_stopped's).
fn local_stopped_in(address : String, said : String) -> Json? {
  if address == "" || address != this_machine() {
    return None
  }
  let s = match said {
    "" => return None
    j => try Some(@json.parse(j)) catch { _ => return None }
  }
  if text(s, "runner") == "none" && local_startable(s) {
    s
  } else {
    None
  }
}

///|
/// How the station here stands where it is not running (local_stopped): what is being done to it, else 已停止.
pub fn local_stopped_words(s : Json?) -> String {
  match text(s, "doing") {
    "" => @sf.t("web-pages.localStation.stopped")
    doing => @sf.t("web-pages.localStation.doing." + doing)
  }
}

///|
/// Whether its menu is open.
// kept across runs: said by the page's ⋯; reset puts it back
let local_menu : Ref[Bool] = Ref(false)

///|
/// Whether its menu is open (tests).
pub fn local_menu_open() -> Bool {
  local_menu.val
}

///|
/// (card: its parts 10 apart, the card's padding and ground)
// kept across runs: a value (no field of it changes)
let ls_card : @ui.Style = @sf.desk_card.then(@ui.css("gap=S2_5"))

///|
/// (cardHead: its dot, its title, its buttons, 10 apart)
// kept across runs: a value (no field of it changes)
let ls_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
/// Its ⋯ (an icon button: 32, a block: in the card's top right corner, out past its words to 16 in, concentric with
/// the card's there: a small block's corner of the ladder's, all four alike).
// kept across runs: a value (no field of it changes)
let ls_more_at : @ui.Style = @ui.css("w=S8 h=S8 align=ACenter justify=JCenter")
  .then(@ui.style(radius=@sf.small_radius))
  .then(@sf.card_top_end_out)

///|
/// (cardTitle: its name and how it is on a line, 10 apart)
// kept across runs: a value (no field of it changes)
let ls_title : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2_5, align=AEnd)

///|
/// (name: the body's size, 600)
// kept across runs: a value (no field of it changes)
let ls_name : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Semibold, color=Fg, wrap=false)

///|
/// (state: the list's size, muted)
// kept across runs: a value (no field of it changes)
let ls_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// (cardFoot: its facts 12 apart, going on in lines where the room ends, past its dot: 17 in)
// kept across runs: a value (no field of it changes)
let ls_foot : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let ls_past : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ls_fact : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// What comes under its facts, as far in.
// kept across runs: a value (no field of it changes)
let ls_under : @ui.Style = @ui.style(w=@sf.grow, gap=S1_5)

///|
// kept across runs: a value (no field of it changes)
let ls_bar : @ui.Style = @ui.css("w=Full py=S1")

///|
/// (warn: red, the list's size, 500)
// kept across runs: a value (no field of it changes)
let ls_warn : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Danger, w=Full)

///|
/// Its dot's room, what stands under its head being past it.
// kept across runs: a value (no field of it changes)
let ls_dot_room : @ui.Style = @ui.style(w=@sf.dot_size)
