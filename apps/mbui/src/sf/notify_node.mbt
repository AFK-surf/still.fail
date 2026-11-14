// 通知's parts as nodes of the window's tree, made once (Notifications.tsx, Notifications.css.ts; notifications.mbt's
// old view): the preview of this device's system as the settings make it, the ways of telling as tiles, the kinds of
// thing told of, each opened to its ways.

///|
/// How this device's system shows the app's notifications, as the preview and the tiles draw it: macOS a banner in the
/// screen's top right corner and the app's icon in the Dock; Windows a banner in the bottom right corner over the
/// taskbar; a phone's system a banner across the top under the status bar and the app's icon among the home screen's at
/// the foot, its camera iOS's island (`island`) or Android's hole.
pub(all) enum NoticeLook {
  MacOS
  Windows
  Phone(island~ : Bool)
}

///|
/// What the preview's app icon carries: the number the app puts on it (where the system shows it), the system's own
/// dot (a phone's launcher's, while a notification of the app shows), or nothing.
pub(all) enum IconMark {
  Count(Int)
  Dot
  Unmarked
}

///|
/// The preview (Preview, notify_preview's) in `parent`: a small screen of this device's system (`look`) as the settings
/// make it, 200 high, 28 under it, `w` across (its ground's gradient worked out for it): the banner (`title`, `body`)
/// where `banner` says one comes, the app's icon (the picture `icon`) among others with what it carries (`mark`). Read
/// out a picture said `label`.
#callsite(autofill(loc))
pub fn notify_preview_node(
  parent : @view.View,
  look : NoticeLook,
  w : () -> Double,
  banner : () -> Bool,
  title : () -> String,
  body : () -> String,
  mark : () -> IconMark,
  icon : String,
  label : () -> String,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(room) {
    room.padding(Is((0.0, 0.0, 0.0, notify_preview_foot))) |> ignore
    room.box(fn(v) {
      v
      .height(Is(Some(notify_screen_h)))
      .clips(Is(true))
      .radius(By(fn() { @ui.tree_theme().corner(Xl4) }))
      .says(By(fn() { Some(@view.said(Image, label=label())) }))
      |> ignore
      match look {
        Phone(island~) => notify_device_node(v, w, island, banner, title, body, mark, icon)
        _ => {
          // (its ground the web's linear-gradient(150deg, blue-bg, accent-bg): as wide as the preview by its height)
          notify_gradient_node(v, w, fn() { notify_screen_h }, fn() { notify_screen_corner })
          // (shown over the screen, as what it holds is)
          v.show(banner, fn(b) {
            b.over(Is(true)) |> ignore
            b.box(fn(at) {
              at.over(Is(true)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Start))) |> ignore
              if look is Windows {
                // (in the bottom right corner, over the taskbar)
                at.lines_up(Is(Some(End))).padding(Is((0.0, 0.0, notify_banner_in, notify_taskbar_h + notify_banner_in))) |> ignore
              } else {
                at.padding(Is((0.0, notify_banner_in, notify_banner_in, 0.0))) |> ignore
              }
              notify_banner_node(at, title, body, icon, across=false)
            })
            |> ignore
          })
          v.box(fn(at) {
            at.over(Is(true)).row(Is(true)).lies_along(Is(Middle)).lines_up(Is(Some(End))) |> ignore
            if look is Windows {
              // Windows' taskbar: the whole width at the screen's foot, its icons in its middle
              at.box(fn(bar) {
                bar
                .row(Is(true))
                .grow(Is(1.0))
                .height(Is(Some(notify_taskbar_h)))
                .gap(Is(notify_icons_gap))
                .lines_up(Is(Some(Middle)))
                .lies_along(Is(Middle))
                .ground(By(fn() { alpha(@ui.tree_theme().color(Raised), 0.7) }))
                |> ignore
                notify_icons_node(bar, notify_dock_icon, fn() { @ui.tree_theme().corner(Lg) }, mark, icon)
              })
              |> ignore
            } else {
              // the Dock, 10 up from the screen's foot
              at.padding(Is((0.0, 0.0, 0.0, notify_dock_bottom))) |> ignore
              at.box(fn(dock) {
                dock
                .row(Is(true))
                .padding(Is((notify_dock_in, notify_dock_in, notify_dock_in, notify_dock_in)))
                .gap(Is(notify_icons_gap))
                .radius(By(fn() { @ui.tree_theme().corner(Xl1_5) }))
                .ground(By(fn() { alpha(@ui.tree_theme().color(Raised), 0.7) }))
                |> ignore
                notify_icons_node(dock, notify_dock_icon, fn() { @ui.tree_theme().corner(Lg) }, mark, icon)
              })
              |> ignore
            }
          })
          |> ignore
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A phone's system's preview (device_preview's): the device itself, a tablet where a tablet's frame has the room, else
/// a phone's at most, 32 at least from the preview's sides and 20 under its top, as high as the preview (its foot out
/// of it); its frame 6 round its screen; on the screen the status bar, its camera, the home screen's first row of
/// icons, the banner across the top over them. The preview round it the card's ground.
#callsite(autofill(loc))
fn notify_device_node(
  v : @view.View,
  w : () -> Double,
  island : Bool,
  banner : () -> Bool,
  title : () -> String,
  body : () -> String,
  mark : () -> IconMark,
  icon : String,
  loc~ : SourceLoc,
) -> Unit {
  let device_w = fn() {
    let room = w() - 2.0 * notify_device_side
    if room >= notify_tablet_w {
      notify_tablet_w
    } else if room >= notify_phone_w {
      notify_phone_w
    } else {
      room
    }
  }
  v.ground(By(fn() { @ui.tree_theme().color(Card) })).row(Is(true)).lies_along(Is(Middle)).lines_up(Is(Some(Start))) |> ignore
  v.box(made_for=loc, fn(frame) {
    frame
    .margin(Is((0.0, notify_device_top, 0.0, 0.0)))
    .width(By(fn() { Some(device_w()) }))
    .height(Is(Some(notify_screen_h)))
    .padding(Is((notify_device_bezel, notify_device_bezel, notify_device_bezel, notify_device_bezel)))
    .radius(By(fn() { @ui.tree_theme().corner(Xl4) }))
    .ground(By(fn() { @ui.tree_theme().color(Fg) }))
    |> ignore
    frame.box(fn(screen) {
      screen.grow(Is(1.0)).clips(Is(true)).radius(By(fn() { @ui.tree_theme().corner(Xl2) })) |> ignore
      // (its wallpaper the preview's ground as it was)
      notify_gradient_node(
        screen,
        fn() { device_w() - 2.0 * notify_device_bezel },
        fn() { notify_screen_h - 2.0 * notify_device_bezel },
        fn() { @ui.tree_theme().corner(Xl2) },
      )
      // its status bar: its time at the start, its battery at the end
      screen.box(fn(s) {
        s
        .over(Is(true))
        .row(Is(true))
        .height(Is(Some(notify_status_h)))
        .padding(Is((notify_status_in, 0.0, notify_status_in, 0.0)))
        .lines_up(Is(Some(Middle)))
        |> ignore
        s.box(fn(n) {
          n.grow(Is(1.0)) |> ignore
          words_node(n, fn() { notify_status_time }, fn() { notify_status_words }) |> ignore
        })
        |> ignore
        s.box(fn(b) {
          b
          .width(Is(Some(notify_battery_w)))
          .height(Is(Some(notify_battery_h)))
          .radius(By(fn() { @ui.tree_theme().corner(Sm) }))
          .ground(By(fn() { @ui.tree_theme().color(Fg) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // its camera in the middle of it: iOS's island, Android's hole
      screen.box(fn(at) {
        at.over(Is(true)).row(Is(true)).lies_along(Is(Middle)).padding(Is((0.0, notify_camera_top, 0.0, 0.0))) |> ignore
        at.box(fn(cam) {
          let (cw, ch) = if island { (notify_island_w, notify_island_h) } else { (notify_hole_side, notify_hole_side) }
          cam
          .width(Is(Some(cw)))
          .height(Is(Some(ch)))
          .radius(Is(ch / 2.0))
          .ground(By(fn() { @ui.tree_theme().color(Fg) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // the home screen's first row of icons, 24 apart, in the middle
      screen.box(fn(at) {
        at
        .over(Is(true))
        .row(Is(true))
        .lies_along(Is(Middle))
        .gap(Is(notify_home_gap))
        .padding(Is((0.0, notify_home_top, 0.0, 0.0)))
        |> ignore
        notify_icons_node(at, notify_home_icon, fn() { @ui.tree_theme().corner(Lg) }, mark, icon)
      })
      |> ignore
      // the banner across the top under the status bar, a phone's width at most
      screen.show(banner, fn(b) {
        b.over(Is(true)) |> ignore
        b.box(fn(at) {
          at
          .over(Is(true))
          .row(Is(true))
          .lies_along(Is(Middle))
          .lines_up(Is(Some(Start)))
          .padding(Is((notify_banner_side, notify_status_h, notify_banner_side, 0.0)))
          |> ignore
          notify_banner_node(at, title, body, icon, across=true)
        })
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// A banner (banner): the app's icon, the chat's title with when, what it says in two lines at most; 12 by 10 in, 10
/// between the icon and the words, 16 round, on what floats, a soft shadow; 320 across, or (`across`) as wide as its
/// room up to 400.
#callsite(autofill(loc))
fn notify_banner_node(
  parent : @view.View,
  title : () -> String,
  body : () -> String,
  icon : String,
  across~ : Bool,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(b) {
    b
    .row(Is(true))
    .padding(Is((notify_banner_x, notify_banner_y, notify_banner_x, notify_banner_y)))
    .gap(Is(notify_banner_gap))
    .lines_up(Is(Some(Start)))
    .radius(By(fn() { @ui.tree_theme().corner(Xl1_5) }))
    .ground(By(fn() { @ui.tree_theme().color(Raised) }))
    .shadow(By(fn() { (2.0, 1.0, @ui.tree_theme().shadow) }))
    |> ignore
    if across {
      b.grow(Is(1.0)).max_width(Is(Some(notify_banner_across_most))) |> ignore
    } else {
      b.width(Is(Some(notify_banner_w))) |> ignore
    }
    notify_app_icon_node(b, notify_banner_icon, icon)
    b.box(fn(col) {
      col.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(notify_banner_lines)) |> ignore
      col.box(fn(h) {
        h.row(Is(true)).gap(Is(notify_banner_head_gap)) |> ignore
        h.box(fn(n) {
          n.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
          words_node(n, title, fn() { notify_banner_title }) |> ignore
        })
        |> ignore
        words_node(h, fn() { t("web-pages.notifications.now") }, fn() { notify_banner_muted }) |> ignore
      })
      |> ignore
      words_node(col, body, fn() { notify_banner_body }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Apps' icons in a row (icons_with_mine's): two of the line's grey (`corner` round), then the app's own with its mark
/// (the number in a red capsule at its top right corner, or the system's red dot a little over it), then another;
/// `side` square each.
#callsite(autofill(loc))
fn notify_icons_node(
  parent : @view.View,
  side : Double,
  corner : () -> Double,
  mark : () -> IconMark,
  icon : String,
  loc~ : SourceLoc,
) -> Unit {
  let other = fn(p : @view.View) {
    p.box(fn(o) {
      o
      .width(Is(Some(side)))
      .height(Is(Some(side)))
      .radius(By(corner))
      .ground(By(fn() { @ui.tree_theme().color(Line) }))
      |> ignore
    })
    |> ignore
  }
  other(parent)
  other(parent)
  parent.box(made_for=loc, fn(mine) {
    mine.width(Is(Some(side))).height(Is(Some(side))) |> ignore
    notify_app_icon_node(mine, side, icon)
    mine.show(fn() { mark() is Count(_) }, fn(m) {
      m.over(Is(true)) |> ignore
      m.box(fn(at) {
        at
        .over(Is(true))
        .row(Is(true))
        .lies_along(Is(End))
        .lines_up(Is(Some(Start)))
        |> ignore
        at.box(fn(badge) {
          badge
          .offset(Is((-notify_count_right, notify_count_top)))
          .row(Is(true))
          .min_width(Is(Some(notify_count_least)))
          .height(Is(Some(notify_count_least)))
          .padding(Is((notify_count_in, 0.0, notify_count_in, 0.0)))
          .radius(Is(notify_count_least / 2.0))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .ground(By(fn() { @ui.tree_theme().color(Danger) }))
          |> ignore
          words_node(
            badge,
            fn() {
              match mark() {
                Count(n) => if n > 99 { "99+" } else { n.to_string() }
                _ => ""
              }
            },
            fn() { notify_count_words },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    mine.show(fn() { mark() is Dot }, fn(m) {
      m.over(Is(true)) |> ignore
      m.box(fn(at) {
        at.over(Is(true)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Start))) |> ignore
        at.box(fn(dot) {
          dot
          .offset(Is((-notify_dot_at, notify_dot_at)))
          .width(Is(Some(notify_dot_side)))
          .height(Is(Some(notify_dot_side)))
          .radius(Is(notify_dot_side / 2.0))
          .ground(By(fn() { @ui.tree_theme().color(Danger) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
  other(parent)
}

///|
/// The app's own icon (app_icon's: the picture `icon`, `side` square, 22% round: Md).
#callsite(autofill(loc))
fn notify_app_icon_node(parent : @view.View, side : Double, icon : String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(i) {
    i
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .clips(Is(true))
    .radius(By(fn() { @ui.tree_theme().corner(Md) }))
    |> ignore
    // (the picture in what cuts it to its corners: View::picture, as wide as its box)
    i.box(fn(pic) { pic.grow(Is(1.0)).picture(Is(drawable_vector(icon))) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// The preview's ground (gradient's, as a node): the web's linear-gradient(150deg, blue-bg, accent-bg) worked out for a
/// box `w` by `h`, over all of `parent`, `corner` round.
#callsite(autofill(loc))
fn notify_gradient_node(
  parent : @view.View,
  w : () -> Double,
  h : () -> Double,
  corner : () -> Double,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(g) {
    g
    .over(Is(true))
    .radius(By(corner))
    .image(By(fn() {
      let p = theme().p
      Some((gradient_key(w(), h(), notify_screen_angle, p.blue_bg, p.accent_bg), "", gradient_px))
    }))
    |> ignore
  })
  |> ignore
}

///|
/// The ways of telling side by side (way_tiles: 10 apart, as wide as they share), made by `tiles`.
#callsite(autofill(loc))
pub fn way_tiles_node(parent : @view.View, tiles : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(r) {
    r.row(Is(true)).gap(Is(notify_tiles_gap)) |> ignore
    tiles(r)
  })
  |> ignore
}

///|
/// What a way's tile draws small of how it tells: the banner, or the app's icon with its badge.
pub(all) enum WayPicture {
  BannerWay
  BadgeWay
}

///|
/// One way of telling as a tile (Tile, way_tile's): a picture of it on this system (`look`), its `name`, on or off
/// (`state`); while `action` says the system has to allow it first, ringed in red, its picture marked, a red capsule
/// across its foot saying so; `busy`, a spinner in their place. On, ringed in the accent. Pressed, `press`; read out a
/// button named `name`, pressed while on.
#callsite(autofill(loc))
pub fn way_tile_node(
  parent : @view.View,
  look : NoticeLook,
  way : WayPicture,
  name : () -> String,
  state : () -> String,
  on : () -> Bool,
  action : () -> String,
  busy : () -> Bool,
  press : () -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let lit = fn() { on() && action() == "" }
  @headless.toggle(made_for=loc, parent, Button, name, lit, fn(_) { press() }, fn(t, _) {
    t
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .padding(By(fn() {
      let foot = if action() != "" { card_foot_in(notify_action_h) } else { notify_tile_foot }
      (notify_tile_x, notify_tile_top, notify_tile_x, foot)
    }))
    .gap(Is(notify_tile_gap))
    .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
    .ground(By(fn() { @ui.tree_theme().color(Card) }))
    .edge(By(fn() {
      let th = @ui.tree_theme()
      (
        notify_tile_ring,
        if action() != "" {
          alpha(th.color(Danger), 0.55)
        } else if lit() {
          th.color(Accent)
        } else {
          0L
        },
      )
    }))
    |> ignore
    // (its parts in its middle, its way to allow it across it)
    // its picture: a screen drawn small
    middle_of(t, fn(at) { at.box(fn(p) {
      p
      .width(Is(Some(notify_pic_w)))
      .height(Is(Some(notify_pic_h)))
      .margin(Is((0.0, 0.0, 0.0, notify_tile_gap)))
      .clips(Is(true))
      .radius(By(fn() { @ui.tree_theme().corner(Lg) }))
      .ground(By(fn() { @ui.tree_theme().color(Bg) }))
      .edge(By(fn() { (1.0, @ui.tree_theme().color(Line)) }))
      |> ignore
      p.box(fn(at) {
        at.over(Is(true)) |> ignore
        match (way, look) {
          (BannerWay, Phone(..)) => {
            at.padding(Is((notify_pic_in, notify_pic_in, notify_pic_in, 0.0))) |> ignore
            notify_pic_block(at, None, notify_pic_banner_h, Base, Border)
          }
          (BannerWay, Windows) => {
            at.row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(End))).padding(Is((0.0, 0.0, notify_pic_in, notify_pic_in))) |> ignore
            notify_pic_block(at, Some(notify_pic_banner_w), notify_pic_banner_h, Base, Border)
          }
          (BannerWay, MacOS) => {
            at.row(Is(true)).lies_along(Is(End)).padding(Is((0.0, notify_pic_in, notify_pic_in, 0.0))) |> ignore
            notify_pic_block(at, Some(notify_pic_banner_w), notify_pic_banner_h, Base, Border)
          }
          (BadgeWay, _) => {
            at.row(Is(true)).lines_up(Is(Some(End))).padding(Is((notify_pic_app_left, 0.0, 0.0, notify_pic_in))) |> ignore
            at.box(fn(app) {
              app
              .width(Is(Some(notify_pic_app)))
              .height(Is(Some(notify_pic_app)))
              .radius(By(fn() { @ui.tree_theme().corner(Md) }))
              .ground(By(fn() { @ui.tree_theme().color(Accent) }))
              |> ignore
              app.box(fn(b) {
                b
                .over(Is(true))
                .row(Is(true))
                .lies_along(Is(End))
                .lines_up(Is(Some(Start)))
                |> ignore
                b.box(fn(dot) {
                  dot
                  .offset(Is((-notify_pic_badge_right, notify_pic_badge_top)))
                  .width(Is(Some(notify_pic_badge)))
                  .height(Is(Some(notify_pic_badge)))
                  .radius(Is(notify_pic_badge / 2.0))
                  .ground(By(fn() { @ui.tree_theme().color(Danger) }))
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        }
      })
      |> ignore
      // (the system to allow it first: its mark a little under the middle)
      p.show(fn() { action() != "" }, fn(a) {
        a.over(Is(true)) |> ignore
        a.box(fn(at) {
          at
          .over(Is(true))
          .row(Is(true))
          .lies_along(Is(Middle))
          .lines_up(Is(Some(Middle)))
          .padding(Is((0.0, notify_alert_down, 0.0, 0.0)))
          |> ignore
          at.box(fn(m) {
            m
            .row(Is(true))
            .width(Is(Some(notify_pic_app)))
            .height(Is(Some(notify_pic_app)))
            .radius(Is(notify_pic_app / 2.0))
            .lines_up(Is(Some(Middle)))
            .lies_along(Is(Middle))
            .ground(By(fn() { @ui.tree_theme().color(Danger) }))
            |> ignore
            // (part of the mark: at its size whatever the system's size of words)
            mark_words_node(m, fn() { "!" }, fn() { notify_alert_words }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore })
    middle_of(t, fn(at) { words_node(at, name, fn() { notify_tile_name }) |> ignore })
    t.pick(fn() { if busy() { 0 } else if action() != "" { 1 } else { 2 } }, fn(s, what) {
      match what {
        0 => middle_of(s, fn(at) { spinner_node(at, size=spinner_inline) |> ignore })
        1 =>
          s.box(fn(btn) {
            btn
            .row(Is(true))
            .height(Is(Some(notify_action_h)))
            .margin(Is((card_foot_in(notify_action_h) - notify_tile_x, notify_tile_gap, card_foot_in(notify_action_h) - notify_tile_x, 0.0)))
            .padding(Is((notify_action_x, 0.0, notify_action_x, 0.0)))
            .gap(Is(1.0))
            .lines_up(Is(Some(Middle)))
            .lies_along(Is(Middle))
            .radius(Is(notify_action_h / 2.0))
            .ground(By(fn() { @ui.tree_theme().color(Danger) }))
            |> ignore
            words_node(btn, action, fn() { notify_action_words }) |> ignore
            icon_node(btn, "chevron-right", notify_action_chevron, By(fn() { theme().p.on_primary })) |> ignore
          })
          |> ignore
        _ => middle_of(s, fn(at) { words_node(at, state, fn() { notify_tile_state }) |> ignore })
      }
    })
  })
  |> ignore
}

///|
/// What `make` makes in the middle of `parent`'s width.
#callsite(autofill(loc))
fn middle_of(parent : @view.View, make : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(m) {
    m.row(Is(true)).lies_along(Is(Middle)) |> ignore
    make(m)
  })
  |> ignore
}

///|
/// A block of a tile's picture: `w` across (None: as wide as the column it is in), `h` high, `corner` round, of `ink`.
#callsite(autofill(loc))
fn notify_pic_block(
  parent : @view.View,
  w : Double?,
  h : Double,
  corner : @ui.Radius,
  ink : @ui.Color,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(b) {
    b
    .height(Is(Some(h)))
    .radius(By(fn() { @ui.tree_theme().corner(corner) }))
    .ground(By(fn() { @ui.tree_theme().color(ink) }))
    |> ignore
    // (None: stretched across the column it is in)
    match w {
      Some(w) => b.width(Is(Some(w))) |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// The kinds of thing told of on a card (kinds_card: 20 at the sides, 6 over and under), its rows made by `rows`, apart
/// by their room.
#callsite(autofill(loc))
pub fn kinds_card_node(parent : @view.View, rows : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(k) {
    k
    .padding(Is((card_pad, notify_kinds_y, card_pad, notify_kinds_y)))
    .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
    .ground(By(fn() { @ui.tree_theme().color(Card) }))
    |> ignore
    rows(k)
  })
  |> ignore
}

///|
/// A kind of thing that happens (KindRow, kind_row's): its `title`, what tells of it (`sum`) at that line's end, a
/// chevron turned down while `open`; what it is (`note`) under it across the row. Pressed, `toggle`; read out a button
/// named `title`, expanded while open. Opened, its ways (`ways` makes them: 4 apart, 14 in and under).
#callsite(autofill(loc))
pub fn kind_row_node(
  parent : @view.View,
  title : () -> String,
  sum : () -> String,
  note : () -> String,
  open : () -> Bool,
  toggle : () -> Unit,
  ways : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  @headless.disclosure(made_for=loc, parent, title, open, fn(_) { toggle() }, fn(head, _) {
    head
    .padding(Is((0.0, notify_kind_y, 0.0, notify_kind_y)))
    .gap(Is(notify_kind_lines))
    |> ignore
    head.box(fn(top) {
      top.row(Is(true)).gap(Is(notify_kind_gap)).lines_up(Is(Some(Middle))) |> ignore
      top.box(fn(t) {
        t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        words_node(t, title, fn() { notify_kind_title }) |> ignore
      })
      |> ignore
      words_node(top, sum, fn() { notify_kind_sum }) |> ignore
      icon_node(top, "chevron-right", notify_kind_chevron, By(fn() { theme().p.muted }), name_now=fn() {
        if open() {
          "chevron-down"
        } else {
          "chevron-right"
        }
      })
      |> ignore
    })
    |> ignore
    words_node(head, note, fn() { notify_kind_note }) |> ignore
  })
  |> ignore
  parent.show(open, fn(o) {
    o.box(fn(w) {
      w.padding(Is((notify_ways_in, 0.0, 0.0, notify_ways_in))).gap(Is(notify_ways_gap)) |> ignore
      ways(w)
    })
    |> ignore
  })
}

///|
/// A way of a kind (WayRow, way_switch's): its `title` at the start, `control` made at the end, 32 high at least, 12
/// apart.
#callsite(autofill(loc))
pub fn way_row_node(
  parent : @view.View,
  title : () -> String,
  control : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(r) {
    r.row(Is(true)).min_height(Is(Some(notify_way_least))).gap(Is(notify_kind_gap)).lines_up(Is(Some(Middle))) |> ignore
    r.box(fn(t) {
      t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      words_node(t, title, fn() { notify_way_words }) |> ignore
    })
    |> ignore
    control(r)
  })
  |> ignore
}

///|
let notify_screen_h : Double = 200.0

///|
let notify_preview_foot : Double = 28.0

///|
/// The ground's own corner under the screen's (screen_corner: 28, the screen cutting it at its own 24).
let notify_screen_corner : Double = 28.0

///|
let notify_screen_angle : Double = 150.0

///|
let notify_banner_in : Double = 12.0

///|
let notify_banner_w : Double = 320.0

///|
let notify_banner_across_most : Double = 400.0

///|
let notify_banner_x : Double = 12.0

///|
let notify_banner_y : Double = 10.0

///|
let notify_banner_gap : Double = 10.0

///|
let notify_banner_lines : Double = 2.0

///|
let notify_banner_head_gap : Double = 8.0

///|
let notify_banner_icon : Double = 28.0

///|
let notify_taskbar_h : Double = 44.0

///|
let notify_dock_icon : Double = 30.0

///|
let notify_dock_bottom : Double = 10.0

///|
let notify_dock_in : Double = 6.0

///|
let notify_icons_gap : Double = 10.0

///|
let notify_count_top : Double = -6.0

///|
let notify_count_right : Double = -8.0

///|
let notify_count_least : Double = 18.0

///|
let notify_count_in : Double = 5.0

///|
let notify_dot_at : Double = -3.0

///|
let notify_dot_side : Double = 10.0

///|
let notify_phone_w : Double = 300.0

///|
let notify_tablet_w : Double = 520.0

///|
let notify_device_side : Double = 32.0

///|
let notify_device_top : Double = 20.0

///|
let notify_device_bezel : Double = 6.0

///|
let notify_status_h : Double = 24.0

///|
let notify_status_in : Double = 22.0

///|
let notify_status_time : String = "9:41"

///|
let notify_battery_w : Double = 18.0

///|
let notify_battery_h : Double = 9.0

///|
let notify_camera_top : Double = 8.0

///|
let notify_hole_side : Double = 8.0

///|
let notify_island_w : Double = 36.0

///|
let notify_island_h : Double = 11.0

///|
let notify_banner_side : Double = 8.0

///|
let notify_home_icon : Double = 36.0

///|
let notify_home_top : Double = 100.0

///|
let notify_home_gap : Double = 24.0

///|
let notify_tiles_gap : Double = 10.0

///|
/// A tile (tile: 14 over, 10 at the sides, 12 under, its parts 4 apart in its middle; a ring of 2).
let notify_tile_top : Double = 14.0

///|
let notify_tile_x : Double = 10.0

///|
let notify_tile_foot : Double = 12.0

///|
let notify_tile_gap : Double = 4.0

///|
let notify_tile_ring : Double = 2.0

///|
/// A tile's picture (72 by 46, 4 over its name): a banner 5 in (38 by 11), the app's icon at its foot (18, 26 from its
/// start, a red dot 9 at its corner), the mark that it has to be allowed (18, 8 under the middle).
let notify_pic_w : Double = 72.0

///|
let notify_pic_h : Double = 46.0

///|
let notify_pic_in : Double = 5.0

///|
let notify_pic_banner_w : Double = 38.0

///|
let notify_pic_banner_h : Double = 11.0

///|
let notify_pic_app : Double = 18.0

///|
let notify_pic_app_left : Double = 26.0

///|
let notify_pic_badge : Double = 9.0

///|
let notify_pic_badge_top : Double = -4.0

///|
let notify_pic_badge_right : Double = -5.0

///|
let notify_alert_down : Double = 8.0

///|
/// The way to allow it (tileAction: 26 high, 12 in, its words and chevron 1 apart, round, red).
let notify_action_h : Double = 26.0

///|
let notify_action_x : Double = 12.0

///|
let notify_action_chevron : Double = 14.0

///|
let notify_kinds_y : Double = 6.0

///|
let notify_kind_y : Double = 12.0

///|
let notify_kind_lines : Double = 2.0

///|
let notify_kind_gap : Double = 12.0

///|
let notify_kind_chevron : Double = 16.0

///|
let notify_ways_in : Double = 14.0

///|
let notify_ways_gap : Double = 4.0

///|
let notify_way_least : Double = 32.0

///|
// kept across runs: a value (no field of it changes)
let notify_banner_title : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_banner_muted : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_banner_body : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, w=Full, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let notify_count_words : @ui.TextStyle = @ui.text_style(size=Caption, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_status_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_alert_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_tile_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_tile_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_action_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_kind_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let notify_kind_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let notify_kind_sum : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let notify_way_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg)
