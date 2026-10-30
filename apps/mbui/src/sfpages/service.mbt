// A web service an agent started (a dev server, a report it serves), or a visualization it posted, as one view on
// every screen (ember web/src/Preview.tsx StationPreview, ServiceFrame, PreviewBar, Restart; PreviewStage.tsx,
// ViewportSize.tsx, PreviewLoad.tsx; Android's Preview.kt the phone's): found by its job (the `job` topic), known by
// its name, never its port; what serves its page and what it keeps is sfbase's (service_page.mbt, viz_file.mbt), its
// marks service_marks.mbt. The frame puts it where it goes: the phone's stack a page of its own under a bar with its
// way back (sfapp's service.mbt), a wide frame the chat's side panel's tab (sfdesk's service_tab.mbt).
//
// Its bar (@sf's page bar) over the page, a phone's two under it in a thumb's reach (as a phone's browser has them):
// back and forward in the page's own history, reload, how far its resources came (the `previewLoad` topic's ring;
// pressed, each of them in a panel), where it is (its name, then its path; typed, it goes there), its size, marking
// it. The page fills what is beside the bar, or is laid out at a size of
// its own (a phone's, a tablet's, a laptop's, a desktop's, one typed) on the grey of a canvas, fitted and centred, with
// its screen's corners; the ground dragged moves it, two fingers zoom it, a double tap fits it again. Its size is
// chosen in one place on every screen: the bar's size key, its choices in the presenters' panel (a sheet on a phone,
// beside the key with keyboard and mouse), with 移动页面 (a finger then moves the page in place of using it: said on the size key,
// pressed it stops) and 适应 once moved. Changing its size is now and then, so it keeps none of a phone's room under
// the page. A service being started again is said over the page, which loads anew once it is back. The size chosen is
// kept on the device (the core's prefs `previewSizes`).

