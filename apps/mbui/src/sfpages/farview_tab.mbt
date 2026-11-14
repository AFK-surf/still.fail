// A chat's Farview tab drawn by this app itself (Farview's stage, fvclient/stage: the page's tiles drawn here as it
// scrolls, a field typed in here), not as the station's pictures of it: the core's `farview.view` carries the tab's
// own protocol both ways (client/core-ts/src/farview.ts), its bytes fed to the stage as they come and what the stage
// says sent by `farview.send`. Opened while it is shown, let go as it goes; each open a conversation of its own with
// the tab's host (the stage told so, it says its viewport again). A tab is one by its id (`browser:fv_…`, the screens'
// list saying `farview` of it).

///|
/// Whether screen `screen` is a Farview tab, which this app draws itself.
pub fn farview_screen(screen : String) -> Bool {
  screen.has_prefix("browser:fv_")
}

///|
/// One tab's stage and the core's call that carries it (0 none open).
priv struct FarviewTab {
  stage : @stage.Stage
  view : String
  mut call : Int
  /// how many are shown now (a tab beside its chat and its page at once)
  mut shown : Int
}

///|
// kept across runs: a tab's stage stays as it was left while the app runs
let farview_tabs : Map[String, FarviewTab] = Map([])

///|
// kept across runs: only counts
let farview_views : Ref[Int] = Ref(0)

///|
fn farview_tab(src : Source, station : String, screen : String) -> FarviewTab {
  let key = station + "\n" + screen
  match farview_tabs.get(key) {
    Some(t) => t
    None => {
      farview_views.val += 1
      let view = "fv-\{farview_views.val}"
      let t = {
        stage: @stage.Stage::new(fn(bytes) {
          (src.call_bytes)("farview.send", Json::object({ "view": Json::string(view) }), bytes, @sfbase.answer_unread)
        }, forget=@ui.forget_image),
        view,
        call: 0,
        shown: 0,
      }
      farview_tabs[key] = t
      t
    }
  }
}

///|
/// The core's call opened: the host's bytes to the stage as they come, a new conversation each time it opens.
fn FarviewTab::open(self : FarviewTab, src : Source, station : String, screen : String) -> Unit {
  if self.call != 0 {
    return
  }
  let tab = self
  self.call = (src.stream)(
    "farview.view",
    Json::object({ "station": Json::string(station), "screen": Json::string(screen), "view": Json::string(self.view) }),
    None,
    fn(value, bytes) {
      match (value, bytes) {
        (Object(o), Some(b)) if o.contains("data") => tab.stage.feed(b)
        (Object(o), _) =>
          match o.get("state") {
            Some(Object(s)) =>
              match s.get("phase") {
                Some(String("live")) => tab.stage.opened()
                _ => tab.stage.closed()
              }
            _ => ()
          }
        _ => ()
      }
    },
    fn(_) {
      tab.call = 0
      tab.stage.closed()
    },
  )
}

///|
fn FarviewTab::close(self : FarviewTab, src : Source) -> Unit {
  if self.call != 0 {
    (src.cancel)(self.call)
    self.call = 0
  }
  self.stage.closed()
}

///|
/// Farview tab `screen` of `station` in `v`, filling it: its bar (back, forward, the page again, its address; while an
/// agent drives it, a line saying so with 接管) over the page drawn here. The tab is viewed while this is shown.
#callsite(autofill(loc))
pub fn farview_tab_node(v : @view.View, src : Source, station : String, screen : String, loc~ : SourceLoc) -> Unit {
  let tab = farview_tab(src, station, screen)
  v.box(made_for=loc, fn(p) {
    p.grow(Is(1.0)).min_height(Is(Some(0.0))).ground(By(fn() { @sf.theme().p.bg })) |> ignore
    tab.shown += 1
    tab.open(src, station, screen)
    p.owns(fn() {
      tab.shown -= 1
      if tab.shown == 0 {
        tab.close(src)
      }
    })
    |> ignore
    farview_bar_node(p, tab.stage)
    p.show(fn() { tab.stage.agent() }, fn(line) {
      line.row(Is(true)).gap(Is(8.0)).padding(Is((6.0, 12.0, 6.0, 12.0))).lines_up(Is(Some(Middle))).ground(By(fn() { @sf.theme().p.muted })) |> ignore
      line.box(fn(w) {
        w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(w, fn() { @sf.t("web-pages.chat.screenAgent") }, fn() { @sf.body }) |> ignore
      })
      |> ignore
      @sf.button_node(line, fn() { @sf.t("android-misc.screen.takeOver") }, fn() { tab.stage.take_over() }) |> ignore
    })
    @stage.stage_node(p, tab.stage) |> ignore
  })
  |> ignore
}

///|
/// The tab's bar: ← → ⟳ and its address, Enter going to what is typed there (an address, or words to search for).
fn farview_bar_node(p : @view.View, stage : @stage.Stage) -> Unit {
  p.box(fn(bar) {
    bar.row(Is(true)).gap(Is(4.0)).padding(Is((6.0, 8.0, 6.0, 8.0))).lines_up(Is(Some(Middle))) |> ignore
    @sf.icon_button_node(bar, "arrow-left", fn() { @sf.t("web-pages.screen.back") }, fn() { stage.back() }) |> ignore
    @sf.icon_button_node(bar, "arrow-right", fn() { @sf.t("web-pages.screen.forward") }, fn() { stage.forward() }) |> ignore
    @sf.icon_button_node(bar, "refresh", fn() { @sf.t("web-pages.screen.reloadShort") }, fn() { stage.reload() }) |> ignore
    let address = @ui.Field::new()
    bar.reacts(fn() { stage.url() }, fn(u) { address.set(u) })
    bar.box(fn(f) {
      f.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      @sf.style_node(f, fn() { farview_address })
      @ui.field(f, address, font_size=14.0, max_lines=1, enter_sends=true, ime_action=2, label=@sf.t("web-pages.screen.goUrlShort"), submitted=fn(
        t,
      ) {
        stage.go(t)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a style, read as it is
let farview_address : @ui.Style = @ui.css("px=S3 py=S2 radius=Full bg=Neutral")
