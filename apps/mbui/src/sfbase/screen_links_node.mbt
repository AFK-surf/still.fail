// Links to a station's screens, its web services and its 共享调试 in an agent's words (screen_links.mbt's) as nodes of
// the window's tree, made once: a link alone in a paragraph its card (a capsule as a file's, a screen its station
// previews live in a card of its own, 共享调试 a card that asks), one bare within a sentence its title. A preview held
// while its card's node lives (peeks_node_held: peeks_settle starts and stops it as the frames go), its pictures drawn as
// they come and are decoded.

///|
/// The links to screens in message `message`'s words as a chat draws them in the window's tree (screen_links'): their
/// cards, and a bare one's title.
pub fn screen_links_node(src : Source, message : () -> String) -> @sf.ScreensNode {
  {
    card: fn(v, href, to, words) {
      match to.card {
        "adb" => adb_link_card_node(v, src, to, words)
        "service" => service_link_card_node(v, src, href, to, words)
        _ => screen_link_card_node(v, src, @signals.untracked(message) + "\n" + href, href, to, words)
      }
    },
    title: fn(_href, to) {
      if to.card == "adb" {
        adb_title(src, to)
      } else if to.card == "service" {
        service_card_of(src, to).0
      } else {
        match screen_card_of(src, to) {
          Some(card) => card.title
          None => @sf.t("android-misc.screen.title")
        }
      }
    },
  }
}

///|
/// The cards' previews held by a node of the window's tree, by card (peeks_settle's `held`): how many nodes hold each.
pub let peeks_node_held : Map[String, Int] = {}

///|
/// Told as a preview's pictures change (peek_took's, peeks_settle's): what draws them follows.
pub let peeks_told : @signals.Signal[Int] = @signals.signal(0)

///|
/// A link's card as a capsule (link_card's) in `v`: 236 wide, a row high, round, on the neutral ground, its `mark`
/// (none: its room kept) and its two lines; pressed, its link opened.
fn link_capsule_node(
  v : @view.View,
  href : String,
  mark : () -> LinkMark?,
  title : () -> String,
  line : () -> String,
  gone : () -> Bool,
) -> Unit {
  v.box(fn(card) {
    card
    .row(Is(true))
    .width(Is(Some(236.0)))
    .height(Is(Some(52.0)))
    .padding(Is((14.0, 0.0, @sf.file_capsule_words_end, 0.0)))
    .gap(Is(8.0))
    .lines_up(Is(Some(Middle)))
    .radius(Is(26.0))
    .ground(By(fn() { @ui.tree_theme().color(Neutral) }))
    .says(By(fn() { Some(@view.said(Link, label=title())) }))
    |> ignore
    @sf.presses_node(card, fn() { open_link(href) })
    link_mark_node(card, mark)
    link_words_node(card, title, line, gone)
  })
  |> ignore
}