///|
/// What is said where the page would be (PreviewNote): 13, muted, centred.
pub fn service_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=file_wait, fn() { c.text(words, style=note_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)

///|
/// The service's view in the box it is given (Preview.kt ServicePage, ServiceFrame): its bar, the stage. `file`: a
/// visualization's page, served from here. `close`: what closes the panel it is alone in (on the tape, its bar the
/// panel's: the × at its end, no row of the panel's own over it).
pub fn service_view(
  c : @ui.Ctx,
  src : Source,
  station : String,
  job : String,
  port : Int,
  name : String,
  restarting : Bool,
  restarts : Int,
  session : String,
  file? : FilePage? = None,
  close? : (() -> Unit)? = None,
) -> Unit {
  svc_keep.val = fn(patch) { (src.call)("prefs.set", patch, fn(_) {  }) }
  let p = service_page_for(station, job, prefs=(src.topic)("prefs", {}).value)
  p.port.set(port)
  p.name.set(name)
  p.session.set(session)
  src_now.val = src.now
  let site = service_site(src, p, file, fn(url) {
    // a link elsewhere: one of still.fail's opened here as the core says, any other handed to the system
    // (AppState.openLink), said when nothing took it (Preview.kt's leave)
    open_link_in(src, url, or_else=fn() {
      if !@ui.open_url(url) {
        toast_later(svc("android-chat.link.failed"))
      }
    })
  })
  // up again after a restart: the page loads anew
  if p.restarting.get() && !restarting {
    // (once the frame's builds are over: by the job's restart as the core says it)
    c.tell("service-reload", fn() { site.reload() })
  }
  p.restarting.set(restarting)
  page_marks_frame(p, site)
  // what marking has for the page, sent once the frame's builds are over
  if p.marks.out.length() > 0 {
    let out = p.marks.out.copy()
    p.marks.out.clear()
    p.marks.sent.set(p.marks.sent.get() + 1)
    c.tell("service/marks/\{p.marks.sent.get()}", fn() {
      for js in out {
        site.script(js)
      }
    })
  }
  // the system's back steps the page back first; at its first page it leaves (Preview.kt BackHandler(canBack))
  let (_, can_back, _, _, _) = site.page_at()
  if can_back {
    c.take_back(fn() { site.go_back() })
  }
  // (with touch, as narrow as a phone's: what drives it under it, in a thumb's reach; a row over it would be short of
  // room for what a browser keeps at hand, a press's room round each key)
  // alone in a panel (its bar the panel's): the page a card in it, round, its foot corners concentric with the
  // panel's (the user, 2026-10-28: 加点圆角)
  let at_foot = @sf.keys_at_foot(c.width)
  let stage = fn() {
    match close {
      Some(_) =>
        // (in from the panel's sides and the side its bar is not on: its corners there concentric with the panel's)
        {
          let (room, corners) = stage_in_panel(bar_at_foot=at_foot)
          let inset = if at_foot {
            @ui.style(w=Full, h=Full, px=@sf.room_of(room), pt=@sf.room_of(room))
          } else {
            @ui.style(w=Full, h=Full, px=@sf.room_of(room), pb=@sf.room_of(room))
          }
          c.box(style=inset, fn() {
            service_stage(c, p, site, name, restarting, restarts, corners~)
          })
          |> ignore
        }
      None => service_stage(c, p, site, name, restarting, restarts)
    }
  }
  if at_foot {
    stage()
    service_foot_bar(c, src, p, site, name, station, port, fixed=file is Some(_), close~)
  } else {
    service_page_bar(c, src, p, site, name, station, port, fixed=file is Some(_), close~)
    stage()
  }
}

///|
/// How far in from a panel's sides and the side its bar is not on the page stands alone in it: the nearest the theme lets
/// what lies in a corner stand (corner_fit's 4; the user, 2026-10-28: 网页边距 4px 差不多了).
let stage_in_panel_room : Double = @sf.corner_fit.near

///|
/// Where the page alone in a panel stands in from its sides and the side its bar is not on (stage_in_panel_room), and
/// its corners (top left, then round it): those away from its bar in the panel's corners there (pane_round: the
/// screen's at its edges, the system's at its foot, the tape's elsewhere; none beside the system's column) concentric
/// with them so far in, however round that makes them (an iPhone Duo's foot corner round its action: past the ladder's
/// most, as the panel's own is); those under its bar, in no corner of the panel's, the tape's so far in.
fn stage_in_panel(bar_at_foot~ : Bool) -> (Double, FixedArray[@ui.CornerOf]) {
  let r = match @sf.pane_round.val {
    Some(k) => @sf.corner_radii(k)
    None => FixedArray::make(4, @sf.tape_corner)
  }
  let room = stage_in_panel_room
  let alone = @ui.concentric(@sf.tape_corner, room)
  (
    room,
    FixedArray::makei(4, fn(i) {
      if (i < 2) == bar_at_foot && r[i] > room {
        @ui.CornerOf::Own(@ui.concentric(r[i], room))
      } else {
        Own(alone)
      }
    }),
  )
}

///|
/// What its bars know of the page this frame (its address said on the log as it moves, a tap on the address typing
/// there): where it is, whether it can go back and forward, the address's field and whether it is typed in, its pill.
priv struct BarNow {
  at : String
  can_back : Bool
  can_forward : Bool
  field_key : String
  editing : Bool
  pill : Int
}

///|
fn bar_now(c : @ui.Ctx, p : ServicePage, site : @ui.NativeView, fixed : Bool) -> BarNow {
  let (at, can_back, can_forward, _, _) = site.page_at()
  let field_key = "service/address/" + service_key(p.station, p.job)
  let editing = c.editor_focused(field_key)
  // (said on the log as the page moves: e2e/flows check where it went)
  if at != p.logged_path.get() {
    p.logged_path.set(at)
    @ui.log("service: at \{at}")
  }
  // a tap anywhere on the address types there (the I-beam over it)
  let pill = c.id("service/address")
  if !fixed {
    c.cursor(pill, IBeam)
  }
  if !editing && !fixed && c.clicked(pill) {
    c.focus_editor(field_key)
  }
  { at, can_back, can_forward, field_key, editing, pill }
}

///|
/// Back, forward, reload, how far its resources came, where it is (typed to go elsewhere), its size, marking it
/// (PreviewBar): over the page, in a row.
fn service_page_bar(
  c : @ui.Ctx,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  station : String,
  port : Int,
  fixed? : Bool = false,
  close? : (() -> Unit)? = None,
) -> Unit {
  let n = bar_now(c, p, site, fixed)
  // (the bar of a panel it is alone in, its top: its first and last keys concentric with the panel's corners)
  let corners = match (close, @sf.pane_radii()) {
    (Some(_), Some(k)) => Some((k[0], k[1]))
    _ => None
  }
  @sf.page_bar(c, corners~, fn() {
    // (short of room, as the address keeps its least (@sf.bar_field) and marking's words want four characters at
    // least: how far it came leaves the bar first, then its size, then reload, each offered in its ⋯ at its end;
    // never back and forward, nor the address's place)
    let gone : Array[@sf.MenuItem?] = []
    let more = c.id("service/more")
    // (back and forward stay, whatever the room: a browser's own)
    back_forward(c, site, n)
    let reload_slot = c.id("service/reload-slot")
    c.box(id=reload_slot, taps=false, drop=bar_drop_reload, fn() { reload_key(c, site) }) |> ignore
    if c.left_out(reload_slot) {
      gone.push(Some(bar_line(@sf.t("web-main.preview.reload"), "refresh", disabled=false, on_press=fn() { site.reload() })))
    }
    let load = load_of(src, station, port, fixed)
    if load is Some(Object(_)) {
      let slot = c.id("service/load-slot")
      c.box(id=slot, taps=false, drop=bar_drop_load, fn() { load_key(c, src, station, port, load) }) |> ignore
      if c.left_out(slot) {
        gone.push(Some(bar_line(load_label(load), "", disabled=false, on_press=fn() { service_load_panel(src, station, port, Of(more)) })))
      }
    }
    address_or_marking(c, src, p, site, name, fixed, n)
    let size_slot = c.id("service/size-slot")
    c.box(id=size_slot, taps=false, drop=bar_drop_size, fn() { size_key_of(c, p) }) |> ignore
    if c.left_out(size_slot) {
      gone.push(
        Some(
          bar_line(size_said(p), if p.moving.get() { "move" } else { "devices" }, disabled=false, on_press=fn() {
            if p.moving.get() {
              p.moving.set(false)
            } else {
              service_sizes_panel(service_key(p.station, p.job), Of(more))
            }
          }),
        ),
      )
    }
    mark_key_of(c, p, site)
    // what left it, in its ⋯ at its end (there only while something did)
    c.box(more=true, fn() {
      if @sf.bar_key(c, "service/more", "more", @sf.t("web-main.menu.more")) {
        @sf.menu(gone, from=Of(more))
      }
    })
    |> ignore
    panel_close_key(c, close)
  })
  |> ignore
}

///|
/// The × of the panel the page is alone in, at its bar's end (service_view's `close`).
fn panel_close_key(c : @ui.Ctx, close : (() -> Unit)?) -> Unit {
  match close {
    Some(f) =>
      if @sf.bar_key(c, "service/panel-close", "close", @sf.t("web-pages.chat.closePanel")) {
        f()
      }
    None => ()
  }
}

///|
/// The same under the page, in a thumb's reach, in one row (as a phone's browser has it: Safari's compact bar at the
/// foot): back and forward, where it is with reload at its end (marking's say in its place while marking) and how far
/// the page came along its foot, marking it, its ⋯ (its size, how far each of its resources came); while a finger moves
/// the page, the size key in the ⋯'s place, a press stopping it. In a panel of its own (the tape's) the first and the
/// last keys concentric with its foot corners (@sf.foot_capsule).
fn service_foot_bar(
  c : @ui.Ctx,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  station : String,
  port : Int,
  fixed? : Bool = false,
  close? : (() -> Unit)? = None,
) -> Unit {
  let n = bar_now(c, p, site, fixed)
  let load = load_of(src, station, port, fixed)
  // (each key in the row's middle, as far over its foot as its room leaves under it)
  let under = (@ui.room_least() - @sf.theme().bars.key) / 2.0
  let (left, right, foot) = @sf.foot_capsule(@sf.theme().bars.key, foot_keys_in, under)
  let lifted = dmax(0.0, foot - under)
  let row = foot_row_look.then(
    @ui.style(
      h=Fixed(@ui.room_least() + lifted),
      pl=@sf.room_of(left),
      pr=@sf.room_of(right),
      pb=@sf.room_of(lifted),
      gap=@sf.keys_gap(size=@sf.theme().bars.key),
    ),
  )
  c.box(style=row, fn() {
    back_forward(c, site, n)
    address_or_marking(c, src, p, site, name, fixed, n, end=Some(fn() { reload_key(c, site) }), part=load_part(load))
    mark_key_of(c, p, site)
    if p.moving.get() {
      size_key_of(c, p)
    } else {
      foot_more(c, src, p, station, port, load)
    }
    panel_close_key(c, close)
  })
  |> ignore
}

///|
/// How far the page came, along the address's foot while its resources come (the accent), all of it red once one of
/// them failed; none once all came.
fn load_part(load : Json?) -> (Double, @ui.Color)? {
  if !(load is Some(Object(_))) {
    return None
  }
  if number(load, "failed") > 0.0 {
    Some((1.0, Danger))
  } else {
    let k = number(load, "percent") / 100.0
    if k >= 1.0 {
      None
    } else {
      Some((dmax(0.0, k), Accent))
    }
  }
}

///|
/// The foot bar's ⋯: its size (its choices in the presenters' sheet), how far each of its resources came (a sheet).
fn foot_more(c : @ui.Ctx, src : Source, p : ServicePage, station : String, port : Int, load : Json?) -> Unit {
  let more = c.id("service/more")
  if @sf.bar_key(c, "service/more", "more", @sf.t("web-main.menu.more")) {
    let lines : Array[@sf.MenuItem?] = [
      Some(bar_line(size_said(p), "devices", disabled=false, on_press=fn() {
        service_sizes_panel(service_key(p.station, p.job), Of(more))
      })),
    ]
    if load is Some(Object(_)) {
      lines.push(Some(bar_line(load_label(load), "", disabled=false, on_press=fn() { service_load_panel(src, station, port, Of(more)) })))
    }
    @sf.menu(lines, from=Of(more))
  }
}

///|
/// The bar under the page (service_foot_bar): on the page's ground (none of its own: what parts it from the page is
/// where it ends), a press's room high (@ui.room_least) over what lifts its keys into a panel's foot corners, its keys
/// keys_gap apart, the address taking what they leave (160 at least: a phone's 360 holds it, its four keys and their
/// rooms just so).
// kept across runs: a value (no field of it changes)
let foot_row_look : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// How far in its first and last keys stand at its sides where no corner of a panel's is to be followed: as a page
/// bar's, 8.
let foot_keys_in : Double = 8.0

///|
/// Back and forward in the page's own history.
fn back_forward(c : @ui.Ctx, site : @ui.NativeView, n : BarNow) -> Unit {
  if @sf.bar_key(c, "service/go-back", "arrow-left", @sf.t("web-main.keymap.nav.back"), enabled=n.can_back) {
    site.go_back()
  }
  if @sf.bar_key(c, "service/go-forward", "arrow-right", @sf.t("web-main.keymap.nav.forward"), enabled=n.can_forward) {
    site.go_forward()
  }
}

///|
fn reload_key(c : @ui.Ctx, site : @ui.NativeView) -> Unit {
  if @sf.bar_key(c, "service/reload", "refresh", @sf.t("web-main.preview.reload")) {
    site.reload()
  }
}

///|
/// How far the page's resources came (the `previewLoad` topic); a visualization's page has none (served from here).
fn load_of(src : Source, station : String, port : Int, fixed : Bool) -> Json? {
  if fixed {
    None
  } else {
    (src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value
  }
}

///|
/// How far the page's resources came (PreviewLoad.kt): a ring, red with one failed; pressed, each of them in a panel.
fn load_key(c : @ui.Ctx, src : Source, station : String, port : Int, load : Json?) -> Unit {
  let t = @sf.theme()
  let ring = c.id("service/load")
  if c.clicked(ring) {
    service_load_panel(src, station, port, Of(ring))
  }
  let color = if number(load, "failed") > 0.0 { t.p.red } else { t.p.muted }
  // (PreviewLoad.kt: how far, in words, to a screen reader)
  c.box(style=ring_box.then(@ui.style(w=Fixed(t.bars.key), h=Fixed(t.bars.key))), id=ring, label=load_label(load), fn() {
    @sf.progress_ring(c, 20.0, number(load, "percent") / 100.0, color) |> ignore
  })
  |> ignore
}

///|
/// Where it is (previewAddress: its name, then its path, typed to go elsewhere), or what marking says in its place;
/// `end` and `part` as @sf.bar_field has them (reload at its end, how far the page came along its foot).
fn address_or_marking(
  c : @ui.Ctx,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  fixed : Bool,
  n : BarNow,
  end? : (() -> Unit)? = None,
  part? : (Double, @ui.Color)? = None,
) -> Unit {
  let t = @sf.theme()
  let markable = p.session.get() != ""
  if markable && (p.marks.marking.get() || p.marks.marks.length() > 0) {
    c.box(style=mark_mode_place, keep=true, fn() { page_mark_mode(c, src, p, site) }) |> ignore
    return
  }
  @sf.bar_field(c, n.pill, n.editing, end~, part~, fn() {
    @sf.icon(c, "web", size=t.bars.icon, color=t.p.muted) |> ignore
    if fixed {
      // nowhere else to go (a visualization): the address is only its name
      c.box(style=file_name_box, fn() { c.text(name, style=file_name_words) |> ignore }) |> ignore
      return
    }
    c.text(name, size=t.t.meta, weight=500, color=t.p.text, wrap=false) |> ignore
    // where it went is what the bar says, unless someone is typing there
    if !n.editing && n.at != p.shown_path.get() {
      p.shown_path.set(n.at)
      p.address.set(n.at)
    }
    let r = c.editor(
      n.field_key,
      font_size=t.t.ui,
      max_lines=1,
      plain=true,
      ime_action=@hostapi.ime_action_go,
      color=if n.editing { t.p.text } else { t.p.muted },
      caret_color=t.p.accent,
      field=p.address,
    )
    match r.submitted {
      Some(typed) => {
        let path = typed.trim().to_owned()
        site.load(if path.has_prefix("/") { path } else { "/" + path })
        c.blur()
      }
      None => ()
    }
  })
}

///|
/// What the size key says: its size, or, while a finger moves the page, that a press stops it.
fn size_said(p : ServicePage) -> String {
  if p.moving.get() {
    svc("android-chat.preview.moveOff")
  } else {
    svc("android-chat.preview.size.title")
  }
}

///|
/// Its size, on every screen: what it is laid out at (none: as the room is), its choices pressed open (the presenters'
/// panel: a sheet on a phone, beside it with keyboard and mouse); while a finger moves the page in place of using it,
/// said here, in the accent with the move icon, and pressed it lets go of moving at once.
fn size_key_of(c : @ui.Ctx, p : ServicePage) -> Unit {
  let t = @sf.theme()
  let sid = c.id("service/size")
  if c.clicked(sid) {
    if p.moving.get() {
      p.moving.set(false)
    } else {
      service_sizes_panel(service_key(p.station, p.job), Of(sid))
    }
  }
  let sb = c.box(style=if p.moving.get() { size_key_moving } else if p.viewport.get() is Some(_) { size_key_sized } else { size_key }, id=sid, fn() {
    @sf.icon(c, if p.moving.get() { "move" } else { "devices" }, size=bar_icon_size, color=if p.moving.get() { t.p.accent_text } else { t.p.text }) |> ignore
    // (its size in words, as its panel says it too: short of room they leave it, its icon staying)
    match p.viewport.get() {
      Some(v) =>
        c.box(drop=bar_drop_size_words, fn() {
          c.text(dims(v.width, v.height), style=if p.moving.get() { size_key_words_moving } else { size_key_words }) |> ignore
        })
        |> ignore
      None => ()
    }
  })
  c.semantics(sb, Button, id=sid, label=size_said(p))
  @sf.tip(c, "service/size/tip", sid, size_said(p))
}

///|
/// Marking the page for the chat's agent (a page with no chat to put it in has none).
fn mark_key_of(c : @ui.Ctx, p : ServicePage, site : @ui.NativeView) -> Unit {
  if p.session.get() != "" && page_mark_key(c, p.marks.marking.get()) {
    page_marks_toggle(p, site)
  }
}

///|
/// The size key (web ViewportSize.tsx trigger): 28 high, round, 6 in, as wide as high at least (its icon alone in its
/// middle, as the bar's other keys); sized, on the chip's ground with its size (12) 5 after the icon, 8 in; moving the
/// page, on the accent's 14% in the accent's ink (as the mark key picking).
// kept across runs: a value (no field of it changes)
let size_key : @ui.Style = @ui.css("row h=S7 min_w=S7 radius=Full px=S1_5 gap=S1_25 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let size_key_sized : @ui.Style = size_key.then(@ui.css("px=S2 bg=Faint"))

///|
// kept across runs: a value (no field of it changes)
let size_key_moving : @ui.Style = size_key_sized.then(@ui.style(bg=@sf.mark_key_on))

///|
// kept across runs: a value (no field of it changes)
let size_key_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let size_key_words_moving : @ui.TextStyle = size_key_words.then(@ui.text_style(color=AccentText))

///|
/// How far its resources came: a ring in a key's room.
// kept across runs: a value (no field of it changes)
let ring_box : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// What of the page's bar leaves it first where it is short of room, each to its ⋯: how far its resources came, then
/// its size (its words first, its key keeping its icon: chosen now and then), then reload; back and forward never, as
/// a browser's own (the user, 2026-10-27: 前进后退不能省吧).
let bar_drop_load : Int = 1

///|
let bar_drop_size_words : Int = 2

///|
let bar_drop_size : Int = 3

///|
let bar_drop_reload : Int = 4

///|
/// A line of the bar's ⋯: what a key that left the bar does, `on_press` once it is chosen.
fn bar_line(label : String, icon : String, disabled~ : Bool, on_press~ : () -> Unit) -> @sf.MenuItem {
  @sf.menu_item_of(label, on_press, icon~, disabled~)
}

///|
/// `390 × 844` (自动 for no height).
fn dims(w : Int, h : Int?) -> String {
  "\{w} × " +
  (match h {
    Some(x) => x.to_string()
    None => svc("android-chat.preview.auto")
  })
}

///|
/// A double tap on the ground (Preview.kt Stage): each tap shorter than this, moving less than `stage_tap_slop`, the
/// second this soon after the first.
let stage_tap_ms : Double = 300.0

///|
let stage_double_ms : Double = 350.0

///|
let stage_tap_slop : Double = 12.0

///|
/// The page's corners, as its screen's (Preview.kt cornerOf): a phone's round, a tablet's less, a desktop's all but
/// square.
fn corner_of(width : Int, scale : Double) -> Double {
  if width <= 600 {
    44.0
  } else if width < 1024 {
    24.0
  } else {
    5.0 / scale
  }
}

///|
/// All of the room for the page, or — laid out at a size of its own — a canvas with the page on it (Preview.kt Stage,
/// PreviewStage.tsx): fitted (100% at most) and centred, 16 round it, its screen's corners; then the ground dragged (or,
/// in the toolbar's moving mode, the page), two fingers anywhere zoom and move it (0.05 to 4 times), a double tap on
/// the ground fits it again.
fn service_stage(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  restarting : Bool,
  restarts : Int,
  corners? : FixedArray[@ui.CornerOf],
) -> Unit {
  let t = @sf.theme()
  let ground = @sf.mix(t.p.chip, 0.55, t.p.card)
  let stage = c.id("service/stage")
  // (the page's: a press on it is the page's, no control of ours)
  c.cursor(stage, Arrow)
  // who takes a finger on the page: all its own fitted; a sized page's two fingers the canvas's, all of it while it is
  // moved by a finger
  let touch = match p.viewport.get() {
    None => @ui.Touch::All
    Some(_) if p.moving.get() => @ui.Touch::Through
    Some(_) => @ui.Touch::PinchOut
  }
  // (once the frame's builds are over, as the last of them has it; told the host only when it changes)
  c.after_build("service-touch", fn() { site.touch(touch) })
  // (round only alone in a panel: a style given, its box is one more the spacing rules see)
  let round = match corners {
    Some(k) => Some(@ui.style(radius=@sf.corners_radius(k)))
    None => None
  }
  // (the page's own corners each the stage's, where it fills it)
  let r = match corners {
    Some(k) => {
      let r = @sf.corner_radii(k)
      Some((r[0], r[1], r[2], r[3]))
    }
    None => None
  }
  // (a page filling it, once drawn, on nothing of the stage's: a ground under it showed along its edges, where the
  // host's cut and the hole's meet within a pixel, a line round the page)
  let under = match p.viewport.get() {
    Some(_) => Some(ground)
    None => if site.shown() { None } else { Some(t.p.card) }
  }
  c.box(w=Fill(1.0), h=Fill(1.0), style?=round, bg?=under, clip=true, id=stage, fn() {
    // (the stage's place as this frame lays it out: read back, built again once it is)
    let placed = match (p.viewport.get(), c.laid_size(stage)) {
      (Some(v), Some((sw, sh))) => {
        let w = v.width.to_double()
        // a page of no height of its own: as high as the stage leaves it at the scale its width is fitted at
        let h = match v.height {
          Some(x) => x.to_double()
          None => {
            let fitted = dmax(stage_min_scale, (dmin(1.0, (sw - 32.0) / w) * 1000.0).floor() / 1000.0)
            dmax(240.0, ((sh - 32.0) / fitted).floor())
          }
        }
        p.view.boxed(sw, sh)
        p.view.natural(w, h)
        match p.view.rect() {
          // (fitted: on whole points, as Preview.kt centres it)
          Some((x, y, _, _)) if p.view.fitted => Some(({ x: x.round(), y: y.round(), scale: p.view.scale, w, h } : Placed))
          Some((x, y, _, _)) => Some(({ x, y, scale: p.view.scale, w, h } : Placed))
          None => None
        }
      }
      _ => None
    }
    p.placed.set(placed)
    match placed {
      Some(pl) => {
        let corner = corner_of(p.viewport.get().map(fn(v) { v.width }).unwrap_or(0), pl.scale)
        // (told once the frame's builds are over, as the last laid the stage out)
        c.after_build("scale", fn() { site.set_scale(pl.scale) })
        // its white, its shadow and its screen's corners under it; the page where they are
        c.layer(fn() {
          c.box(
            w=Px(pl.w * pl.scale),
            h=Px(pl.h * pl.scale),
            tx=pl.x,
            ty=pl.y,
            radius=corner * pl.scale,
            // (Preview.kt: the page's view at an elevation of 6)
            shadow=@sf.bubble_raised.sigma,
            shadow_y=@sf.bubble_raised.dy,
            shadow_color=@sf.bubble_raised.color,
            bg=0xFFFFFFFFL,
            fn() {  },
          )
          |> ignore
        })
        |> ignore
        // (its screen's corners the page's own too: the host cuts it round, as Preview.kt's place() does)
        c.layer(fn() {
          c.native(site, content=Some((pl.x, pl.y, pl.w * pl.scale, pl.h * pl.scale)), radius=corner * pl.scale)
          |> ignore
        })
        |> ignore
      }
      None =>
        if p.viewport.get() is None {
          c.after_build("scale", fn() { site.set_scale(1.0) })
          c.native(site, corners?=r) |> ignore
        }
    }
    // the marks over the page, where it is drawn
    if p.session.get() != "" && p.marks.marks.length() > 0 {
      match (placed, c.laid_size(stage)) {
        (Some(pl), Some((sw, _))) => page_marks_over(c, p, site, pl.x, pl.y, pl.w, pl.scale, sw)
        (None, Some((sw, _))) => page_marks_over(c, p, site, 0.0, 0.0, sw, 1.0, sw)
        _ => ()
      }
    }
    if restarting {
      c.layer(fn() { c.box(style=service_restart_room, fn() { service_restart(c, name, restarts) }) |> ignore })
      |> ignore
    }
  })
  |> ignore
  match placed_origin(c, stage) {
    Some((sx, sy)) => stage_gestures(c, p, stage, sx, sy)
    None => ()
  }
}

///|
/// The stage's top left on the screen, as this frame laid it out.
fn placed_origin(c : @ui.Ctx, stage : Int) -> (Double, Double)? {
  match c.laid_rect(stage) {
    Some((x, y, _, _)) => Some((x, y))
    None => None
  }
}

///|
/// The stage's fingers on a sized page (Preview.kt Stage): the ground's (or, moving it, the page's) one finger moves
/// the page, two anywhere zoom and move it, a double tap on the ground fits it again. What the canvas is given of a
/// finger on the page (two fingers; all, moving it) is its to handle, as the ground's is.
fn stage_gestures(c : @ui.Ctx, p : ServicePage, stage : Int, sx : Double, sy : Double) -> Unit {
  let pl = match p.placed.get() {
    Some(pl) => pl
    None => {
      p.hold.set(None)
      return
    }
  }
  let (px, py, _) = c.pointer()
  if c.pressed(stage) {
    let at = match c.second_pointer() {
      Some((x2, y2)) => [(px - sx, py - sy), (x2 - sx, y2 - sy)]
      None => [(px - sx, py - sy)]
    }
    match p.hold.get() {
      None => {
        let dx = c.press_x - sx
        let dy = c.press_y - sy
        let on_page = dx >= pl.x && dx <= pl.x + pl.w * pl.scale && dy >= pl.y && dy <= pl.y + pl.h * pl.scale
        p.hold.set(Some({
          was: @signals.signal(if at.length() == 1 { [(dx, dy)] } else { at }),
          travelled: @signals.signal(0.0, same=fn(a, b) { a == b }),
          down_at: c.pointer_at(),
          on_page,
        }))
        if at.length() == 1 && (at[0].0 != dx || at[0].1 != dy) {
          stage_moved(p, at)
        }
      }
      Some(_) => stage_moved(p, at)
    }
  } else {
    // let go (down and up between two frames: a tap the frames never saw held, taken all the same)
    let (on_page, travelled, down_at) = match p.hold.get() {
      Some(h) => (h.on_page, h.travelled.get(), h.down_at)
      None if c.clicked(stage) => {
        let dx = c.press_x - sx
        let dy = c.press_y - sy
        (dx >= pl.x && dx <= pl.x + pl.w * pl.scale && dy >= pl.y && dy <= pl.y + pl.h * pl.scale, 0.0, c.press_at)
      }
      None => return
    }
    p.hold.set(None)
    // a double tap on the ground fits it again
    let now = c.pointer_at()
    if !on_page && travelled < stage_tap_slop && now - down_at < stage_tap_ms {
      if now - p.tapped_at.get() < stage_double_ms {
        p.view.fit_now()
        p.tapped_at.set(-1.0e9)
      } else {
        p.tapped_at.set(now)
      }
    }
  }
}

///|
/// The fingers now at `at` (from the stage's top left): one moves the page as far as it went, two zoom it by how far
/// apart they went about the point between them, moving it as that point did (Preview.kt pinch); a finger come or gone,
/// from there on.
fn stage_moved(p : ServicePage, at : Array[(Double, Double)]) -> Unit {
  let h = match p.hold.get() {
    Some(h) => h
    None => return
  }
  if at.length() != h.was.get().length() {
    h.was.set(at)
    return
  }
  if at.length() == 1 {
    let (x0, y0) = h.was.get()[0]
    let (x1, y1) = at[0]
    h.travelled.set(h.travelled.get() + ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt())
    p.view.pan(x1 - x0, y1 - y0)
  } else {
    let mid = fn(ps : Array[(Double, Double)]) { ((ps[0].0 + ps[1].0) / 2.0, (ps[0].1 + ps[1].1) / 2.0) }
    let apart = fn(ps : Array[(Double, Double)]) {
      let dx = ps[0].0 - ps[1].0
      let dy = ps[0].1 - ps[1].1
      dmax(1.0, (dx * dx + dy * dy).sqrt())
    }
    let (m0x, m0y) = mid(h.was.get())
    let (m1x, m1y) = mid(at)
    p.view.transform(m0x, m0y, apart(at) / apart(h.was.get()), m1x - m0x, m1y - m0y)
  }
  h.was.set(at)
}

///|
/// Over the page while its service starts again (Restart): an amber dot, its name 正在重启, and how often so far.
fn service_restart(c : @ui.Ctx, name : String, restarts : Int) -> Unit {
  c.box(style=service_restart_pill, glass=@sf.glass_floating(), fn() {
    c.box(style=service_restart_dot, fn() {  }) |> ignore
    c.box(style=service_restart_words, fn() {
      c.text(@sf.t("web-main.preview.restarting", args=[("name", name)]), style=service_restart_title) |> ignore
      c.text(
        if restarts > 0 {
          @sf.t("web-main.preview.restartAgain", args=[("n", restarts.to_string())])
        } else {
          @sf.t("web-main.preview.restartNote")
        },
        style=service_restart_note,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let service_restart_pill : @ui.Style = @ui.css("row pl=S4 pr=S4_5 py=S2_5 gap=S3 radius=Full shadow=Lg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let service_restart_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Warn")

///|
// kept across runs: a value (no field of it changes)
let service_restart_words : @ui.Style = @ui.css("gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let service_restart_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let service_restart_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The preset a size is (either way round), if it is one.
fn preset_of(v : Viewport?) -> String? {
  match v {
    Some({ width, height: Some(h) }) =>
      match svc_presets.iter().find_first(fn(p) { (p.1 == width && p.2 == h) || (p.1 == h && p.2 == width) }) {
        Some(p) => Some(p.0)
        None => None
      }
    _ => None
  }
}

///|
/// All the sizes (ViewportSize.tsx's panel), the same on every screen: as big as the preview, the presets, 自定义; a
/// page laid out at a size of its own moved by a finger in place of used (移动页面: what the toolbar under the page had)
/// and fitted again once moved or zoomed. Its rows a row's room, its words the theme's (Rows, its ui and meta: a touch
/// device's a finger's and a size up), a sheet on a phone and beside the size key with keyboard and mouse (the presenters').
fn page_sizes(c : @ui.Ctx, key : String, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let r = t.rows
  let p = service_pages.get(key)
  let current = match p {
    Some(x) => x.viewport.get()
    None => None
  }
  let preset = preset_of(current)
  c.box(style=sizes_room, fn() {
    let option = fn(k : String, checked : Bool, name : String, note : String, v : Viewport?) {
      let id = c.id("service/size/" + k)
      if c.clicked(id) {
        match p {
          Some(x) => {
            // a size chosen is fitted anew; the page no longer moved by a finger
            x.moving.set(false)
            x.view.fit_now()
            x.viewport.set(v)
            keep_size(key, v)
          }
          None => ()
        }
        close()
      }
      c.box(style=size_option.then(@sf.panel_row_in()).then(@ui.style(min_h=Fixed(@sf.theme().items.least))), id~, fn() {
        c.box(style=@ui.style(w=Fixed(r.check), align=ACenter), fn() {
          if checked {
            @sf.icon(c, "check", size=size_check_icon, color=t.p.accent) |> ignore
          }
        })
        |> ignore
        c.box(style=custom_name, fn() { c.text(name, style=if checked { r.title.then(size_name_on) } else { r.title }) |> ignore })
        |> ignore
        c.text(note, style=r.note) |> ignore
        // the row clickable over its clip
        @motion.ripple(c, id, size_option_corner)
      })
      |> ignore
    }
    option("fit", current is None, svc("android-chat.preview.fit"), svc("android-chat.preview.fit.note"), None)
    for pr in svc_presets {
      option(
        pr.0,
        preset == Some(pr.0),
        svc("android-chat.preview.preset." + pr.0),
        dims(pr.1, Some(pr.2)),
        Some({ width: pr.1, height: Some(pr.2) }),
      )
    }
    c.box(style=custom_gap, fn() {  }) |> ignore
    match p {
      Some(x) => {
        custom_size(c, x, key)
        // laid out at a size of its own: moved by a finger, fitted again (the toolbar's tools that were)
        if x.viewport.get() is Some(_) {
          c.box(style=sizes_tools, fn() {
            let moving = @sf.switch_row(
              c,
              "service/move",
              svc("android-chat.preview.move"),
              x.moving.get(),
              note=svc("android-chat.preview.move.note"),
            )
            if moving != x.moving.get() {
              x.moving.set(moving)
              // (on: what it changes is the page under the panel, so the panel goes)
              if moving {
                close()
              }
            }
            if !x.view.fitted &&
              @sf.button(c, svc("android-chat.preview.fitView"), key="service/fit-view", w=Fill(1.0)) {
              x.view.fit_now()
              x.moving.set(false)
              close()
            }
          })
          |> ignore
        }
      }
      None => ()
    }
  })
  |> ignore
}

///|
/// The sizes' room (under them the presenter's foot); a size's row: at the panel's rows' edge, its check's column on
/// its words' line (@sf.panel_row_in), 8 apart, concentric with the panel; its name a row's title (500 chosen), its
/// note a row's note (Rows); the check 16.
// kept across runs: a value (no field of it changes)
let sizes_room : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let size_option : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2 radius=Inner align=ACenter")

///|
let size_option_corner : Double = 12.0

///|
let size_check_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let size_name_on : @ui.TextStyle = @ui.text_style(weight=Medium)

///|
/// Moving and fitting under 自定义, 12 under it, 8 apart.
// kept across runs: a value (no field of it changes)
let sizes_tools : @ui.Style = @ui.css("w=Full pt=S3 px=S2_5 gap=S2")

///|
/// The turn key's icon (ViewportSize.tsx: 15).
let custom_turn_icon : Double = 15.0

///|
/// 自定义's row (ViewportSize.tsx CustomSize): 10 under the sizes, its name where the sizes' names are (past a column
/// as wide as their check), its two fields the theme's rows' (Rows), 4 apart with × between them, the turn key 24
/// round (faint when there is nothing to turn).
// kept across runs: a value (no field of it changes)
let custom_gap : @ui.Style = @ui.css("h=S2_5")

///|
// kept across runs: a value (no field of it changes)
let custom_row : @ui.Style = @ui.css("row w=Full pl=S2_5 pr=S1 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let custom_fields : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let custom_name : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let custom_field : @ui.Style = @ui.style(radius=@sf.custom_field_r, bg=Faint, px=S1_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let custom_by : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_turn : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let custom_turn_off : @ui.Style = custom_turn.then(@ui.css("opacity=O35"))

///|
/// Any size, typed (Preview.kt CustomSize): the width, and the height (empty: as high as the preview leaves it), each
/// put once its field is let go of or done; turned by the button. 72 × 36 fields on the chip's ground.
fn custom_size(c : @ui.Ctx, p : ServicePage, key : String) -> Unit {
  let t = @sf.theme()
  let r = t.rows
  let wk = "service/custom-w"
  let hk = "service/custom-h"
  let typing = c.editor_focused(wk) || c.editor_focused(hk)
  // what it is, unless someone is typing there
  if !typing {
    let (w, h) = match p.viewport.get() {
      Some(v) => (v.width.to_string(), v.height.map(fn(x) { x.to_string() }).unwrap_or(""))
      None => ("", "")
    }
    if p.custom_w.text() != w {
      p.custom_w.set(w)
    }
    if p.custom_h.text() != h {
      p.custom_h.set(h)
    }
  }
  let commit = fn() {
    let ws = p.custom_w.text()
    let hs = p.custom_h.text()
    let width = size_of(ws)
    let height = if hs == "" { Some(None) } else { size_of(hs).map(fn(x) { Some(x) }) }
    match (width, height) {
      (Some(w), Some(h)) => {
        let v : Viewport = { width: clamp_size(w), height: h.map(clamp_size) }
        let same = match p.viewport.get() {
          Some(x) => x.width == w && x.height == h
          None => false
        }
        if !same {
          p.moving.set(false)
          p.view.fit_now()
          p.viewport.set(Some(v))
          keep_size(key, Some(v))
        }
      }
      _ => ()
    }
  }
  // put once let go of (it was being typed in the frame before)
  if p.custom_typing.get() && !typing {
    commit()
  }
  p.custom_typing.set(typing)
  c.box(style=custom_row.then(@ui.style(min_h=Fixed(@sf.theme().items.least))), fn() {
    // (its name where the sizes' names are: past a column as wide as their check)
    c.box(style=@ui.style(w=Fixed(r.check)), fn() {  }) |> ignore
    c.box(style=custom_name, fn() { c.text(svc("android-chat.preview.custom"), style=r.title) |> ignore }) |> ignore
    let field = fn(k : String, f : @ui.Field, hint : String) {
      c.box(style=custom_field.then(@ui.style(w=r.field_w, h=r.field_h)), fn() {
        let r = c.editor(
          k,
          font_size=t.t.ui,
          max_lines=1,
          plain=true,
          ime_action=@hostapi.ime_action_number,
          placeholder=hint,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          field=f,
        )
        let digits = size_digits(r.text)
        if digits != r.text {
          f.set(digits)
        }
        match r.submitted {
          Some(_) => {
            commit()
            c.blur()
          }
          None => ()
        }
      })
      |> ignore
    }
    c.box(style=custom_fields, fn() {
      field(wk, p.custom_w, svc("android-chat.preview.width"))
      c.text("×", style=custom_by) |> ignore
      field(hk, p.custom_h, svc("android-chat.preview.auto"))
    })
    |> ignore
    let turnable = match p.viewport.get() {
      Some(v) => v.height is Some(_)
      None => false
    }
    let turn = c.id("service/custom-turn")
    if turnable && c.clicked(turn) {
      match p.viewport.get() {
        Some({ width, height: Some(h) }) => {
          let v : Viewport = { width: h, height: Some(width) }
          p.view.fit_now()
          p.viewport.set(Some(v))
          keep_size(key, Some(v))
        }
        _ => ()
      }
    }
    let tb = c.box(style=if turnable { custom_turn } else { custom_turn_off }, id=if turnable { turn } else { 0 }, fn() {
      @sf.icon(c, "landscape", size=custom_turn_icon, color=t.p.text) |> ignore
    })
    // (named, and said on hover: ViewportSize.tsx's Tip)
    c.semantics(tb, Button, id=if turnable { turn } else { 0 }, label=@sf.t("web-main.viewport.turn"), disabled=!turnable)
    if turnable {
      @sf.tip(c, "service/custom-turn/tip", turn, @sf.t("web-main.viewport.turn"))
    }
  })
  |> ignore
}

///|
/// How the page's resources came, each of them (PreviewLoad.tsx's list): as tall as they are, scrolled past the web's
/// most (Preview.css.ts loadList: min(320px, 55vh)) on every screen.
fn load_list(c : @ui.Ctx, src : Source, station : String, port : Int) -> Unit {
  let t = @sf.theme()
  let v = (src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value
  let all = items(v, "resources")
  let row = fn(rr : Json?) {
    let failed = text(rr, "error") != "" || number(rr, "status") >= 400.0
    let color = if failed { t.p.red } else { t.p.muted }
    let ended = field(rr, "ended") is Some(Number(_, ..))
    c.box(w=Fill(1.0), pt=6.0, pb=6.0, fn() {
      c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
        c.box(w=Fill(1.0), fn() { c.text(text(rr, "path"), size=@sf.theme().t.meta, color~, max_lines=1) |> ignore }) |> ignore
        c.text(
          if !ended {
            svc("common.reading")
          } else if text(rr, "error") != "" {
            svc("android-chat.load.failed")
          } else {
            number(rr, "status").to_int().to_string()
          },
          size=@sf.theme().t.caption,
          color~,
          wrap=false,
        )
        |> ignore
        if ended {
          let ms = dmax(0.0, number(rr, "ended") - number(rr, "since")).to_int64()
          c.text("\{ms} ms", size=@sf.theme().t.caption, color~, wrap=false) |> ignore
        }
      })
      |> ignore
      if text(rr, "error") != "" {
        c.text(text(rr, "error"), size=@sf.theme().t.caption, color~) |> ignore
      }
    })
    |> ignore
  }
  let rows = fn() {
    for r in all {
      row(Some(r))
    }
  }
  // (its words on the panel's words' line wherever it is drawn)
  c.box(style=@sf.panel_words_in(), w=Fill(1.0), fn() {
    c.text(svc("android-chat.load.note"), size=t.t.caption, color=t.p.muted) |> ignore
    c.box(w=Fill(1.0), pt=12.0, fn() {
      if number(v, "total") <= 0.0 {
        c.text(svc("android-chat.load.waiting"), size=t.t.meta, color=t.p.muted) |> ignore
      }
      c.capped("service/load", dmin(load_list_most, load_list_share * c.window_size().1), rows) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The resources' list at most: 320, 55% of the window where that is less.
let load_list_most : Double = 320.0

///|
let load_list_share : Double = 0.55

///|
fn load_label(v : Json?) -> String {
  let n = fn(k : String) { number(v, k).to_int().to_string() }
  if number(v, "failed") > 0.0 {
    svc("android-chat.load.label.failed", args=[
      ("percent", n("percent")),
      ("finished", n("finished")),
      ("total", n("total")),
      ("failed", n("failed")),
    ])
  } else {
    svc("android-chat.load.label", args=[("percent", n("percent")), ("finished", n("finished")), ("total", n("total"))])
  }
}

// ── a visualization as a page of its own (Preview.kt PreviewFileScreen) ─

///|
// kept across runs: a value (no field of it changes)
pub let file_wait : @ui.Style = @ui.css("w=Full px=S5 py=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let file_name_box : @ui.Style = @ui.css("w=Full clip")

///|
// kept across runs: a value (no field of it changes)
let file_name_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)



///|
/// Where it says so (Restart): at the stage's foot, in its middle, 20 over it.
// kept across runs: a value (no field of it changes)
let service_restart_room : @ui.Style = @ui.css("w=Full h=Full pb=S5 align=ACenter justify=JEnd")

///|
/// How far the page's resources came, each of them (PreviewLoad.tsx's list), beside the ring that opened it: a
/// sheet with touch short of Large.
fn service_load_panel(src : Source, station : String, port : Int, from : @sf.Anchor) -> Unit {
  let words = fn() {
    load_label((src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value)
  }
  @sf.panel(words(), fn(c, _) { load_list(c, src, station, port) }, from~, live=fn() { (words(), "", "") })
}

///|
/// The page's sizes (ViewportSize.tsx's choices: 自适应, a phone's to a desktop's, 自定义 typed, turned), beside what
/// opened them; one chosen, they go.
pub fn service_sizes_panel(key : String, from : @sf.Anchor) -> Unit {
  @sf.panel(svc("android-chat.preview.size.title"), fn(c, close) { page_sizes(c, key, close) }, from~, focus=false)
}

