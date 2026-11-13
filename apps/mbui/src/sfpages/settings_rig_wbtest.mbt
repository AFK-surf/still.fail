// The settings' pages here (about.mbt, appearance.mbt, automatic_decisions.mbt, bars.mbt, memory.mbt,
// notifications.mbt, permissions.mbt, shortcuts.mbt, usage.mbt, account.mbt, workspace_page.mbt, security.mbt, vault.mbt, vault_item.mbt, connects.mbt, connect.mbt, station_page.mbt, accounts.mbt)
// drawn alone over the made-up core's settings, in a box of each width, with a finger and with a mouse: what each is
// for, laid out by its own width. What the shell does around them (the tier, its sidebar, the system's bars) is the
// whole app's tests' (src/sfapp).

///|
/// The made-up workspace the settings' fixture is of.
let rig_workspace : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "" }

///|
/// The settings' page `route` over the made-up core's `mode` (as `over` has it), `w` wide, pointed at as `platform`
/// says (2 a phone's finger, 0 a Mac's mouse), `h` high: opened under settings, drawn alone while it is the stack's top
/// (another of them opened from it, that one), back over it to settings, the presenters over it. `ready`: what the test
/// sets before it is first drawn (the settings' own state: a station's part shown, a login marked); `host`, what the
/// device's host says from the start, its Tester made (a performance record kept, newer builds asked for).
fn setting_tester(
  route : @settings.Route,
  w : Double,
  platform? : Int = 0,
  mode? : String = "settings",
  over? : (Source) -> Source = fn(s) { s },
  h? : Double = 900.0,
  ready? : () -> Unit = fn() {  },
  host? : (@ui.Tester) -> Unit = fn(_) {  },
  env? : Array[(String, String)] = [],
) -> @ui.Tester {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  // (what the settings' own fixture keeps for a mode: their made-up state, as the app's fixture sets it)
  if mode != "settings" {
    @settings.fixture_page(mode) |> ignore
  }
  let src = over(@sffixture.fixture(mode))
  ready()
  app.nav.push(Settings)
  app.nav.push(Setting(route))
  let made = @settings.made_once(route)
  let t = @ui.Tester::new(
    @ui.old_views_here,
    tree=@sf.presented_tree(fn(c) {
      // (made once: the presenters around the tree's page, set_view_app's)
      guard !made else { return }
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        match app.nav.top() {
          Setting(r) => setting_alone(c, src, r)
          _ => ()
        }
        @sf.presented(c)
      })
    }),
    w~,
    h~,
    platform~,
    env~,
  )
  // (what the device's host says from the start: a performance record kept)
  host(t)
  // (the pages every frame makes once (setting_made's), as they make them: the page on top made in the window's tree, `w`
  // wide, the presenters around it)
  if made {
    @ui.set_view_app(
      fn(root) {
        // (its nodes drawn in still.fail's theme, as the app's are: app_tree's; told as the tree is made, set_view_app
        // having forgotten what was told before it)
        @ui.set_tree_theme(@sf.ui_theme_now)
        root.pick(fn() { app.nav.top() }, fn(p, page) {
          @ui.words_picked(p)
          match page {
            Setting(r) => setting_made(p, src, r, fn() { w })
            _ => ()
          }
        })
        // (what of the presented the tree draws, over the page: as the app's tree has it)
        @sf.presented_nodes(root)
      },
      around=fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          // (the old views it holds, where it puts them: the pages opened from them not made once yet)
          @ui.old_views_here(c)
          @sf.presented(c)
        })
      },
    )
  }
  t.draw()
  t
}