///|
/// A mark in its room (link_mark's), 24, in the muted ink; none while what it is is not known.
fn link_mark_node(parent : @view.View, mark : () -> LinkMark?) -> Unit {
  parent.box(fn(m) {
    m.width(Is(Some(24.0))).height(Is(Some(24.0))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    m.pick(fn() { mark().map(fn(k) { k.name }).unwrap_or("") }, fn(i, name) {
      if name != "" {
        @sf.icon_node(i, name, 24.0, By(fn() { @ui.tree_theme().color(Muted) })) |> ignore
      }
    })
  })
  |> ignore
}

///|
/// A card's two lines (link_card_words'): its title (one line, 20 high; quieter where `gone`) over what is said of it
/// (16 high), what is left across.
fn link_words_node(parent : @view.View, title : () -> String, line : () -> String, gone : () -> Bool) -> Unit {
  parent.box(fn(w) {
    w.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    w.box(fn(t) {
      t.height(Is(Some(20.0))) |> ignore
      t.box(fn(x) {
        let style = fn() { if gone() { link_title_gone } else { link_title } }
        x.words(By(title)).words_look(By(fn() { @ui.style_words(style()) })).ink(By(fn() { @ui.style_ink(style()) })) |> ignore
      })
      |> ignore
    })
    |> ignore
    w.box(fn(l) {
      l.height(Is(Some(16.0))) |> ignore
      l.box(fn(x) {
        x.words(By(line)).words_look(By(fn() { @ui.style_words(link_line) })).ink(By(fn() { @ui.style_ink(link_line) })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A screen as a card (screen_link_card's) in `v`, `key` its own: a capsule with its kind's mark, its title (the
/// link's own words, when it has them) over what its station says of it; one its station previews, the screen live
/// across a card's top, the words under it. A tap opens it, as the link does.
fn screen_link_card_node(v : @view.View, src : Source, key : String, href : String, to : @sf.LinkTo, words : String?) -> Unit {
  let card = fn() { screen_card_of(src, to) }
  let title = fn() {
    match (words, card()) {
      (Some(w), _) => w
      (None, Some(k)) => k.title
      (None, None) => ""
    }
  }
  let line = fn() { card().map(fn(k) { k.line }).unwrap_or("") }
  let gone = fn() { card().map(fn(k) { k.gone }).unwrap_or(false) }
  let peeks = fn() { to.card == "screen" && card() is Some(k) && k.peek && !k.gone }
  v.pick(peeks, fn(c, peeking) {
    if !peeking {
      link_capsule_node(c, href, fn() {
        card().map(fn(k) { if k.kind == "browser" { globe_mark } else { monitor_mark } })
      }, title, line, gone)
      return
    }
    // (held as its node lives: peeks_settle starts it while the app shows, stops it as it goes)
    peeks_node_held[key] = peeks_node_held.get(key).unwrap_or(0) + 1
    c.owns(fn() {
      let n = peeks_node_held.get(key).unwrap_or(1) - 1
      if n <= 0 {
        peeks_node_held.remove(key) |> ignore
      } else {
        peeks_node_held[key] = n
      }
    })
    |> ignore
    let p = peek_for(key, to.station, to.screen)
    c.box(fn(k) {
      k
      .width(Is(Some(@sf.peek_card_px)))
      .padding(Is((4.0, 4.0, 4.0, 0.0)))
      .radius(Is(@sf.message_file_corner))
      .ground(By(fn() { @ui.tree_theme().color(Neutral) }))
      .says(By(fn() { Some(@view.said(Link, label=title())) }))
      |> ignore
      @sf.presses_node(k, fn() { open_link(href) })
      // (the screen live: its shape as its picture or its listed size has it, within bounds; its mark till a picture
      // comes, the newest decoded over what came before)
      k.box(fn(f) {
        f
        .aspect(By(fn() {
          peeks_told.get() |> ignore
          let kc = card()
          let mut natural = 0.0
          for pk in p.pictures {
            match @ui.image_natural(pk) {
              Some((w, h)) => natural = if h > 0.0 { w / h } else { 0.0 }
              None => ()
            }
          }
          match p.stream {
            Some(st) =>
              match st.size_told() {
                Some((w, h)) if h > 0 => natural = w.to_double() / h.to_double()
                _ => ()
              }
            None => ()
          }
          let listed = match kc {
            Some(s) if s.width > 0.0 && s.height > 0.0 => s.width / s.height
            _ => 0.0
          }
          let own = if natural > 0.0 { natural } else { listed }
          if kc.map(fn(s) { s.kind }).unwrap_or("") != "browser" && own > 0.0 {
            dclamp(own, peek_ratio_least, peek_ratio_most)
          } else {
            peek_ratio
          }
        }))
        .radius(Is(@ui.concentric(@sf.message_file_corner, 4.0)))
        .ground(By(fn() { @ui.tree_theme().color(Wash) }))
        .clips(Is(true))
        .lines_up(Is(Some(Middle)))
        .lies_along(Is(Middle))
        |> ignore
        link_mark_node(f, fn() { card().map(fn(s) { if s.kind == "browser" { globe_mark } else { monitor_mark } }) })
        f.each(fn() {
          peeks_told.get() |> ignore
          p.pictures.copy()
        }, fn(pk) { pk }, fn(pic, pk) {
          let pk = @signals.untracked(fn() { pk.get() })
          pic
          .over(Is(true))
          .grow(Is(1.0))
          .image(Is(Some((pk, "", 8192))))
          .image_covers(Is(true))
          |> ignore
        })
        f.show(fn() {
          peeks_told.get() |> ignore
          p.stream is Some(_)
        }, fn(pic) {
          pic.over(Is(true)).grow(Is(1.0)) |> ignore
          @ui.stream_node(pic, fn() { p.stream }, fit=FitCoverAt(0.0))
        })
      })
      |> ignore
      k.box(fn(w) {
        w.padding(Is((16.0, 12.0, 16.0, 16.0))) |> ignore
        link_words_node(w, title, line, gone)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// A link to a chat's web service as a card (service_link_card's) in `v`: the web's mark, its title (the link's own
/// words, when it has them) over its station and port and how it stands; one no longer up, its title quieter.
fn service_link_card_node(v : @view.View, src : Source, href : String, to : @sf.LinkTo, words : String?) -> Unit {
  link_capsule_node(v, href, fn() { Some(globe_mark) }, fn() {
    match words {
      Some(w) => w
      None => service_card_of(src, to).0
    }
  }, fn() { service_card_of(src, to).1 }, fn() { service_card_of(src, to).2 })
}

///|
/// A station's 共享调试 asked for (adb_link_card's) in `v`, as a card that asks: whether its agents may debug this
/// device. Lent there, how that stands with 详情 and 停止共享; else where the phone has all it takes 共享 (and 详情),
/// where it lacks something first what and 查看步骤; a device with nothing to lend says why, nothing to press.
fn adb_link_card_node(v : @view.View, src : Source, to : @sf.LinkTo, words : String?) -> Unit {
  ignore(words)
  let station = to.station
  let card = fn() { adb_card_of(src, to) }
  // (what the phone has, asked of its host as the card is made)
  v.reacts(fn() { () }, fn(_) { @settings.adb_phone_ask() })
  let ready = fn() {
    match card() {
      Some(_) as c if flag(c, "lendable") => @settings.adb_ready_now()
      Some(_) as c => @settings.AdbCannot(text(c, "line"))
      None => @settings.AdbUnknown
    }
  }
  let name = fn() {
    let ws = match station.find("/") {
      Some(i) => station.view(end_offset=i).to_owned()
      None => station
    }
    match dv_stations(src, ws).0 {
      Some(list) =>
        match list.iter().find_first(fn(s) { s.station == station }) {
          Some(s) => s.name
          None => @settings.station_name(station)
        }
      None => @settings.station_name(station)
    }
  }
  let stopping = "adb-stop/" + station
  // (0 lent here; 1 cannot; 2 lacks a step; 3 lends; 4 not known yet)
  let way = fn() {
    if flag(card(), "sharing") {
      return 0
    }
    match ready() {
      AdbCannot(_) => 1
      AdbLacks(_) => 2
      AdbLends => 3
      AdbUnknown => 4
    }
  }
  @sf.ask_card_room_node(v, fn(room) {
    @sf.card_node(room, fn(k) {
      k.pick(way, fn(body, w) {
        body.gap(Is(14.0)) |> ignore
        let title = fn() { @sf.t("android-misc.adb.ask.title", args=[("name", name())]) }
        match w {
          0 => {
            @sf.ask_words_node(body, fn() { @sf.t("android-misc.adb.ask.sharing", args=[("name", name())]) }, fn() {
              text(card(), "line")
            })
            |> ignore
            @sf.ask_buttons_node(body, fn(b) {
              @sf.button_node(b, fn() { @sf.t("android-misc.adb.ask.more") }, fn() { open_adb(src, station) }, tone=Primary, at_foot=true) |> ignore
              @sf.button_node(b, fn() { @sf.t("android-misc.adb.ask.stop") }, fn() {
                act(src, @sf.t("android-misc.adb.stopWhat"), stopping, "adb.stop", Json::object({}))
              }, tone=Ghost, busy=fn() { acting.doing.contains(stopping) }, at_foot=true)
              |> ignore
            })
            |> ignore
          }
          1 =>
            @sf.ask_words_node(body, title, fn() {
              match ready() {
                AdbCannot(why) => why
                _ => ""
              }
            })
            |> ignore
          2 => {
            @sf.ask_words_node(body, title, fn() {
              match ready() {
                AdbLacks(step) => @sf.t("android-misc.adb.ask.first", args=[("step", step)])
                _ => ""
              }
            })
            |> ignore
            @sf.ask_buttons_node(body, fn(b) {
              @sf.button_node(b, fn() { @sf.t("android-misc.adb.ask.how") }, fn() { open_adb(src, station) }, tone=Primary, at_foot=true) |> ignore
            })
            |> ignore
          }
          3 => {
            // (lent to another station now: lending it here moves it)
            @sf.ask_words_node(body, title, fn() {
              let now = (src.topic)("adbShare", {}).value
              let elsewhere = flag(now, "sharing") && text(now, "station") != station
              @sf.t(if elsewhere { "android-misc.adb.elsewhere" } else { "android-misc.adb.hour" })
            })
            |> ignore
            @sf.ask_buttons_node(body, fn(b) {
              @sf.button_node(b, fn() { @sf.t("android-misc.adb.ask.share") }, fn() { @settings.adb_lend(station, name()) }, tone=Primary, busy=fn() {
                @settings.adb_asking()
              }, at_foot=true)
              |> ignore
              @sf.button_node(b, fn() { @sf.t("android-misc.adb.ask.more") }, fn() { open_adb(src, station) }, tone=Ghost, at_foot=true) |> ignore
            })
            |> ignore
          }
          // (not known yet what the phone has: the question alone, its answer as it comes)
          _ => @sf.ask_words_node(body, title, fn() { "" }) |> ignore
        }
      })
    })
    |> ignore
  })
  |> ignore
}
