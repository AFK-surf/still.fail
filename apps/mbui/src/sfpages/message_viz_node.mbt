// A visualization a message places (an HTML file drawn as a page: sfbase's viz_page.mbt) as nodes of the window's tree,
// in its row (viz_file_of's, as nodes): the frame and document viz_page.mbt keeps, its view ui's native in the row.
// Not here yet: what it waited under brushed off as it comes in (viz_reveal): its placeholder is gone at once.

///|
/// The visualization `a` that message `ts` of chat `session` on `station` places, kept by session `key`, in `parent`
/// (viz_file_of's): its place 120 high, breathing, till its page has come and drawn itself; then the page, a fragment as
/// tall as it says, a whole page 16:9 of its width; its view ui's native, kept past its node (the chat keeps its pages
/// as it is left: viz_chat_left lets them go), one of its own for each copy drawn at once (viz_frame_of); under it the
/// ways to open it on its own (their tips in `tips`). What it cannot read, drawn by `failed` (its file's card).
fn message_viz_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  station : String,
  session : String,
  key : String,
  ts : String,
  a : Attachment,
  failed : (@view.View) -> Unit,
) -> Unit {
  let load = @sfbase.viz_load_node(parent, src, station, key, a.path, size=a.size)
  parent.pick(
    fn() {
      match load() {
        None => 0
        Some(Err(_)) => 1
        Some(Ok(_)) => 2
      }
    },
    fn(p, k) {
      match (k, @signals.untracked(load)) {
        (1, _) => failed(p)
        (2, Some(Ok((html, state)))) => viz_shown_node(p, src, tips, station, session, key, ts, a, html, state)
        _ =>
          // its place, breathing as every wait's shapes, till the page comes
          p.box(fn(w) {
            @sf.style_node(w, fn() { @sfbase.viz_wait_under })
            w.box(fn(i) {
              @sf.style_node(i, fn() { @sfbase.viz_wait })
              @sf.breathe_node(i)
            })
            |> ignore
          })
          |> ignore
      }
    },
  )
}

///|
/// The page come (`html`, what its widget kept: `state`) of message_viz_node's, and the ways under it.
fn viz_shown_node(
  parent : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  station : String,
  session : String,
  key : String,
  ts : String,
  a : Attachment,
  html : String,
  state : Json?,
) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(b, fn() { @sfbase.viz_file_box })
    let place = "chat/" + station + ":" + session + "/" + ts + "/" + a.path
    // (its node's own: a view to each node drawing it, the same one again for the node that comes after it)
    let owner = -(b.id().at + 1)
    let t = @sf.theme()
    let f = @sfbase.viz_frame_of(
      place,
      html,
      state,
      {
        keep: Some(fn(s) { @sfbase.viz_keep(src, station, key, a.path, s) }),
        failed: None,
        follow_up: Some(@sfbase.viz_follow_up(station, session)),
      },
      owner,
      ground=t.p.bg,
    )
    f.owner = Some(owner)
    b.owns(fn() {
      if f.owner == Some(owner) {
        f.owner = None
      }
    }) |> ignore
    // the theme told only as it changes (viz_frame's)
    b.reacts(fn() { (@sf.theme().dark, @sf.theme().p.bg, @ui.font_scale()) }, fn(now) {
      let (dark, ground, _) = now
      if @sfbase.viz_theme_news(f, dark, ground) {
        @sfbase.viz_theme_tell(f, dark, ground)
      }
    })
    // drawn: what it said of its height, or a whole page (or a fragment that says none) loaded, and its host done
    // drawing it (viz_frame's cover)
    let drawn = fn() {
      f.said.get() |> ignore
      (f.shown || (f.view.state() == 1 && (f.page || f.height == 0))) && f.view.host_done()
    }
    b.box(fn(fr) {
      if f.page {
        @sf.style_node(fr, fn() { @sfbase.viz_page_frame })
        fr.aspect(Is(1.0 / @sfbase.viz_page_ratio)) |> ignore
      } else {
        @sf.style_node(fr, fn() { viz_node_frame })
        fr.height(
          By(fn() {
            f.said.get() |> ignore
            Some((if f.height > 0 { f.height } else { @sfbase.viz_first_height }).to_double())
          }),
        )
        |> ignore
        // (as tall as it says by a move, the list's with what is round it: the height it comes to as its page says it
        // is for that word's moment, View::resizes; what was read over it does not step)
        fr.reacts(fn() { f.said.get() }, fn(_) { fr.resizes() |> ignore }, at_start=false)
      }
      let n = @ui.native(
        fr,
        f.view,
        corners=fn() {
          let r = if f.page || @signals.untracked(drawn) { 0.0 } else { @ui.tree_theme().corner(Xl) }
          (r, r, r, r)
        },
        kept=true,
      )
      @sf.style_node(n, fn() { @sfbase.viz_fill })
      // till it has drawn itself, its place as while it came (the line's grey, breathing, its corners the
      // placeholder's), over it
      fr.show(at_once=true, fn() { !drawn() }, fn(o) {
        o.over(Is(true)) |> ignore
        @sf.style_node(o, fn() { @sfbase.viz_wait_ground })
        o.box(fn(i) {
          @sf.style_node(i, fn() { @sfbase.viz_wait_fill })
          @sf.breathe_node(i)
        })
        |> ignore
      })
    })
    |> ignore
    // under the page, out of its way: the ways to open it on its own
    b.box(fn(ways) {
      @sf.style_node(ways, fn() { viz_node_ways })
      @sf.icon_button_node(
        ways,
        "expand",
        fn() { @sfbase.viz_tr("android-misc.viz.fullscreen") },
        fn() { viz_open_full(a.name, station, key, a.path, session) },
        tips~,
        size=viz_way_px,
        icon_size=14.0,
      )
      |> ignore
      @sf.icon_button_node(
        ways,
        "panel-open",
        fn() { @sfbase.viz_tr("android-misc.viz.openAside") },
        fn() { open_page(@sfbase.PreviewFile(station, key, a.path, a.name)) },
        tips~,
        size=viz_way_px,
        icon_size=14.0,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A fragment's frame: the message's width, as tall as it says.
// kept across runs: a value (no field of it changes)
let viz_node_frame : @ui.Style = @ui.css("w=Full")

///|
/// The ways under it (viz_ways'), as far apart as the room a finger's press round each needs (44 in all).
// kept across runs: a value (no field of it changes)
let viz_node_ways : @ui.Style = @ui.css("row w=Full pt=S0_5 h=S6 gap=S6 justify=JEnd")

///|
/// Each way under it: viz_way's 22.
let viz_way_px : Double = 22.0