///|
/// The page of `route` made once in node `p` (关于, 更新日志, 记忆, 一台 station 的记忆, 归档, 一台 station 的归档, 自动决策:
/// as the frames make them; another, its old view), `width`
/// wide, in the frame a page under another is given.
fn setting_made(p : @view.View, src : Source, route : @settings.Route, width : () -> Double) -> Unit {
  let core = @sfbase.settings_core(src, rig_workspace)
  let here = fn() { @settings.here_of(core, rig_workspace.id, rig_workspace.name) }
  @settings.frame(core, here())
  let frame = fn() -> PageFrame { { back: app.nav.under().map(@sfbase.back_label), top: 0.0, foot: 0.0, named: false } }
  p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  match route {
    About => about_node(p, core, on_back=core.pop, frame~, width~)
    Changelog => changelog_node(p, core, on_back=core.pop, frame~, width~)
    Memories => memories_node(p, core, here, on_back=core.pop, frame~, width~)
    Memory(a) => memory_node(p, core, here, a, on_back=core.pop, frame~, width~)
    Archiving => archiving_node(p, core, here, on_back=core.pop, frame~, stint=fn() { 0 }, width~)
    StationArchiving(st) => station_archiving_node(p, core, here, st, on_back=core.pop, frame~, width~)
    AutoDecisions => decisions_node(p, core, here, on_back=core.pop, frame~, width~)
    AutoCompletion => completion_node(p, core, here, on_back=core.pop, frame~, width~)
    Usage => usage_node(p, core, src, here, on_back=core.pop, frame~, width~)
    Shortcuts => {
      // (recording while it is the one on top, as every frame says it: its stay there as it is made)
      let stay = @signals.untracked(fn() { app.nav.top_stay().1 })
      shortcuts_node(p, core, on_back=core.pop, frame~, active=fn() { app.nav.top_stay().1 == stay }, width~)
    }
    Notifications => notify_node(p, core, here, on_back=core.pop, frame~, stint=fn() { 0 }, width~)
    AutoPolicy(st) => policy_node(p, core, here, st, on_back=core.pop, frame~, width~)
    Appearance => appearance_node(p, core, on_back=core.pop, frame~, width~)
    LocalStation => local_station_node(p, core, on_back=core.pop, frame~, width~)
    Permissions => permissions_node(p, core, on_back=core.pop, frame~, width~)
    Security => security_node(p, core, here, on_back=core.pop, frame~, width~)
    SecurityOpen => security_open_node(p, core, here, on_back=core.pop, frame~, width~)
    MemoryDoc(a, skill, at) => memory_doc_node(p, core, here, a, skill, at, on_back=core.pop, frame~, width~)
    UsagePrices(days) => usage_prices_node(p, core, here, days, on_back=core.pop, frame~, width~)
    Workspace => workspace_node(p, core, here, on_back=core.pop, frame~, stint=fn() { 0 }, width~)
    VaultItems => vault_items_node(p, core, here, on_back=core.pop, frame~, width~)
    Connects(only) => connects_node(p, src, core, here, only, on_back=core.pop, frame~, stint=fn() { 0 }, width~)
    Connect(station, id) => connect_node(p, src, core, here, station, id, on_back=core.pop, frame~, stint=fn() { 0 }, width~)
    Profile(a, id) => profile_node(p, core, here, a, id, on_back=core.pop, frame~, width~)
    NewProfile(a) => new_profile_node(p, core, src, here, a, on_back=core.pop, frame~, width~)
    Station(a) => station_node(p, core, here, a, on_back=core.pop, frame~, width~)
    // (the pages opened from them not made once yet: their old view, hosted)
    _ =>
      @ui.old(p, fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() { setting_alone(c, src, route) })
      })
      .grow(Is(1.0))
      |> ignore
  }
}

///|
/// The page of `route`, in the frame a page under another is given: back over it, no room kept for bars.
fn setting_alone(c : @ui.Ctx, src : Source, route : @settings.Route) -> Unit {
  let core = @sfbase.settings_core(src, rig_workspace)
  let here = @settings.here_of(core, rig_workspace.id, rig_workspace.name)
  @settings.frame(core, here)
  let frame : PageFrame = { back: app.nav.under().map(@sfbase.back_label), top: 0.0, foot: 0.0, named: false }
  match route {
    Fonts => fonts_page(c, core, frame)
    BarSettings => bars_page(c, core, frame)
    Me => me_page(c, core, here, frame)
    Vault => vault_page(c, core, here, frame)
    VaultItem(v, item) => vault_item_page(c, core, here, frame, v, item)
    _ => ()
  }
}

///|
/// Each width a page is drawn at and the hand it is pointed with: a phone's with a finger and with a mouse, a page
/// between, a tablet's with a finger, a desktop's with a mouse.
let page_cases : Array[(Double, Int)] = [(390.0, 2), (390.0, 0), (720.0, 0), (1100.0, 2), (1280.0, 0)]

///|
/// Whether a page `w` wide is laid out wide.
fn laid_wide(w : Double) -> Bool {
  @sf.look_for(w) is Wide
}

///|
/// The page `w` wide scrolled (the wheel over its middle) until `words` stand in its box, clear of its edges, to be
/// pressed.
fn scrolled_to(t : @ui.Tester, w : Double, words : String) -> Unit {
  let x = w / 2.0
  t.move_to(x, 450.0)
  for _ in 0..<12 {
    match t.find(words) {
      Some((_, y)) if y < 40.0 => t.wheel(x, 450.0, -300.0)
      Some((_, y)) if y < 860.0 => break
      _ => t.wheel(x, 450.0, 300.0)
    }
  }
}

///|
/// Presses `words` drawn whole and shown (the rightmost where several are: the page's, not its title's or a note's).
fn tap_words(t : @ui.Tester, words : String) -> Unit raise {
  let shown = t.words().filter(fn(w) { w.0 == words && w.5 > 0.5 })
  guard shown.length() > 0 else { fail("no \{words} drawn") }
  let mut at = shown[0]
  for w in shown {
    if w.1 > at.1 {
      at = w
    }
  }
  t.tap(at.1 + at.3 / 2.0, at.2 + at.4 / 2.0)
}
