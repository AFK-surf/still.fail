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
/// sets before it is first drawn (the settings' own state: a station's part shown, a login marked).
fn setting_tester(
  route : @settings.Route,
  w : Double,
  platform? : Int = 0,
  mode? : String = "settings",
  over? : (Source) -> Source = fn(s) { s },
  h? : Double = 900.0,
  ready? : () -> Unit = fn() {  },
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
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        match app.nav.top() {
          Setting(r) => setting_alone(c, src, r)
          _ => ()
        }
        @sf.presented(c)
      })
    },
    w~,
    h~,
    platform~,
  )
  t.draw()
  t
}

///|
/// The page of `route`, in the frame a page under another is given: back over it, no room kept for bars.
fn setting_alone(c : @ui.Ctx, src : Source, route : @settings.Route) -> Unit {
  let core = @sfbase.settings_core(src, rig_workspace)
  let here = @settings.here_of(core, rig_workspace.id, rig_workspace.name)
  @settings.frame(core, here)
  let frame : PageFrame = { back: app.nav.under().map(@sfbase.back_label), top: 0.0, foot: 0.0, named: false }
  match route {
    About => about_page(c, core, frame)
    Changelog => changelog_page(c, core, frame)
    Appearance => appearance_page(c, core, frame)
    Fonts => fonts_page(c, core, frame)
    BarSettings => bars_page(c, core, frame)
    Permissions => permissions_page(c, core, frame)
    Archiving => archiving_page(c, core, here, frame)
    StationArchiving(s) => station_archiving_page(c, core, here, frame, s)
    Notifications => notify_page(c, core, here, frame)
    Shortcuts => shortcuts_page(c, core, frame)
    Me => me_page(c, core, here, frame)
    Workspace => workspace_page(c, core, here, frame)
    Security => security_page(c, core, here, frame)
    SecurityOpen => security_open_page(c, core, here, frame)
    Vault => vault_page(c, core, here, frame)
    VaultItems => vault_items_page(c, core, here, frame)
    VaultItem(v, item) => vault_item_page(c, core, here, frame, v, item)
    Connects(only) => connects_page(c, src, core, here, frame, only)
    Connect(station, id) => connect_page(c, src, core, here, frame, station, id)
    Station(a) => station_page(c, core, here, frame, a)
    Profile(a, id) => profile_page(c, core, here, frame, a, id)
    PickModels(a, id) => pick_models_page(c, core, here, frame, a, id)
    LocalStation => local_station_page(c, core, frame)
    MemoryDoc(a, skill, at) => memory_doc_page(c, core, here, frame, a, skill, at)
    AutoCompletion => completion_page(c, core, here, frame)
    AutoPolicy(st) => policy_page(c, core, here, frame, st)
    ProfileModels(a, id) => profile_models_page(c, core, here, frame, a, id)
    Memories => memories_page(c, core, here, frame)
    Memory(a) => memory_page(c, core, here, frame, a)
    AutoDecisions => decisions_page(c, core, here, frame)
    Usage => usage_page(c, core, here, frame)
    UsagePrices(days) => usage_prices_page(c, core, here, frame, days)
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
  t.move(x, 450.0)
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
